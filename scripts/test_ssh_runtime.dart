import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../lib/ssh/ssh_runtime.dart';
import '../lib/security/privacy.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> refuses(Future<void> Function() action, String message) async {
  try {
    await action();
  } catch (_) {
    return;
  }
  throw StateError(message);
}

Future<void> transfer(AbessSshRuntime runtime, int targetPort) async {
  final socket = await Socket.connect('127.0.0.1', runtime.port);
  final iterator = StreamIterator<Uint8List>(socket);
  final buffer = <int>[];
  Future<List<int>> read(int n) async {
    while (buffer.length < n) {
      check(await iterator.moveNext(), 'SOCKS ended');
      buffer.addAll(iterator.current);
    }
    final value = buffer.sublist(0, n);
    buffer.removeRange(0, n);
    return value;
  }

  socket.add([5, 1, 2]);
  await socket.flush();
  check((await read(2))[1] == 2, 'Authenticated SOCKS required');
  final user = utf8.encode(runtime.localUser),
      pass = utf8.encode(runtime.localPassword);
  socket.add([1, user.length, ...user, pass.length, ...pass]);
  await socket.flush();
  check((await read(2))[1] == 0, 'Local SOCKS authentication');
  socket.add([5, 1, 0, 1, 127, 0, 0, 1, targetPort >> 8, targetPort & 255]);
  await socket.flush();
  check((await read(10))[1] == 0, 'SSH forwarding channel');
  socket.add(
    utf8.encode(
      'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
    ),
  );
  await socket.flush();
  while (await iterator.moveNext()) {
    buffer.addAll(iterator.current);
  }
  check(
    utf8.decode(buffer).contains('ABESS_DART_SSH_REAL_TRAFFIC'),
    'Real HTTP through Dart SOCKS and encrypted SSH',
  );
  await iterator.cancel();
  socket.destroy();
}

Future<void> testXray(
  AbessSshRuntime runtime,
  int targetPort,
  Directory directory,
) async {
  final binary = Platform.environment['SSH_TEST_XRAY_BIN'];
  if (binary == null) return;
  final config = File('${directory.path}/xray.json');
  await config.writeAsString(jsonEncode(runtime.xrayConfig()));
  final process = await Process.start(binary, ['run', '-c', config.path]);
  final engineLog = <int>[];
  process.stdout.listen(engineLog.addAll);
  process.stderr.listen(engineLog.addAll);
  Socket? socket;
  try {
    for (var i = 0; i < 50; i++) {
      try {
        socket = await Socket.connect('127.0.0.1', 10808);
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    check(socket != null, 'Official Xray must start with SSH config');
    final connection = socket!;
    final reader = StreamIterator<Uint8List>(connection);
    final buffer = <int>[];
    Future<List<int>> read(int n) async {
      while (buffer.length < n) {
        check(await reader.moveNext(), 'Xray SOCKS ended');
        buffer.addAll(reader.current);
      }
      final v = buffer.sublist(0, n);
      buffer.removeRange(0, n);
      return v;
    }

    connection.add([5, 1, 0]);
    await connection.flush();
    check((await read(2))[1] == 0, 'Xray inbound handshake');
    connection.add([
      5,
      1,
      0,
      1,
      127,
      0,
      0,
      1,
      targetPort >> 8,
      targetPort & 255,
    ]);
    await connection.flush();
    check((await read(10))[1] == 0, 'Xray to authenticated Dart SOCKS');
    connection.add(
      utf8.encode(
        'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
      ),
    );
    await connection.flush();
    while (await reader.moveNext()) {
      buffer.addAll(reader.current);
    }
    check(
      utf8.decode(buffer).contains('ABESS_DART_SSH_REAL_TRAFFIC'),
      'Official Xray -> Dart SOCKS -> SSH -> HTTP',
    );
    await reader.cancel();
    connection.destroy();
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final association = await Socket.connect('127.0.0.1', 10808);
    final associationReader = StreamIterator<Uint8List>(association);
    final associationBuffer = <int>[];
    Future<List<int>> associationRead(int n) async {
      while (associationBuffer.length < n) {
        check(await associationReader.moveNext(), 'UDP association ended');
        associationBuffer.addAll(associationReader.current);
      }
      final value = associationBuffer.sublist(0, n);
      associationBuffer.removeRange(0, n);
      return value;
    }

    association.add([5, 1, 0]);
    await association.flush();
    check((await associationRead(2))[1] == 0, 'UDP association handshake');
    association.add([5, 3, 0, 1, 127, 0, 0, 1, udp.port >> 8, udp.port & 255]);
    await association.flush();
    final bound = await associationRead(10);
    check(bound[1] == 0, 'UDP associate accepted');
    final relayPort = bound[8] * 256 + bound[9];
    try {
      final name = [
        7,
        ...ascii.encode('example'),
        3,
        ...ascii.encode('com'),
        0,
        0,
        1,
        0,
        1,
      ];
      final query = [0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, ...name];
      udp.send(
        [0, 0, 0, 1, 1, 1, 1, 1, 0, 53, ...query],
        InternetAddress.loopbackIPv4,
        relayPort,
      );
      Datagram? response;
      await for (final event in udp.timeout(const Duration(seconds: 8))) {
        if (event == RawSocketEvent.read) {
          response = udp.receive();
          if (response != null) break;
        }
      }
      check(
        response != null &&
            response!.data.length > 14 &&
            response!.data.sublist(response!.data.length - 4).join('.') ==
                '1.2.3.4',
        'UDP DNS converted to TCP and carried through SSH',
      );
    } finally {
      udp.close();
      await associationReader.cancel();
      association.destroy();
    }
    print(
      'Official Xray integration PASS: real TCP via authenticated Dart SOCKS/SSH, UDP DNS converted to SSH TCP.',
    );
  } catch (_) {
    stderr.writeln(utf8.decode(engineLog, allowMalformed: true));
    rethrow;
  } finally {
    socket?.destroy();
    process.kill();
    await process.exitCode;
  }
}

Future<void> main() async {
  check(
    sshProfileIdentity('vpn.example.test', 443, 'client_a', 'ws', true) !=
        sshProfileIdentity('vpn.example.test', 443, 'client_b', 'ws', true),
    'Different SSH accounts on the same server remain separate profiles',
  );
  final directory = await Directory.systemTemp.createTemp('abess-dart-ssh-');
  final fixture = await Process.start('node', [
    'scripts/ssh_test_fixture.mjs',
    directory.path,
  ]);
  final errors = <int>[];
  fixture.stderr.listen(errors.addAll);
  final runtimes = <AbessSshRuntime>[];
  try {
    await fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line == 'SSH fixture ready')
        .timeout(const Duration(seconds: 20));
    final json = Map<String, dynamic>.from(
      jsonDecode(await File('${directory.path}/fixture.json').readAsString())
          as Map,
    );
    final profile = AbessSshProfile.fromJson(json);
    final tcp = AbessSshRuntime();
    runtimes.add(tcp);
    await tcp.start(profile, onDisconnected: () {});
    await transfer(tcp, json['targetPort'] as int);
    await testXray(tcp, json['targetPort'] as int, directory);
    const template =
        'CONNECT [host_port] [protocol][crlf]Host: [host][crlf]X-ABESS-Payload: tcp[crlf][crlf]';
    final payloadTcp = AbessSshRuntime();
    runtimes.add(payloadTcp);
    await payloadTcp.start(
      AbessSshProfile.fromJson({
        ...json,
        'port': json['payloadPort'],
        'payload': template,
      }),
      onDisconnected: () {},
    );
    await transfer(payloadTcp, json['targetPort'] as int);
    final sent = await File('${directory.path}/tcp-payload.txt').readAsString();
    check(
      sent.contains('CONNECT 127.0.0.1:${json['payloadPort']} HTTP/1.1') &&
          sent.contains('X-ABESS-Payload: tcp'),
      'TCP payload is actually sent and expanded before SSH',
    );
    final payloadBadPin = AbessSshRuntime();
    runtimes.add(payloadBadPin);
    await refuses(
      () => payloadBadPin.start(
        AbessSshProfile.fromJson({
          ...json,
          'port': json['payloadPort'],
          'payload': template,
          'fingerprint': 'SHA256:${'A' * 43}',
        }),
        onDisconnected: () {},
      ),
      'TCP payload still verifies SSH host key',
    );
    for (final invalid in ['GET / HTTP/1.1[unknown]', 'GET / HTTP/1.1\x00']) {
      var refused = false;
      try {
        AbessSshProfile.fromJson({...json, 'payload': invalid});
      } catch (_) {
        refused = true;
      }
      check(refused, 'Malformed payload rejected');
    }
    final config = tcp.xrayConfig();
    final text = jsonEncode(config);
    check(!text.contains('freedom'), 'No direct routing fallback');
    check(
      text.contains('dns-out') &&
          text.contains('blackhole') &&
          text.contains('ssh-out'),
      'DNS TCP and UDP blocking',
    );
    final bad = AbessSshRuntime();
    runtimes.add(bad);
    await refuses(
      () => bad.start(
        AbessSshProfile.fromJson({
          ...json,
          'fingerprint': 'SHA256:${'A' * 43}',
        }),
        onDisconnected: () {},
      ),
      'Wrong host key must fail',
    );
    final rawPlainJson = {
      ...json,
      'transport': 'ws',
      'port': json['wsPort'],
      'tls': false,
      'path': '/ws-ssh',
    };
    final rawPlain = AbessSshRuntime();
    runtimes.add(rawPlain);
    await rawPlain.start(
      AbessSshProfile.fromJson(rawPlainJson),
      onDisconnected: () {},
    );
    await transfer(rawPlain, json['targetPort'] as int);
    await testXray(rawPlain, json['targetPort'] as int, directory);
    final rejectedHttp = AbessSshRuntime();
    runtimes.add(rejectedHttp);
    await refuses(
      () => rejectedHttp.start(
        AbessSshProfile.fromJson({...rawPlainJson, 'port': json['rejectPort']}),
        onDisconnected: () {},
      ),
      'HTTP 200 cannot impersonate an Upgrade tunnel',
    );
    final tlsJson = {
      ...json,
      'transport': 'wss',
      'port': json['tlsPort'],
      'tls': true,
      'sni': json['host'],
      'path': '/ws-ssh',
    };
    final untrusted = AbessSshRuntime();
    runtimes.add(untrusted);
    await refuses(
      () => untrusted.start(
        AbessSshProfile.fromJson(tlsJson),
        onDisconnected: () {},
      ),
      'Untrusted TLS certificate must fail',
    );
    final untrustedRaw = AbessSshRuntime();
    runtimes.add(untrustedRaw);
    await refuses(
      () => untrustedRaw.start(
        AbessSshProfile.fromJson({...tlsJson, 'transport': 'wss-raw'}),
        onDisconnected: () {},
      ),
      'Raw SSH-WS TLS must reject an untrusted certificate',
    );
    final unpinnedRaw = AbessSshRuntime();
    runtimes.add(unpinnedRaw);
    await refuses(
      () => unpinnedRaw.start(
        AbessSshProfile.fromJson({
          ...rawPlainJson,
          'fingerprint': 'SHA256:${'A' * 43}',
        }),
        onDisconnected: () {},
      ),
      'Plain SSH-WS must still verify the SSH host key',
    );
    SecurityContext.defaultContext.setTrustedCertificates(
      '${directory.path}/tls.crt',
    );
    final tls = AbessSshRuntime();
    runtimes.add(tls);
    await tls.start(AbessSshProfile.fromJson(tlsJson), onDisconnected: () {});
    await transfer(tls, json['targetPort'] as int);
    final rawTls = AbessSshRuntime();
    runtimes.add(rawTls);
    await rawTls.start(
      AbessSshProfile.fromJson({...tlsJson, 'transport': 'wss-raw-alt'}),
      onDisconnected: () {},
    );
    await transfer(rawTls, json['targetPort'] as int);
    final framedPlain = AbessSshRuntime();
    runtimes.add(framedPlain);
    await framedPlain.start(
      AbessSshProfile.fromJson({
        ...rawPlainJson,
        'transport': 'ws-framed',
        'path': '/custom-ssh',
      }),
      onDisconnected: () {},
    );
    await transfer(framedPlain, json['targetPort'] as int);
    final customRaw = AbessSshRuntime();
    runtimes.add(customRaw);
    await customRaw.start(
      AbessSshProfile.fromJson({
        ...rawPlainJson,
        'path': '/custom-ssh',
        'payload':
            'GET /custom-ssh HTTP/1.1[crlf]Host: [host_port][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]',
      }),
      onDisconnected: () {},
    );
    await transfer(customRaw, json['targetPort'] as int);
    final customSni = AbessSshRuntime();
    runtimes.add(customSni);
    await customSni.start(
      AbessSshProfile.fromJson({
        ...tlsJson,
        'transport': 'wss-raw',
        'sni': 'localhost',
        'path': '/custom-ssh',
      }),
      onDisconnected: () {},
    );
    await transfer(customSni, json['targetPort'] as int);
    final customWss = AbessSshRuntime();
    runtimes.add(customWss);
    await customWss.start(
      AbessSshProfile.fromJson({
        ...tlsJson,
        'sni': 'localhost',
        'path': '/custom-ssh',
      }),
      onDisconnected: () {},
    );
    await transfer(customWss, json['targetPort'] as int);
    final badSni = AbessSshRuntime();
    runtimes.add(badSni);
    await refuses(
      () => badSni.start(
        AbessSshProfile.fromJson({
          ...tlsJson,
          'sni': 'wrong.example.test',
          'transport': 'wss-raw',
        }),
        onDisconnected: () {},
      ),
      'Custom SNI must still match the certificate',
    );
    final handshakes =
        jsonDecode(
              await File(
                '${directory.path}/http-handshakes.json',
              ).readAsString(),
            )
            as List;
    check(
      handshakes.length >= 2 &&
          handshakes.every(
            (v) =>
                ['/ws-ssh', '/custom-ssh'].contains(v['path']) &&
                v['upgrade'] == 'websocket' &&
                v['connection'] == 'Upgrade',
          ),
      'Actual raw HTTP Upgrade payload used in plain and TLS SSH-WS',
    );
    check(
      handshakes.any((v) => v['host'] == 'localhost:${json['tlsPort']}'),
      'Default TLS Host follows custom SNI',
    );
    var rejected = false;
    try {
      AbessSshProfile.fromJson({...json, 'fingerprint': null});
    } catch (_) {
      rejected = true;
    }
    check(rejected, 'No unpinned imports');
    final report = redactDiagnostics(
      '{"sshPassword":"test-secret","password":"another-secret"}',
    );
    check(
      !report.contains('test-secret') && !report.contains('another-secret'),
      'JSON credentials redacted',
    );
    print(
      'Dart SSH runtime PASS: TCP with real custom payload, framed WS, custom SNI/path, raw SSH-WS HTTP/TLS, HTTP 200 rejection, verified WSS, SHA256 pin rejection, authenticated SOCKS, real HTTP, DNS routing and no direct fallback.',
    );
  } finally {
    for (final runtime in runtimes) {
      await runtime.close();
    }
    fixture.kill();
    await fixture.exitCode;
    await directory.delete(recursive: true);
  }
}

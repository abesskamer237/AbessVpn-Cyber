import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

String sshProfileIdentity(
  String host,
  int port,
  String username,
  String transport,
  bool tls,
) => 'ssh:${host.toLowerCase()}|$port|$username|$transport|$tls';

class AbessSshProfile {
  final String host, username, password, fingerprint, transport;
  final int port;
  final DateTime expiresAt;
  final double quotaGb, usedGb;
  AbessSshProfile({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.fingerprint,
    required this.transport,
    required this.expiresAt,
    this.quotaGb = 10,
    this.usedGb = 0,
  });
  factory AbessSshProfile.fromJson(Map<String, dynamic> value) {
    final host = value['host']?.toString() ?? '';
    final port = (value['port'] as num?)?.toInt() ?? 0;
    final user = value['username']?.toString() ?? '';
    final pass = value['password']?.toString() ?? '';
    final pin = value['fingerprint']?.toString() ?? '';
    final transport = value['transport']?.toString() ?? '';
    final expiry = DateTime.tryParse(value['expiresAt']?.toString() ?? '');
    final quota = (value['quotaGb'] as num?)?.toDouble() ?? 10;
    if (value['format'] != 'abess-ssh-v1' ||
        value['protocol'] != 'ssh' ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$').hasMatch(host) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[a-z][a-z0-9_-]{2,31}$').hasMatch(user) ||
        pass.length < 12 ||
        pass.length > 256 ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(pin) ||
        !['tcp', 'wss', 'wss-alt'].contains(transport) ||
        expiry == null ||
        !expiry.isAfter(DateTime.now()) ||
        !quota.isFinite ||
        quota <= 0 ||
        (transport != 'tcp' &&
            (value['tls'] != true ||
                value['sni'] != host ||
                value['path'] != '/ws-ssh'))) {
      throw const FormatException(
        'Configuration SSH ABESS invalide, expirée ou dépourvue d’empreinte serveur.',
      );
    }
    return AbessSshProfile(
      host: host,
      port: port,
      username: user,
      password: pass,
      fingerprint: pin,
      transport: transport,
      expiresAt: expiry,
      quotaGb: quota,
      usedGb: (value['usedGb'] as num?)?.toDouble() ?? 0,
    );
  }
}

class _WebSocketSink implements StreamSink<List<int>> {
  final WebSocket socket;
  _WebSocketSink(this.socket);
  @override
  void add(List<int> data) => socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      socket.add(data);
    }
  }

  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  Future<void> get done => socket.done.then((_) {});
}

class _WebSocketTransport implements SSHSocket {
  final WebSocket socket;
  final StreamController<Uint8List> _input = StreamController<Uint8List>();
  bool _discard = false;
  _WebSocketTransport(this.socket) {
    _input.onCancel = () {
      _discard = true;
    };
    socket.listen(
      (data) {
        if (!_discard && !_input.isClosed)
          _input.add(Uint8List.fromList(data as List<int>));
      },
      onError: (Object error, StackTrace trace) {
        if (!_discard && !_input.isClosed) _input.addError(error, trace);
      },
      onDone: () {
        if (!_input.isClosed) unawaited(_input.close());
      },
    );
  }
  @override
  Stream<Uint8List> get stream => _input.stream;
  @override
  StreamSink<List<int>> get sink => _WebSocketSink(socket);
  @override
  Future<void> get done =>
      socket.done.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  void destroy() {
    unawaited(
      socket.close().then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  @override
  Future<void> flush() async {}
}

class _Reader {
  final StreamIterator<Uint8List> iterator;
  List<int> buffer = [];
  _Reader(Socket socket) : iterator = StreamIterator(socket);
  Future<List<int>> read(int count) async {
    while (buffer.length < count) {
      if (!await iterator.moveNext())
        throw const SocketException('SOCKS closed');
      buffer.addAll(iterator.current);
      if (buffer.length > 262144)
        throw const FormatException('SOCKS handshake too large');
    }
    final result = buffer.sublist(0, count);
    buffer = buffer.sublist(count);
    return result;
  }

  Stream<List<int>> rest() async* {
    if (buffer.isNotEmpty) {
      yield buffer;
      buffer = [];
    }
    while (await iterator.moveNext()) {
      yield iterator.current;
    }
  }
}

/// SSH carries TCP only. The local SOCKS endpoint is authenticated and bound to
/// loopback. Xray supplies Android's VPN/TUN and converts DNS to TCP through SSH.
class AbessSshRuntime {
  SSHClient? _client;
  ServerSocket? _server;
  final Set<Socket> _sockets = {};
  bool _closing = false;
  final String localUser = 'abess';
  final String localPassword = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  int get port => _server!.port;

  Future<void> start(
    AbessSshProfile profile, {
    required void Function() onDisconnected,
  }) async {
    if (!profile.expiresAt.isAfter(DateTime.now()))
      throw const FormatException('Compte SSH expiré.');
    final SSHSocket transport;
    if (profile.transport == 'tcp') {
      transport = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 15),
      );
    } else {
      final ws = await WebSocket.connect(
        Uri(
          scheme: 'wss',
          host: profile.host,
          port: profile.port,
          path: '/ws-ssh',
        ).toString(),
      ).timeout(const Duration(seconds: 15));
      ws.pingInterval = const Duration(seconds: 20);
      transport = _WebSocketTransport(ws);
    }
    try {
      final client = SSHClient(
        transport,
        username: profile.username,
        onPasswordRequest: () => profile.password,
        onVerifyHostKey: (_, fingerprint) =>
            utf8.decode(fingerprint) == profile.fingerprint,
        keepAliveInterval: const Duration(seconds: 20),
      );
      _client = client;
      unawaited(
        client.done.then(
          (_) {
            if (!_closing) {
              unawaited(close());
              onDisconnected();
            }
          },
          onError: (Object _) {
            if (!_closing) {
              unawaited(close());
              onDisconnected();
            }
          },
        ),
      );
      await client.authenticated.timeout(const Duration(seconds: 20));
      if (_closing)
        throw const SocketException('SSH closed during authentication');
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen((socket) {
        if (_closing || _sockets.length >= 128) {
          socket.destroy();
          return;
        }
        _sockets.add(socket);
        unawaited(_proxy(socket, client));
      });
    } catch (_) {
      transport.destroy();
      await close();
      rethrow;
    }
  }

  Future<void> _proxy(Socket socket, SSHClient client) async {
    final reader = _Reader(socket);
    SSHForwardChannel? channel;
    final timeout = Timer(const Duration(seconds: 15), socket.destroy);
    try {
      final hello = await reader.read(2);
      if (hello[0] != 5 || hello[1] == 0) return;
      final methods = await reader.read(hello[1]);
      if (!methods.contains(2)) {
        socket.add([5, 255]);
        await socket.flush();
        return;
      }
      socket.add([5, 2]);
      await socket.flush();
      final auth = await reader.read(2);
      if (auth[0] != 1) return;
      final user = utf8.decode(await reader.read(auth[1]));
      final passLength = (await reader.read(1))[0];
      final pass = utf8.decode(await reader.read(passLength));
      if (user != localUser || pass != localPassword) {
        socket.add([1, 1]);
        await socket.flush();
        return;
      }
      socket.add([1, 0]);
      await socket.flush();
      final request = await reader.read(4);
      if (request[0] != 5 || request[1] != 1 || request[2] != 0) {
        socket.add([5, 7, 0, 1, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        return;
      }
      final String host;
      switch (request[3]) {
        case 1:
          host = InternetAddress.fromRawAddress(
            Uint8List.fromList(await reader.read(4)),
          ).address;
        case 4:
          host = InternetAddress.fromRawAddress(
            Uint8List.fromList(await reader.read(16)),
          ).address;
        case 3:
          host = utf8.decode(await reader.read((await reader.read(1))[0]));
        default:
          return;
      }
      final bytes = await reader.read(2);
      final port = bytes[0] * 256 + bytes[1];
      channel = await client
          .forwardLocal(host, port)
          .timeout(const Duration(seconds: 15));
      socket.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      await socket.flush();
      timeout.cancel();
      final response = channel.stream.listen(
        socket.add,
        onError: (_) => socket.destroy(),
        onDone: () => unawaited(socket.close()),
      );
      try {
        await channel.sink.addStream(reader.rest());
        await channel.sink.close();
        await channel.done;
      } finally {
        await response.cancel();
      }
    } catch (_) {
      /* Never expose a credential or fall back to direct routing. */
    } finally {
      timeout.cancel();
      channel?.destroy();
      await reader.iterator.cancel();
      socket.destroy();
      _sockets.remove(socket);
    }
  }

  Map<String, dynamic> xrayConfig({String dnsAddress = '1.1.1.1'}) => {
    'log': {'loglevel': 'warning'},
    'dns': {
      'servers': ['tcp://$dnsAddress'],
    },
    'inbounds': [
      {
        'tag': 'socks-in',
        'port': 10808,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
      },
    ],
    'outbounds': [
      {
        'tag': 'ssh-out',
        'protocol': 'socks',
        'settings': {
          'servers': [
            {
              'address': '127.0.0.1',
              'port': port,
              'users': [
                {'user': localUser, 'pass': localPassword},
              ],
            },
          ],
        },
      },
      {
        'tag': 'dns-out',
        'protocol': 'dns',
        'settings': {'network': 'tcp', 'address': dnsAddress, 'port': 53},
        'proxySettings': {'tag': 'ssh-out'},
      },
      {'tag': 'blocked', 'protocol': 'blackhole', 'settings': {}},
    ],
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
        {
          'type': 'field',
          'network': 'udp',
          'port': '53',
          'outboundTag': 'dns-out',
        },
        {'type': 'field', 'network': 'udp', 'outboundTag': 'blocked'},
      ],
    },
  };

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _server?.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
    final client = _client;
    client?.close();
    if (client != null) {
      try {
        await client.done.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}

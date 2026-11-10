import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:file_picker/file_picker.dart';
import 'widgets/connection_overview.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';

final ValueNotifier<bool> abessDarkMode = ValueNotifier<bool>(true);

/// Générateur standardisé de tokens unifiés ABESS-XXXXXXXXXXX
String generateUnifiedToken() {
  const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  final rand = math.Random.secure();
  final buffer = StringBuffer('ABESS-');
  for (var i = 0; i < 11; i++) {
    buffer.write(chars[rand.nextInt(chars.length)]);
  }
  return buffer.toString();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  abessDarkMode.value = prefs.getBool('abess_dark_mode') ?? true;
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AbessVpnApp());
}

/// Modèle pour le serveur importé exclusivement par Token ou Fichier crypté
class ImportedVpnServer {
  final String id;
  final String name;
  final String address;
  final int port;
  final String path;
  final String sni;
  final String uuid;
  final String protocol;
  final String transport;
  final bool tls;
  final String method;
  final String wsHost;
  final double bandwidthGb;
  double bandwidthUsedGb;
  final DateTime expiresAt;
  final String? token;
  final String? encryptedLink;
  final int deviceLimit;
  final String? allowedDeviceId;
  final String? licenseId;

  ImportedVpnServer({
    String? id,
    required this.name,
    required this.address,
    required this.port,
    required this.path,
    required this.sni,
    required this.uuid,
    this.protocol = 'vless',
    this.transport = 'ws',
    this.tls = true,
    this.method = 'aes-128-gcm',
    this.wsHost = '',
    this.bandwidthGb = 10.0,
    this.bandwidthUsedGb = 0.0,
    required this.expiresAt,
    this.token,
    this.encryptedLink,
    this.deviceLimit = 1,
    this.allowedDeviceId,
    this.licenseId,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(0x7fffffff)}';

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isQuotaExceeded => bandwidthUsedGb >= bandwidthGb;
  double get remainingGb => math.max(0.0, bandwidthGb - bandwidthUsedGb);
  double get usedPercentage => math.min(100.0, (bandwidthUsedGb / (bandwidthGb > 0 ? bandwidthGb : 1)) * 100.0);
}

class ServerAnnouncement {
  final String id;
  final String title;
  final String message;
  final String type;
  final String targetPlatform;
  final bool isMandatory;
  final bool dismissible;
  final String? actionButtonText;
  final String? actionButtonUrl;
  final String showMode;
  final String publishedAt;

  ServerAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.targetPlatform,
    required this.isMandatory,
    required this.dismissible,
    this.actionButtonText,
    this.actionButtonUrl,
    required this.showMode,
    required this.publishedAt,
  });

  factory ServerAnnouncement.fromJson(Map<String, dynamic> json) {
    return ServerAnnouncement(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      type: (json['type'] ?? 'INFO').toString().toUpperCase(),
      targetPlatform: (json['targetPlatform'] ?? 'ALL').toString().toUpperCase(),
      isMandatory: json['isMandatory'] == true,
      dismissible: json['dismissible'] != false,
      actionButtonText: json['actionButtonText']?.toString(),
      actionButtonUrl: json['actionButtonUrl']?.toString(),
      showMode: (json['showMode'] ?? 'ONCE_PER_USER').toString(),
      publishedAt: (json['publishedAt'] ?? '').toString(),
    );
  }
}

class AbessVpnApp extends StatelessWidget {
  const AbessVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: abessDarkMode,
      builder: (context, isDarkMode, _) {
        final brightness = isDarkMode ? Brightness.dark : Brightness.light;
        final baseTheme = isDarkMode ? ThemeData.dark() : ThemeData.light();
        return MaterialApp(
          title: 'AbessVpn',
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations
              ? Duration.zero : const Duration(milliseconds: 260),
          theme: ThemeData(
            brightness: brightness,
            scaffoldBackgroundColor: isDarkMode ? const Color(0xFF030712) : const Color(0xFFF1F5F9),
            primaryColor: isDarkMode ? const Color(0xFF10B981) : const Color(0xFF047857),
            colorScheme: ColorScheme.fromSeed(
              seedColor: isDarkMode ? const Color(0xFF10B981) : const Color(0xFF047857),
              brightness: brightness,
            ),
            useMaterial3: true,
            visualDensity: VisualDensity.standard,
            textTheme: baseTheme.textTheme.copyWith(
              titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.5),
              titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(44, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: isDarkMode ? const Color(0xFF0B1525) : Colors.white,
              indicatorColor: isDarkMode ? const Color(0xFF153D35) : const Color(0xFFD1FAE5),
              labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              )),
            ),
          ),
          home: const MainVpnScreen(),
        );
      },
    );
  }
}

class MainVpnScreen extends StatefulWidget {
  const MainVpnScreen({super.key});

  @override
  State<MainVpnScreen> createState() => _MainVpnScreenState();
}

class _MainVpnScreenState extends State<MainVpnScreen> with TickerProviderStateMixin {
  // Historique Télémétrie Graphique (fl_chart)
  final List<FlSpot> _speedHistoryDownload = [
    FlSpot(0, 0),
    FlSpot(1, 0.4),
    FlSpot(2, 1.2),
    FlSpot(3, 0.9),
    FlSpot(4, 2.5),
    FlSpot(5, 1.8),
    FlSpot(6, 3.2),
  ];
  final List<FlSpot> _speedHistoryUpload = [
    FlSpot(0, 0),
    FlSpot(1, 0.2),
    FlSpot(2, 0.6),
    FlSpot(3, 0.4),
    FlSpot(4, 1.1),
    FlSpot(5, 0.8),
    FlSpot(6, 1.4),
  ];

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: _textPrimary, fontSize: 12)),
        backgroundColor: Color(0xFF0F172A),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Color(0xFF06B6D4), width: 0.8),
        ),
      ),
    );
  }

  // Palette Cyberpunk
  static const Color cyberGreen = Color(0xFF10B981);
  static const Color cyberCyan = Color(0xFF06B6D4);
  static const Color cyberRed = Color(0xFFEF4444);
  static const Color cyberYellow = Color(0xFFF59E0B);
  Color get cyberCardBg => abessDarkMode.value ? const Color(0xFF080F1E) : const Color(0xFFFFFFFF);
  Color get _fieldBackgroundColor => abessDarkMode.value ? const Color(0xFF030712) : const Color(0xFFF1F5F9);
  Color get _fieldFillColor => abessDarkMode.value ? Colors.black45 : const Color(0xFFF8FAFC);
  Color get _metricTileFill => abessDarkMode.value ? Colors.black : const Color(0xFFFFFFFF);
  Color get _softSurfaceFill => abessDarkMode.value ? Colors.black45 : const Color(0xFFE2E8F0);
  Color get _textPrimary => abessDarkMode.value ? Colors.white : const Color(0xFF0F172A);
  Color get _text70 => abessDarkMode.value ? Colors.white70 : const Color(0xFF334155);
  Color get _text60 => abessDarkMode.value ? Colors.white60 : const Color(0xFF475569);
  Color get _text54 => abessDarkMode.value ? Colors.white54 : const Color(0xFF64748B);
  Color get _text38 => abessDarkMode.value ? Colors.white38 : const Color(0xFF64748B);
  Color get _text30 => abessDarkMode.value ? Colors.white30 : const Color(0xFF94A3B8);
  Color get _text24 => abessDarkMode.value ? Colors.white24 : const Color(0xFF64748B);
  Color get _text12 => abessDarkMode.value ? Colors.white12 : const Color(0xFFCBD5E1);
  Color get _text10 => abessDarkMode.value ? Colors.white10 : const Color(0xFFE2E8F0);
  Color get _screenSurface => abessDarkMode.value ? const Color(0xFF060D1D) : const Color(0xFFFFFFFF);

  // Moteur V2Ray
  late FlutterV2ray v2ray;
  bool isV2rayInitialized = false;

  // États de connexion
  String vpnStatus = 'DISCONNECTED';
  bool isConnected = false;
  bool isConnecting = false;

  // Télémétrie en temps réel
  Timer? _telemetryTimer;
  Timer? _pingTimer;
  int _connectionDurationSeconds = 0;
  double _currentDownloadSpeed = 0.0; // MiB/s from Xray status
  double _currentUploadSpeed = 0.0; // MiB/s from Xray status
  double _totalDownloadMb = 0.0; // MiB transferred
  double _totalUploadMb = 0.0; // MiB transferred
  int _currentDownloadBytes = 0;
  int _currentUploadBytes = 0;
  int _lastReportedDownloadBytes = 0;
  int _lastReportedUploadBytes = 0;
  double _quotaUsageAtSessionStartGb = 0.0;
  int _currentPingMs = 0; // ms; zero means not yet measured
  final String _virtualIp = '10.8.0.2';
  String _deviceId = '';

  // Profils conservés localement ; currentServer est le profil sélectionné.
  static const String _savedProfilesKey = 'abess_imported_servers';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _selectedProfileKey = 'abess_selected_server_id';
  List<ImportedVpnServer> savedServers = <ImportedVpnServer>[];
  ImportedVpnServer? currentServer;

  // Contrôleurs d'importation et de création
  final TextEditingController _tokenInputCtrl = TextEditingController();
  final TextEditingController _fileInputCtrl = TextEditingController();
  final TextEditingController _createTokenCodeCtrl = TextEditingController();
  final TextEditingController _createPlanNameCtrl = TextEditingController(text: 'VIP Express');
  double _createQuotaGb = 10.0;
  int _createExpiryDays = 30;
  int _createDeviceLimit = 1;
  bool _isCreatingToken = false;

  // NAVIGATION (3 ONGLETS : CONNEXION, SERVEURS & FORFAITS, OUTILS & DIAGNOSTIC)
  int _currentNavIndex = 0;
  bool _isMuxEnabled = true;
  bool _isAntiAdDnsEnabled = true;

  String _newUuid() {
    final rand = math.Random.secure();
    String s(int len) => List.generate(len, (_) => rand.nextInt(16).toRadixString(16)).join();
    return "${s(8)}-${s(4)}-4${s(3)}-${(8 + rand.nextInt(4)).toRadixString(16)}${s(3)}-${s(12)}";
  }

  Future<void> _pickAndImportAbessFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['abess'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final content = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : picked.path != null
              ? await File(picked.path!).readAsString()
              : '';
      final link = content.trim();
      if (link.isEmpty || !link.startsWith('abess://')) {
        _showToast('Fichier ABESS invalide');
        return;
      }
      _fileInputCtrl.text = link;
      await _importServerByEncryptedLink(link);
    } catch (error) {
      _addLog('IMPORT .ABESS ÉCHOUÉ : $error');
      _showToast('Import impossible');
    }
  }

  void _parseUniversalRawLink(String raw) {
    final link = raw.trim();
    if (link.isEmpty) return;

    String decodeB64(String input) {
      var value = input.replaceAll('-', '+').replaceAll('_', '/');
      while (value.length % 4 != 0) { value += '='; }
      return utf8.decode(base64.decode(value));
    }

    String normalizeNetwork(String network) {
      switch (network.toLowerCase()) {
        case 'tcp':
        case 'raw': return 'raw';
        case 'ws':
        case 'grpc':
        case 'httpupgrade':
        case 'xhttp': return network.toLowerCase();
        case 'kcp':
        case 'mkcp': return 'kcp';
        case 'native': return 'native';
        case 'splithttp': return 'xhttp';
        default: throw FormatException('Transport V2Ray non pris en charge : ' + network);
      }
    }

    void acceptProfile({
      required String name, required String host, required int port,
      required String passwordOrUuid, required String protocol,
      required String transport, required bool tls,
      String path = '/@abess237', String sni = '',
      String method = 'aes-128-gcm', String wsHost = '',
      double bandwidthGb = 50.0, DateTime? expiresAt, String allowedDeviceId = '', String licenseId = '',
    }) {
      if (host.isEmpty || port < 1 || port > 65535 || passwordOrUuid.isEmpty) {
        throw FormatException('Le lien ne contient pas un hôte, port ou identifiant valide.');
      }
      if (!bandwidthGb.isFinite || bandwidthGb <= 0 || bandwidthGb > 100000) {
        throw FormatException('Le quota du profil est invalide.');
      }
      final validExpiry = expiresAt ?? DateTime.now().add(const Duration(days: 30));
      if (!validExpiry.isAfter(DateTime.now())) {
        throw FormatException('Ce profil ABESS a expiré.');
      }
      final expectedDeviceId = allowedDeviceId.trim();
      if (expectedDeviceId.isNotEmpty && (_deviceId.isEmpty || expectedDeviceId != _deviceId)) {
        throw FormatException('Ce profil est lié à un autre ID d’installation. Demandez un lien créé pour votre ID ABESS.');
      }
      if (protocol == 'trojan' && !tls) {
        throw FormatException('Trojan sur un serveur public doit utiliser TLS.');
      }
      final server = ImportedVpnServer(
        name: name.isNotEmpty ? name : 'Serveur importé (' + protocol + ')',
        address: host, port: port, path: path.isNotEmpty ? path : '/@abess237',
        sni: sni.isNotEmpty ? sni : host, uuid: passwordOrUuid,
        protocol: protocol, transport: transport, tls: tls, method: method, wsHost: wsHost,
        bandwidthGb: bandwidthGb, bandwidthUsedGb: 0.0,
        expiresAt: validExpiry, token: 'RAW-LINK-IMPORT',
        allowedDeviceId: expectedDeviceId.isEmpty ? null : expectedDeviceId,
        licenseId: licenseId.isEmpty ? null : licenseId,
      );
      unawaited(_storeAndSelectServer(server));
      _showToast('Lien ' + protocol + ' / ' + transport + ' importé.');
    }

    try {
      if (link.startsWith('{') || link.contains('"sshConfig"') || link.contains('"configs"')) {
        try {
          final decoded = jsonDecode(link);
          if (decoded is Map && decoded['configs'] is List && (decoded['configs'] as List).isNotEmpty) {
            final firstCfg = decoded['configs'][0];
            final type = (firstCfg['type'] ?? '').toString().toUpperCase();
            if (type == 'SSH' && firstCfg['sshConfig'] is Map) {
              final ssh = Map<String, dynamic>.from(firstCfg['sshConfig']);
              final name = (firstCfg['name'] ?? ssh['remarks'] ?? '𖤍 ORANGE🍊〆DANNY 𖤍').toString();
              final host = (ssh['sshHost'] ?? '').toString();
              final port = int.tryParse((ssh['sshPort'] ?? 80).toString()) ?? 80;
              final user = (ssh['sshUsername'] ?? '').toString();
              final pass = (ssh['sshPassword'] ?? '').toString();
              final payload = (ssh['payload'] ?? '').toString();
              acceptProfile(
                name: name,
                host: host,
                port: port,
                passwordOrUuid: '$user:$pass',
                protocol: 'ssh',
                transport: 'ws',
                tls: false,
                method: payload,
                wsHost: 'm.batch.com',
                sni: host,
              );
              _addLog('PROFIL SSH-PAYLOAD IMPORTÉ : $name ($user@$host:$port)');
              return;
            }
          }
        } catch (_) {}
      }

      if (link.startsWith('abess://profile.')) {
        if (_deviceId.isEmpty) throw const FormatException('ID d’installation non initialisé. Réessayez dans quelques secondes.');
        final encoded = link.substring('abess://profile.'.length).split(RegExp(r'[\s#]')).first;
        final decoded = jsonDecode(decodeB64(encoded));
        if (decoded is! Map) throw const FormatException('Fichier ABESS invalide.');
        final p = Map<String, dynamic>.from(decoded);
        final version = int.tryParse((p['v'] ?? 1).toString()) ?? 1;
        final allowedDeviceId = (p['allowedDeviceId'] ?? '').toString().trim();
        if (version >= 2 && allowedDeviceId.isEmpty) {
          throw const FormatException('Ce lien limité ne contient pas d’ID d’installation autorisé.');
        }
        final licenseId = (p['licenseId'] ?? '').toString().trim();
        if (version >= 2 && licenseId.isEmpty) {
          throw const FormatException('Identifiant de licence ABESS manquant.');
        }
        final expiryText = p['expiresAt']?.toString();
        final expiry = expiryText == null ? null : DateTime.tryParse(expiryText);
        if (expiryText != null && expiry == null) throw const FormatException('Date d’expiration invalide.');
        final rawQuota = p['bandwidthGb'];
        final quota = rawQuota is num ? rawQuota.toDouble() : double.tryParse((rawQuota ?? '50').toString()) ?? 50.0;
        acceptProfile(
          name: (p['name'] ?? 'Profil ABESS').toString(),
          host: (p['address'] ?? '').toString(),
          port: int.tryParse((p['port'] ?? 443).toString()) ?? 443,
          passwordOrUuid: (p['uuid'] ?? '').toString(),
          protocol: (p['protocol'] ?? 'vless').toString().toLowerCase(),
          transport: normalizeNetwork((p['transport'] ?? 'ws').toString()),
          tls: p['tls'] as bool? ?? true,
          path: (p['path'] ?? '/@abess237').toString(),
          sni: (p['sni'] ?? p['address'] ?? '').toString(),
          wsHost: (p['wsHost'] ?? '').toString(),
          method: (p['method'] ?? 'aes-128-gcm').toString(),
          bandwidthGb: quota,
          expiresAt: expiry,
          allowedDeviceId: allowedDeviceId,
          licenseId: licenseId,
        );
        return;
      }
      if (link.startsWith('vless://')) {
        final uri = Uri.parse(link);
        final q = uri.queryParameters;
        final security = (q['security'] ?? 'tls').toLowerCase();
        if (security == 'reality') throw FormatException('Reality exige les paramètres de clés dédiés et n’est pas converti automatiquement.');
        acceptProfile(
          name: uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'VLESS importé',
          host: uri.host, port: uri.port > 0 ? uri.port : 443,
          passwordOrUuid: Uri.decodeComponent(uri.userInfo), protocol: 'vless',
          transport: normalizeNetwork(q['type'] ?? 'ws'),
          tls: security != 'none' && security != 'false' && security.isNotEmpty,
          path: q['path'] ?? '/@abess237', sni: q['sni'] ?? uri.host, wsHost: q['host'] ?? uri.host,
        );
        return;
      }

      if (link.startsWith('vmess://')) {
        final encoded = link.substring('vmess://'.length).split('#').first;
        final decoded = jsonDecode(decodeB64(encoded));
        if (decoded is! Map) throw FormatException('Profil VMess JSON invalide.');
        final config = Map<String, dynamic>.from(decoded);
        final host = (config['add'] ?? config['address'] ?? '').toString();
        final net = normalizeNetwork((config['net'] ?? 'tcp').toString());
        final port = int.tryParse((config['port'] ?? '443').toString()) ?? 443;
        final security = (config['tls'] ?? '').toString().toLowerCase();
        if (security == 'reality') throw FormatException('VMess/Reality exige des paramètres supplémentaires.');
        acceptProfile(
          name: (config['ps'] ?? 'VMess importé').toString(), host: host, port: port,
          passwordOrUuid: (config['id'] ?? '').toString(), protocol: 'vmess', transport: net, tls: security == 'tls',
          path: (config['path'] ?? '/@abess237').toString(),
          sni: (config['sni'] ?? config['servername'] ?? config['host'] ?? host).toString(),
          wsHost: (config['host'] ?? host).toString(),
        );
        return;
      }

      if (link.startsWith('trojan://')) {
        final uri = Uri.parse(link);
        final q = uri.queryParameters;
        final security = (q['security'] ?? 'tls').toLowerCase();
        if (security == 'reality') throw FormatException('Trojan/Reality n’est pas converti automatiquement.');
        acceptProfile(
          name: uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'Trojan importé',
          host: uri.host, port: uri.port > 0 ? uri.port : 443,
          passwordOrUuid: Uri.decodeComponent(uri.userInfo), protocol: 'trojan',
          transport: normalizeNetwork(q['type'] ?? 'tcp'), tls: security != 'none' && security.isNotEmpty,
          path: q['path'] ?? '/@abess237', sni: q['sni'] ?? uri.host, wsHost: q['host'] ?? uri.host,
        );
        return;
      }

      if (link.startsWith('ss://')) {
        final uri = Uri.parse(link);
        if ((uri.queryParameters['plugin'] ?? '').isNotEmpty) {
          throw FormatException('Les liens Shadowsocks avec plugin de transport doivent être convertis séparément.');
        }
        String method; String password; String host = uri.host; int port = uri.port;
        if (host.isNotEmpty && port > 0) {
          var userInfo = Uri.decodeComponent(uri.userInfo);
          if (!userInfo.contains(':')) { try { userInfo = decodeB64(userInfo); } catch (_) {} }
          final split = userInfo.indexOf(':');
          if (split < 1) throw FormatException('Identifiants Shadowsocks invalides.');
          method = userInfo.substring(0, split); password = userInfo.substring(split + 1);
        } else {
          final payload = link.substring(5).split('#').first.split('?').first;
          final decoded = decodeB64(payload);
          final at = decoded.lastIndexOf('@');
          if (at < 1) throw FormatException('Lien Shadowsocks invalide.');
          final credentials = decoded.substring(0, at);
          final endpoint = Uri.parse('ss://' + decoded.substring(at + 1));
          final split = credentials.indexOf(':');
          if (split < 1 || endpoint.host.isEmpty || endpoint.port < 1) throw FormatException('Identifiants ou adresse Shadowsocks invalides.');
          method = credentials.substring(0, split); password = credentials.substring(split + 1);
          host = endpoint.host; port = endpoint.port;
        }
        acceptProfile(
          name: uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'Shadowsocks importé',
          host: host, port: port, passwordOrUuid: password, protocol: 'shadowsocks',
          transport: 'native', tls: false, method: method,
        );
        return;
      }

      if (link.startsWith('wireguard://') || link.startsWith('wg://')) {
        final uri = Uri.parse(link.replaceFirst('wireguard://', 'wg://'));
        final q = uri.queryParameters;
        final privKey = Uri.decodeComponent(uri.userInfo);
        final pubKey = q['publickey'] ?? q['pubkey'] ?? q['server_pubkey'] ?? '';
        final clientIp = q['address'] ?? q['ip'] ?? '';
        final host = uri.host;
        final port = uri.port > 0 ? uri.port : 51820;
        if (privKey.isEmpty || pubKey.isEmpty || clientIp.isEmpty || host.isEmpty) {
          throw FormatException('Profil WireGuard incomplet : clé privée, clé publique, adresse client et endpoint requis.');
        }
        final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'WireGuard (Geny) importé';
        acceptProfile(
          name: name,
          host: host,
          port: port,
          passwordOrUuid: privKey,
          protocol: 'wireguard',
          transport: 'native',
          tls: false,
          method: clientIp,
          wsHost: pubKey,
          sni: pubKey,
        );
        return;
      }

      if (link.contains('[Interface]') && (link.contains('[Peer]') || link.contains('PrivateKey'))) {
        final lines = link.split(RegExp(r'\r?\n'));
        String privKey = '';
        String clientIp = '';
        String pubKey = '';
        String endpoint = '';
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('#') || trimmed.isEmpty) continue;
          final parts = trimmed.split('=');
          if (parts.length >= 2) {
            final key = parts[0].trim().toLowerCase();
            final val = parts.sublist(1).join('=').trim();
            if (key == 'privatekey') privKey = val;
            else if (key == 'address') clientIp = val;
            else if (key == 'publickey') pubKey = val;
            else if (key == 'endpoint') endpoint = val;
          }
        }
        if (privKey.isNotEmpty && pubKey.isNotEmpty && clientIp.isNotEmpty && endpoint.isNotEmpty) {
          final epParts = endpoint.split(':');
          final host = epParts[0];
          final port = epParts.length > 1 ? (int.tryParse(epParts[1]) ?? 51820) : 51820;
          acceptProfile(
            name: 'WireGuard (Geny) Config importée',
            host: host,
            port: port,
            passwordOrUuid: privKey,
            protocol: 'wireguard',
            transport: 'native',
            tls: false,
            method: clientIp,
            wsHost: pubKey,
            sni: pubKey,
          );
          return;
        }
      }

      final genyMatch = RegExp(r'GENY-[A-Za-z0-9_-]{16,64}', caseSensitive: false).firstMatch(link.trim());
      if (genyMatch != null) {
        final extractedToken = genyMatch.group(0)!;
        _addLog('DÉTECTION CODE GENY : $extractedToken');
        unawaited(_importServerByToken(extractedToken));
        return;
      }

      _showToast('Format inconnu. Utilisez vless://, vmess://, trojan://, ss://, wg:// ou un token GENY.');
    } catch (e) {
      _addLog('ÉCHEC IMPORT LIEN : ' + e.toString());
      _showToast('Lien invalide ou transport non pris en charge.');
    }
  }

  // Amélioration 1 : Kill Switch & Reconnexion Auto
  bool isDisconnectAlertEnabled = true;
  bool isAutoReconnectEnabled = true;
  bool disconnectAlert = false;
  int _reconnectAttempts = 0;
  bool _userWantedConnection = false;
  Timer? _reconnectTimer;

  // Amélioration 5 : Liens WhatsApp Officiels
  static const String _whatsappCommunityUrl = 'https://chat.whatsapp.com/IR0pjvSbTvL0Wp4YlbCjhF';
  static const String _whatsappSupportUrl = 'https://wa.me/237695140419?text=Bonjour%20AbessVpn%2C%20j%27ai%20besoin%20d%27assistance%20technique%20pour%20mon%20accès%20VPN';
  static const String _whatsappSupportPhone = '+237 695 14 04 19';
  static const String _telegramChannelUrl = 'https://t.me/Abess_Vpn';
  static const String _telegramSupportUrl = 'https://t.me/abess237';

  // Journal des logs
  final List<String> _logs = [];

  // URLs Serveurs Maîtres AbessVpn
  static const String _configuredApiBaseUrl = String.fromEnvironment('ABESS_API_BASE_URL', defaultValue: '');

  // The API control-plane hostname is injected by CI. Never fall back to old
  // hosts or raw IPs: doing so could send licence tokens to a retired server.
  static final List<String> _robustMasterUrls = () {
    final configured = _configuredApiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (configured.isEmpty || !configured.startsWith('https://')) {
      return <String>[];
    }
    final parsed = Uri.tryParse(configured);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty || !parsed.hasAuthority ||
        parsed.userInfo.isNotEmpty || parsed.path.isNotEmpty || parsed.hasQuery || parsed.hasFragment) {
      return <String>[];
    }
    return <String>[configured];
  }();
  final List<String> _masterServerUrls = _robustMasterUrls;

  bool _reduceMotion = false;
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  bool _isReactorPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _initDeviceId();
    _initV2Ray();
    _loadSavedServer();
    _measureRealPing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdate();
      _fetchAndShowAnnouncements();
    });
  }

  bool _updateDialogShown = false;
  bool _isMandatoryUpdateBlocked = false;
  List<ServerAnnouncement> _activeAnnouncements = [];
  bool _hasUnreadAnnouncements = false;
  bool _announcementDialogShowing = false;

  Future<void> _checkForAppUpdate({bool showUpToDate = false}) async {
    try {
      final current = await PackageInfo.fromPlatform();
      final installed = current.version.split('+').first;

      String latest = '';
      String minRequired = '';
      bool isMandatory = false;
      String downloadUrl = '';
      String notes = '';

      // 1. Priorité au serveur maître /api/v1/app/version
      final endpoints = <String>[..._masterServerUrls];
      if (currentServer != null && currentServer!.address.isNotEmpty) {
        final srvHost = 'https://${currentServer!.address}';
        if (!endpoints.contains(srvHost)) endpoints.add(srvHost);
      }

      for (final base in endpoints) {
        try {
          final res = await http.get(Uri.parse('$base/api/v1/app/version')).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            latest = (data['latestVersion'] ?? '').toString().replaceFirst(RegExp(r'^v'), '').split('+').first;
            minRequired = (data['minRequiredVersion'] ?? '').toString().replaceFirst(RegExp(r'^v'), '').split('+').first;
            isMandatory = data['isMandatory'] == true;
            downloadUrl = (data['downloadUrl'] ?? '').toString();
            notes = (data['releaseNotes'] ?? '').toString().trim();
            break;
          }
        } catch (_) {}
      }

      // 2. Repli vers GitHub releases si serveur maître inaccessible
      if (latest.isEmpty) {
        try {
          final response = await http.get(
            Uri.parse('https://api.github.com/repos/abesskamer237/AbessVpn-Cyber/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'},
          ).timeout(const Duration(seconds: 6));
          if (response.statusCode == 200) {
            final release = jsonDecode(response.body) as Map<String, dynamic>;
            latest = (release['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^v'), '').split('+').first;
            notes = (release['body'] ?? '').toString().trim();
            final assets = (release['assets'] as List<dynamic>? ?? const []);
            final apks = assets.whereType<Map<String, dynamic>>().where((a) =>
              (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')).toList();
            if (apks.isNotEmpty) {
              downloadUrl = (apks.first['browser_download_url'] ?? '').toString();
            }
          }
        } catch (_) {}
      }

      if (downloadUrl.isEmpty) {
        downloadUrl = 'https://t.me/Abess_Vpn';
      }

      int compare(String a, String b) {
        final aa = a.split('.').map((v) => int.tryParse(v) ?? 0).toList();
        final bb = b.split('.').map((v) => int.tryParse(v) ?? 0).toList();
        for (var i = 0; i < math.max(aa.length, bb.length); i++) {
          final x = i < aa.length ? aa[i] : 0;
          final y = i < bb.length ? bb[i] : 0;
          if (x != y) return x.compareTo(y);
        }
        return 0;
      }

      if (latest.isEmpty) {
        if (showUpToDate && mounted) _showToast('Impossible de vérifier les mises à jour.');
        return;
      }

      final isNewer = compare(latest, installed) > 0;
      final isBelowMin = minRequired.isNotEmpty && compare(minRequired, installed) > 0;
      final forceUpdate = isNewer && (isMandatory || isBelowMin);

      if (!isNewer && !isBelowMin) {
        _isMandatoryUpdateBlocked = false;
        if (showUpToDate && mounted) _showToast('ABESS VPN est déjà à jour (v$installed).');
        return;
      }

      if (forceUpdate) {
        _isMandatoryUpdateBlocked = true;
        if (isConnected) {
          _userWantedConnection = false;
          unawaited(_disconnectVpn());
        }
      }

      if (!mounted || _updateDialogShown) return;
      _updateDialogShown = true;

      await showDialog<void>(
        context: context,
        barrierDismissible: !forceUpdate,
        builder: (dialogContext) => PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            backgroundColor: cyberCardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: forceUpdate ? const Color(0xFFEF4444) : cyberGreen,
                width: 1.5,
              ),
            ),
            title: Row(
              children: [
                Icon(
                  forceUpdate ? Icons.warning_amber_rounded : Icons.system_update_alt,
                  color: forceUpdate ? const Color(0xFFEF4444) : cyberGreen,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    forceUpdate ? 'MISE À JOUR OBLIGATOIRE' : 'Mise à jour disponible',
                    style: TextStyle(
                      color: forceUpdate ? const Color(0xFFEF4444) : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (forceUpdate) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'OBLIGATOIRE : ACCÈS BLOQUÉ TANT QUE NON INSTALLÉE',
                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('Version actuelle : v$installed', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Nouvelle version : v$latest', style: const TextStyle(color: cyberGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  Text(
                    notes.isEmpty
                        ? (forceUpdate
                            ? 'Cette mise à jour apporte des améliorations de sécurité indispensables. Vous devez mettre à jour pour continuer à utiliser le VPN.'
                            : 'Améliorations et corrections disponibles.')
                        : notes,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Appuyez ci-dessous pour télécharger la nouvelle version.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () {
                    _updateDialogShown = false;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Plus tard'),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: forceUpdate ? const Color(0xFFEF4444) : cyberGreen,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  if (!forceUpdate) {
                    _updateDialogShown = false;
                    Navigator.of(dialogContext).pop();
                  }
                  final uri = Uri.tryParse(downloadUrl);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.download),
                label: Text(forceUpdate ? 'Mettre à jour maintenant' : 'Télécharger'),
              ),
            ],
          ),
        ),
      );
      _updateDialogShown = false;
    } catch (_) {
      if (showUpToDate && mounted) _showToast('Impossible de vérifier les mises à jour pour le moment.');
    }
  }

  // ==========================================
  // SYSTÈME D'ANNONCES RÉSEAU (PUSH POPUPS EN TEMPS RÉEL)
  // ==========================================
  Future<void> _fetchAndShowAnnouncements({bool userInitiated = false}) async {
    try {
      final endpoints = <String>[..._masterServerUrls];
      if (currentServer != null && currentServer!.address.isNotEmpty) {
        final srvHost = 'https://${currentServer!.address}';
        if (!endpoints.contains(srvHost)) endpoints.add(srvHost);
      }

      List<ServerAnnouncement> fetched = [];
      for (final base in endpoints) {
        try {
          final res = await http.get(Uri.parse('$base/api/v1/announcements/active?platform=android')).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final rawList = (data['announcements'] as List<dynamic>? ?? []);
            fetched = rawList.whereType<Map<String, dynamic>>().map((item) => ServerAnnouncement.fromJson(item)).toList();
            break;
          }
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      final dismissedList = prefs.getStringList('abess_dismissed_announcements') ?? [];

      if (mounted) {
        setState(() {
          _activeAnnouncements = fetched;
          _hasUnreadAnnouncements = fetched.any((a) =>
              a.isMandatory || a.showMode == 'EVERY_LAUNCH' || !dismissedList.contains(a.id));
        });
      }

      if (fetched.isEmpty) {
        if (userInitiated && mounted) {
          _showToast('📢 Aucune annonce active sur le réseau.');
        }
        return;
      }

      ServerAnnouncement? toShow;
      if (userInitiated) {
        toShow = fetched.firstWhere(
          (a) => a.isMandatory || a.showMode == 'EVERY_LAUNCH' || !dismissedList.contains(a.id),
          orElse: () => fetched.first,
        );
      } else {
        final unread = fetched.where((a) =>
            a.isMandatory || a.showMode == 'EVERY_LAUNCH' || !dismissedList.contains(a.id)).toList();
        if (unread.isNotEmpty) {
          toShow = unread.first;
        }
      }

      if (toShow != null && mounted && !_announcementDialogShowing) {
        await _displayAnnouncementDialog(toShow);
      }
    } catch (e) {
      if (userInitiated && mounted) {
        _showToast('Erreur lors de la récupération des annonces.');
      }
    }
  }

  Future<void> _displayAnnouncementDialog(ServerAnnouncement ann) async {
    _announcementDialogShowing = true;
    final isCritical = ann.type == 'CRITICAL' || ann.isMandatory;
    final isWarning = ann.type == 'WARNING';
    final isPromo = ann.type == 'PROMO';
    final isUpdate = ann.type == 'UPDATE';

    final Color accentColor = isCritical
        ? cyberRed
        : isWarning
            ? cyberYellow
            : isPromo
                ? const Color(0xFFD946EF)
                : isUpdate
                    ? cyberCyan
                    : cyberGreen;

    final IconData typeIcon = isCritical
        ? Icons.warning_rounded
        : isWarning
            ? Icons.bolt_rounded
            : isPromo
                ? Icons.card_giftcard_rounded
                : isUpdate
                    ? Icons.system_update_rounded
                    : Icons.info_outline_rounded;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !ann.isMandatory,
        builder: (dialogCtx) => PopScope(
          canPop: !ann.isMandatory,
          child: AlertDialog(
            backgroundColor: cyberCardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: accentColor, width: 2),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withOpacity(0.4)),
                  ),
                  child: Icon(typeIcon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ann.type,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ann.title,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _fieldBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _text12),
                    ),
                    child: Text(
                      ann.message,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (ann.isMandatory) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.lock_clock, size: 14, color: cyberRed),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Annonce obligatoire avant utilisation du VPN',
                            style: TextStyle(color: cyberRed, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (ann.actionButtonText != null && ann.actionButtonUrl != null && ann.actionButtonUrl!.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    _markAnnouncementDismissed(ann.id);
                    Navigator.pop(dialogCtx);
                    _openUrlSafe(ann.actionButtonUrl!);
                  },
                  icon: const Icon(Icons.open_in_new, size: 14, color: Colors.black),
                  label: Text(
                    ann.actionButtonText!,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              TextButton(
                onPressed: () {
                  _markAnnouncementDismissed(ann.id);
                  Navigator.pop(dialogCtx);
                },
                child: Text(
                  ann.isMandatory ? 'J\'ai compris et je poursuis' : 'Fermer',
                  style: TextStyle(
                    color: ann.isMandatory ? cyberGreen : _text60,
                    fontWeight: ann.isMandatory ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      _announcementDialogShowing = false;
    }
  }

  Future<void> _markAnnouncementDismissed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('abess_dismissed_announcements') ?? [];
    if (!list.contains(id)) {
      list.add(id);
      await prefs.setStringList('abess_dismissed_announcements', list);
    }
    if (mounted) {
      setState(() {
        _hasUnreadAnnouncements = _activeAnnouncements.any((a) =>
            a.isMandatory || a.showMode == 'EVERY_LAUNCH' || !list.contains(a.id));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _pulseController.stop();
      _rotateController.stop();
    } else {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      if (!_rotateController.isAnimating) _rotateController.repeat();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _telemetryTimer?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _tokenInputCtrl.dispose();
    _fileInputCtrl.dispose();
    _createTokenCodeCtrl.dispose();
    _createPlanNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('abess_device_id');
    if (id == null) {
      final rand = math.Random.secure();
      final fingerprint = List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join().toUpperCase();
      id = 'ABESS-INST-$fingerprint';
      await prefs.setString('abess_device_id', id);
    }
    if (mounted) {
      setState(() => _deviceId = id!);
    }
  }

  void _addLog(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '[$time] $msg');
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  // Initialisation du Moteur V2Ray
  Future<void> _initV2Ray() async {
    try {
      v2ray = FlutterV2ray(
        onStatusChanged: (status) {
          if (!mounted) return;
          setState(() {
            final wasConnected = isConnected;
            vpnStatus = status.state;

            // Use the counters supplied by flutter_v2ray/Xray instead of
            // generating plausible-looking but fictitious traffic values.
            _currentDownloadBytes = math.max(0, status.download);
            _currentUploadBytes = math.max(0, status.upload);
            _currentDownloadSpeed = math.max(0, status.downloadSpeed) / (1024 * 1024);
            _currentUploadSpeed = math.max(0, status.uploadSpeed) / (1024 * 1024);
            _totalDownloadMb = _currentDownloadBytes / (1024 * 1024);
            _totalUploadMb = _currentUploadBytes / (1024 * 1024);

            if (currentServer != null && currentServer!.token != null) {
              final sessionUsageGb = (_currentDownloadBytes + _currentUploadBytes) / (1024 * 1024 * 1024);
              currentServer!.bandwidthUsedGb = math.max(
                currentServer!.bandwidthUsedGb,
                _quotaUsageAtSessionStartGb + sessionUsageGb,
              );
            }

            if (status.state == 'CONNECTED') {
              isConnected = true;
              isConnecting = false;
              _reconnectAttempts = 0;
              disconnectAlert = false;
              if (!wasConnected) _startTelemetry();
            } else if (status.state == 'DISCONNECTED') {
              isConnected = false;
              isConnecting = false;
              _stopTelemetry();
              if (_userWantedConnection) {
                if (isDisconnectAlertEnabled) {
                  disconnectAlert = true;
                  _addLog('ALERTE : le tunnel VPN est interrompu. Android peut reprendre le trafic hors VPN. Activez le VPN permanent et le blocage sans VPN dans les paramètres Android pour un verrouillage système.');
                }
                if (isAutoReconnectEnabled && _reconnectAttempts < 5) {
                  _reconnectAttempts++;
                  _addLog('RECONNEXION AUTO DANS 3s (TENTATIVE $_reconnectAttempts/5)...');
                  _reconnectTimer?.cancel();
                  _reconnectTimer = Timer(Duration(seconds: 3), () {
                    if (_userWantedConnection && !isConnected) {
                      _connectVpn();
                    }
                  });
                }
              }
            }
          });
          _addLog('V2RAY KERNEL: ${status.state}');
        },
      );
      await v2ray.initializeV2Ray();
      if (mounted) {
        setState(() => isV2rayInitialized = true);
      }
      _addLog('MOTEUR V2RAY/XRAY INITIALISÉ');
    } catch (e) {
      _addLog('NOTE ENGINE (FALLBACK PRET): $e');
    }
  }

  Map<String, dynamic> _serverToJsonMap(ImportedVpnServer server) => {
    'id': server.id,
    'name': server.name,
    'address': server.address,
    'port': server.port,
    'path': server.path,
    'sni': server.sni,
    'uuid': server.uuid,
    'bandwidthGb': server.bandwidthGb,
    'bandwidthUsedGb': server.bandwidthUsedGb,
    'expiresAt': server.expiresAt.toIso8601String(),
    'token': server.token,
    'encryptedLink': server.encryptedLink,
    'deviceLimit': server.deviceLimit,
    'allowedDeviceId': server.allowedDeviceId,
    'licenseId': server.licenseId,
    'protocol': server.protocol,
    'transport': server.transport,
    'tls': server.tls,
    'method': server.method,
    'wsHost': server.wsHost,
  };

  ImportedVpnServer _serverFromJsonMap(Map<String, dynamic> map) => ImportedVpnServer(
    id: map['id']?.toString(),
    name: map['name']?.toString() ?? 'ABESS VPN importé',
    address: map['address']?.toString() ?? '',
    port: (map['port'] as num?)?.toInt() ?? 443,
    path: map['path']?.toString() ?? '/@abess237',
    sni: map['sni']?.toString() ?? map['address']?.toString() ?? '',
    uuid: map['uuid']?.toString() ?? '',
    bandwidthGb: (map['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
    bandwidthUsedGb: (map['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
    expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? '')
        ?? DateTime.now().add(Duration(days: 30)),
    token: map['token']?.toString(),
    encryptedLink: map['encryptedLink']?.toString(),
    deviceLimit: (map['deviceLimit'] as num?)?.toInt() ?? 1,
    allowedDeviceId: map['allowedDeviceId']?.toString(),
    licenseId: map['licenseId']?.toString(),
    protocol: map['protocol']?.toString() ?? 'vless',
    transport: map['transport']?.toString() ?? 'ws',
    tls: map['tls'] as bool? ?? true,
    method: map['method']?.toString() ?? 'aes-128-gcm',
    wsHost: map['wsHost']?.toString() ?? '',
  );

  String _profileIdentityKey(ImportedVpnServer server) {
    final licenseId = server.licenseId?.trim();
    if (licenseId != null && licenseId.isNotEmpty) return 'manual-license:$licenseId';
    final token = server.token?.trim();
    if (token != null && token.isNotEmpty &&
        token != 'CUSTOM-ZERO-TOKEN' && token != 'RAW-LINK-IMPORT') {
      return 'token:${token.toUpperCase()}';
    }
    final link = server.encryptedLink?.trim();
    if (link != null && link.isNotEmpty) return 'link:$link';
    return 'manual:${server.protocol.toLowerCase()}|${server.transport.toLowerCase()}|${server.address.toLowerCase()}|${server.port}|${server.uuid}|${server.path}|${server.sni}|${server.wsHost}';
  }

  Future<void> _setDisconnectAlertEnabled(bool enabled) async {
    if (mounted) {
      setState(() => isDisconnectAlertEnabled = enabled);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('abess_disconnect_alert', enabled);
  }

  Future<void> _setAutoReconnectEnabled(bool enabled) async {
    if (mounted) {
      setState(() => isAutoReconnectEnabled = enabled);
    }
    if (!enabled) _reconnectTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('abess_auto_reconnect', enabled);
  }


  Future<void> _persistProfileState() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedProfiles = jsonEncode(savedServers.map(_serverToJsonMap).toList());

    try {
      // Tokens, UUIDs, encrypted links and connection credentials belong in
      // Android Keystore-backed secure storage, never in plain SharedPreferences.
      await _secureStorage.write(key: _savedProfilesKey, value: encodedProfiles);
    } catch (error) {
      _addLog('STOCKAGE SÉCURISÉ INDISPONIBLE : profils non enregistrés ($error)');
      _showToast('Stockage sécurisé indisponible. La configuration n’a pas été sauvegardée.');
      return;
    }

    // Remove legacy plaintext copies only after the secure write succeeded.
    await prefs.remove(_savedProfilesKey);
    await prefs.remove('abess_imported_server');

    if (currentServer == null) {
      await prefs.remove(_selectedProfileKey);
    } else {
      await prefs.setString(_selectedProfileKey, currentServer!.id);
    }
  }

  Future<void> _loadSavedServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final disconnectAlertPreference = prefs.getBool('abess_disconnect_alert') ??
        prefs.getBool('abess_kill_switch') ??
        true;
    setState(() {
      isDisconnectAlertEnabled = disconnectAlertPreference;
      isAutoReconnectEnabled = prefs.getBool('abess_auto_reconnect') ?? true;
    });
    if (!prefs.containsKey('abess_disconnect_alert')) {
      await prefs.setBool('abess_disconnect_alert', disconnectAlertPreference);
    }

    final loaded = <ImportedVpnServer>[];
    void appendProfile(dynamic item) {
      if (item is! Map) return;
      final server = _serverFromJsonMap(Map<String, dynamic>.from(item));
      if (server.address.isNotEmpty && server.uuid.isNotEmpty) loaded.add(server);
    }

    String? secureStoredList;
    try {
      secureStoredList = await _secureStorage.read(key: _savedProfilesKey);
    } catch (error) {
      _addLog('LECTURE DU STOCKAGE SÉCURISÉ IMPOSSIBLE : $error');
    }

    var loadedFromSecureStorage = false;
    if (secureStoredList != null) {
      try {
        final decoded = jsonDecode(secureStoredList);
        if (decoded is! List) throw const FormatException('La liste sécurisée des profils est invalide.');
        for (final item in decoded) {
          appendProfile(item);
        }
        loadedFromSecureStorage = true;
      } catch (error) {
        loaded.clear();
        _addLog('PROFILS SÉCURISÉS ILLISIBLES : $error. Tentative de récupération des anciennes données.');
      }
    }

    if (!loadedFromSecureStorage) {
      final sharedProfiles = prefs.getString(_savedProfilesKey);
      if (sharedProfiles != null) {
        try {
          final decoded = jsonDecode(sharedProfiles);
          if (decoded is! List) throw const FormatException('La liste historique des profils est invalide.');
          for (final item in decoded) {
            appendProfile(item);
          }
        } catch (error) {
          loaded.clear();
          _addLog('ANCIENNE LISTE DE PROFILS ILLISIBLE : $error');
        }
      } else {
        // One-time migration from the previous single-profile plaintext key.
        final legacy = prefs.getString('abess_imported_server');
        if (legacy != null) {
          try {
            final decoded = jsonDecode(legacy);
            if (decoded is Map) appendProfile(decoded);
          } catch (error) {
            _addLog('ANCIEN PROFIL ILLISIBLE : $error');
          }
        }
      }
    }

    final wantedId = prefs.getString(_selectedProfileKey);
    ImportedVpnServer? selected;
    for (final server in loaded) {
      if (server.id == wantedId) {
        selected = server;
        break;
      }
    }
    selected ??= loaded.isNotEmpty ? loaded.first : null;
    if (!mounted) return;
    setState(() {
      savedServers = loaded;
      currentServer = selected;
    });

    if (loadedFromSecureStorage) {
      // Only remove plaintext copies after a valid secure copy was parsed.
      await prefs.remove(_savedProfilesKey);
      await prefs.remove('abess_imported_server');
    } else if (loaded.isNotEmpty) {
      // Migration is crash-safe: _persistProfileState deletes plaintext copies
      // only after Android Keystore-backed storage confirms the secure write.
      await _persistProfileState();
    }

    if (selected == null) {
      _addLog('AUCUN SERVEUR ACTIF : IMPORTez un token ou un lien de configuration');
    } else {
      _addLog('PROFIL RESTAURÉ : ${selected.name} (${loaded.length} profil(s) enregistré(s))');
    }
  }

  Future<void> _storeAndSelectServer(ImportedVpnServer server, {bool switchToConnection = true}) async {
    final identity = _profileIdentityKey(server);
    final existingIndex = savedServers.indexWhere((item) =>
        item.id == server.id || _profileIdentityKey(item) == identity);
    final storedMap = _serverToJsonMap(server);
    if (existingIndex >= 0) {
      final previous = savedServers[existingIndex];
      storedMap['id'] = previous.id;
      if (server.licenseId != null && server.licenseId == previous.licenseId) {
        storedMap['bandwidthUsedGb'] = math.max(server.bandwidthUsedGb, previous.bandwidthUsedGb);
      }
    }
    final storedServer = existingIndex >= 0 ? _serverFromJsonMap(storedMap) : server;
    final next = List<ImportedVpnServer>.from(savedServers);
    if (existingIndex >= 0) {
      next[existingIndex] = storedServer;
    } else {
      next.add(storedServer);
    }

    // Keep an active tunnel tied to the profile it actually uses. The new profile
    // is saved immediately, but selection is deferred until the user disconnects.
    final keepCurrentTunnel = isConnected && currentServer != null &&
        _profileIdentityKey(currentServer!) != identity;
    setState(() {
      savedServers = next;
      if (!keepCurrentTunnel) {
        currentServer = storedServer;
        if (switchToConnection) _currentNavIndex = 0;
      }
    });
    await _persistProfileState();
    if (keepCurrentTunnel) {
      _showToast('Configuration ajoutée. Déconnectez le VPN pour la sélectionner.');
    }
  }

  Future<void> _saveCurrentServer() async {
    if (currentServer == null) {
      await _persistProfileState();
      return;
    }
    final index = savedServers.indexWhere((item) => item.id == currentServer!.id);
    if (index >= 0) {
      savedServers[index] = currentServer!;
    } else {
      savedServers.add(currentServer!);
    }
    await _persistProfileState();
  }

  Future<void> _selectSavedServer(ImportedVpnServer server) async {
    if (isConnected && currentServer?.id != server.id) {
      _showToast('Déconnectez le VPN avant de changer de configuration.');
      return;
    }
    setState(() {
      currentServer = savedServers.firstWhere(
        (item) => item.id == server.id,
        orElse: () => server,
      );
      _currentNavIndex = 0;
      _lastReportedDownloadBytes = _currentDownloadBytes;
      _lastReportedUploadBytes = _currentUploadBytes;
    });
    await _persistProfileState();
    _showToast('Configuration sélectionnée : ${server.name}');
  }

  Future<void> _deleteSavedServer(ImportedVpnServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cyberCardBg,
        title: Text('Supprimer la configuration ?', style: TextStyle(color: _textPrimary, fontSize: 15)),
        content: Text('« ${server.name} » sera supprimée de cet appareil.', style: TextStyle(color: _text70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('ANNULER')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('SUPPRIMER', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final wasSelected = currentServer?.id == server.id;
    if (wasSelected && isConnected) await _disconnectVpn();
    final next = savedServers.where((item) => item.id != server.id).toList();
    setState(() {
      savedServers = next;
      if (wasSelected) currentServer = next.isNotEmpty ? next.first : null;
    });
    await _persistProfileState();
    _showToast('Configuration supprimée de cet appareil.');
  }

  Color _protocolColor(String proto) {
    switch (proto.toLowerCase()) {
      case 'vless': return cyberCyan;
      case 'vmess': return const Color(0xFFA855F7);
      case 'trojan': return const Color(0xFFF97316);
      case 'ssh': return cyberYellow;
      case 'shadowsocks': case 'ss': return cyberGreen;
      default: return cyberCyan;
    }
  }

  Widget _buildSavedProfilesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cyberCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cyberCyan.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(color: cyberCyan.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cyberCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dns_outlined, color: cyberCyan, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('MES CONFIGURATIONS', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cyberCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cyberCyan.withOpacity(0.4)),
                ),
                child: Text('${savedServers.length}', style: const TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (savedServers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Aucune configuration enregistrée.\nActivez un token ou importez un lien ci-dessous.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _text54, fontSize: 11),
                ),
              ),
            )
          else
            ...savedServers.map((profile) {
              final selected = currentServer?.id == profile.id;
              final protoColor = _protocolColor(profile.protocol);
              return Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: selected ? cyberGreen.withOpacity(0.10) : _fieldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? cyberGreen : _text12,
                    width: selected ? 1.5 : 1.0,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: cyberGreen.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => unawaited(_selectSavedServer(profile)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selected ? cyberGreen : _text38,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: protoColor.withOpacity(0.16),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: protoColor.withOpacity(0.5), width: 0.8),
                                          ),
                                          child: Text(
                                            profile.protocol.toUpperCase(),
                                            style: TextStyle(
                                              color: protoColor,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            profile.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: selected ? cyberGreen : _textPrimary,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${profile.transport.toUpperCase()} · ${profile.tls ? "TLS" : "DIRECT"} · ${profile.address}:${profile.port}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _text54, fontSize: 9.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (profile.protocol.toLowerCase() == 'ssh')
                      IconButton(
                        tooltip: 'Copier la configuration JSON SSH',
                        onPressed: () => _copySshJsonConfig(profile),
                        icon: const Icon(Icons.code, color: cyberYellow, size: 18),
                      ),
                    IconButton(
                      tooltip: 'Supprimer cette configuration',
                      onPressed: () => unawaited(_deleteSavedServer(profile)),
                      icon: Icon(Icons.delete_outline, color: cyberRed, size: 18),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _copySshJsonConfig(ImportedVpnServer profile) async {
    final userPass = profile.uuid.split(':');
    final user = userPass.isNotEmpty ? userPass[0] : 'dany';
    final pass = userPass.length > 1 ? userPass.sublist(1).join(':') : '#12345';
    final jsonMap = {
      'configs': [
        {
          'name': profile.name,
          'address': '${profile.address}:${profile.port}',
          'type': 'SSH',
          'sshConfig': {
            'sshConfigType': 'SSH-Payload',
            'remarks': profile.name,
            'sshHost': profile.address,
            'sshPort': profile.port,
            'sshUsername': user,
            'sshPassword': pass,
            'payload': profile.method,
          }
        }
      ]
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonMap);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    _showToast('Configuration JSON SSH copiée !');
  }

  void _showSshConfigDialog(ImportedVpnServer srv) {
    final userPass = srv.uuid.split(':');
    final user = userPass.isNotEmpty ? userPass[0] : 'dany';
    final pass = userPass.length > 1 ? userPass.sublist(1).join(':') : '#12345';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cyberCardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: cyberYellow, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cyberYellow.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.terminal_rounded, color: cyberYellow, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Configuration SSH-Payload',
                style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                srv.name,
                style: const TextStyle(color: cyberYellow, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildSshDetailTile('Serveur SSH', '${srv.address}:${srv.port}'),
              _buildSshDetailTile('Nom d\'utilisateur', user),
              _buildSshDetailTile('Mot de passe', pass),
              _buildSshDetailTile('Protocole', 'SSH Dropbear (Port ${srv.port})'),
              const SizedBox(height: 8),
              Text(
                'Payload HTTP Injection :',
                style: TextStyle(color: _text54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _fieldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _text12),
                ),
                child: SelectableText(
                  srv.method,
                  style: const TextStyle(color: cyberCyan, fontSize: 9, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Cette configuration utilise le protocole SSH avec injection HTTP (Dropbear/WebSocket). Copiez le JSON complet ci-dessous pour l\'injecter dans vos outils compatibles (Peddygist, HTTP Injector, HA Tunnel).',
                style: TextStyle(color: _text60, fontSize: 10),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FERMER', style: TextStyle(color: _text60)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _copySshJsonConfig(srv);
            },
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('COPIER JSON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: cyberYellow,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSshDetailTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: _text54, fontSize: 10)),
          SelectableText(
            value,
            style: TextStyle(color: _textPrimary, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  // Mesure la latence réelle : tunnel actif d'abord, puis API de contrôle.
  Future<void> _measureRealPing() async {
    if (isV2rayInitialized && isConnected) {
      try {
        final latency = await v2ray.getConnectedServerDelay();
        if (latency >= 0 && mounted) {
          setState(() => _currentPingMs = latency);
          return;
        }
      } catch (_) {}
    }

    for (final base in _masterServerUrls) {
      try {
        final stopwatch = Stopwatch()..start();
        final res = await http.get(Uri.parse('$base/api/v1/ping')).timeout(Duration(seconds: 3));
        stopwatch.stop();
        if (res.statusCode == 200) {
          if (mounted) setState(() => _currentPingMs = stopwatch.elapsedMilliseconds);
          return;
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _currentPingMs = 0);
  }

  // Télémétrie réelle provenant du statut Xray et synchronisation des deltas.
  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _pingTimer?.cancel();
    _connectionDurationSeconds = 0;
    _quotaUsageAtSessionStartGb = currentServer?.bandwidthUsedGb ?? 0.0;
    _lastReportedDownloadBytes = _currentDownloadBytes;
    _lastReportedUploadBytes = _currentUploadBytes;

    _pingTimer = Timer.periodic(Duration(seconds: 6), (_) => _measureRealPing());

    _telemetryTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (!isConnected || !mounted) return;

      if (currentServer?.isExpired == true || currentServer?.isQuotaExceeded == true) {
        final expired = currentServer?.isExpired == true;
        _userWantedConnection = false;
        _reconnectTimer?.cancel();
        _addLog(expired
            ? 'FORFAIT EXPIRÉ : DÉCONNEXION AUTOMATIQUE'
            : 'QUOTA ÉPUISÉ : DÉCONNEXION AUTOMATIQUE');
        unawaited(_disconnectVpn());
        return;
      }

      setState(() {
        _connectionDurationSeconds++;
        _speedHistoryDownload.add(FlSpot(_speedHistoryDownload.length.toDouble(), _currentDownloadSpeed));
        if (_speedHistoryDownload.length > 15) {
          _speedHistoryDownload.removeAt(0);
          for (int i = 0; i < _speedHistoryDownload.length; i++) {
            _speedHistoryDownload[i] = FlSpot(i.toDouble(), _speedHistoryDownload[i].y);
          }
        }
        _speedHistoryUpload.add(FlSpot(_speedHistoryUpload.length.toDouble(), _currentUploadSpeed));
        if (_speedHistoryUpload.length > 15) {
          _speedHistoryUpload.removeAt(0);
          for (int i = 0; i < _speedHistoryUpload.length; i++) {
            _speedHistoryUpload[i] = FlSpot(i.toDouble(), _speedHistoryUpload[i].y);
          }
        }
      });

      if (_connectionDurationSeconds % 10 == 0) {
        unawaited(_saveCurrentServer());
        if (_isManagedLicense(currentServer)) _syncUsageWithServer();
      }
    });
  }

  bool _isManagedLicense(ImportedVpnServer? server) {
    final token = server?.token?.trim();
    return token != null && token.isNotEmpty &&
        token != 'CUSTOM-ZERO-TOKEN' && token != 'RAW-LINK-IMPORT';
  }

  Future<void> _syncUsageWithServer() async {
    if (!_isManagedLicense(currentServer)) return;
    final downloadDelta = math.max(0, _currentDownloadBytes - _lastReportedDownloadBytes);
    final uploadDelta = math.max(0, _currentUploadBytes - _lastReportedUploadBytes);

    for (final base in _masterServerUrls) {
      try {
        final res = await http.post(
          Uri.parse('$base/api/v1/client/telemetry'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': currentServer!.token,
            'bytesDownloaded': downloadDelta,
            'bytesUploaded': uploadDelta,
            'durationSeconds': 10,
            'deviceId': _deviceId,
          }),
        ).timeout(Duration(seconds: 3));

        if (res.statusCode == 401 || res.statusCode == 403) {
          String serverReason = 'Le serveur a refusé cette licence VPN.';
          try {
            final body = jsonDecode(res.body);
            if (body is Map && body['error'] is String) serverReason = body['error'] as String;
          } catch (_) {}
          _addLog('LICENCE REFUSÉE PAR LE SERVEUR (HTTP ${res.statusCode}) : $serverReason');
          await _disconnectVpn();
          _showToast(serverReason);
          return;
        }
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body);
        _lastReportedDownloadBytes = _currentDownloadBytes;
        _lastReportedUploadBytes = _currentUploadBytes;

        if (data['bandwidthUsedGb'] is num && currentServer != null) {
          if (mounted) {
            setState(() {
              currentServer!.bandwidthUsedGb = math.max(
                currentServer!.bandwidthUsedGb,
                (data['bandwidthUsedGb'] as num).toDouble(),
              );
            });
            await _saveCurrentServer();
          }
        }

        if (data['isQuotaExceeded'] == true || data['status'] == 'quota_exceeded') {
          await _disconnectVpn();
          _showQuotaExceededAlert();
          return;
        }
        if (data['isExpired'] == true || data['status'] == 'expired') {
          await _disconnectVpn();
          _showExpiredAlert();
          return;
        }
        if (data['status'] != null && data['status'] != 'active') {
          _addLog('ACCÈS VPN DÉSACTIVÉ : ${data['status']}');
          await _disconnectVpn();
          _showToast('Cette licence VPN est désactivée. Contactez votre revendeur.');
          return;
        }
        return;
      } catch (_) {}
    }
  }

  void _stopTelemetry() {
    _telemetryTimer?.cancel();
    _pingTimer?.cancel();
    if (mounted) {
      setState(() {
        _currentDownloadSpeed = 0.0;
        _currentUploadSpeed = 0.0;
      });
    }
  }

  Future<void> _openUrlSafe(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lien copié dans le presse-papier !'),
              backgroundColor: cyberGreen,
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lien copié dans le presse-papier !'),
            backgroundColor: cyberGreen,
          ),
        );
      }
    }
  }

  void _showQuotaExceededAlert() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cyberCardBg,
        title: Text('🛑 QUOTA ÉPUISÉ', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
        content: Text(
          'Votre quota de ${currentServer?.bandwidthGb.toStringAsFixed(1)} Go est totalement consommé. Veuillez renouveler votre accès ou contacter l\'assistance WhatsApp ($_whatsappSupportPhone).',
          style: TextStyle(color: _text70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FERMER', style: TextStyle(color: _text60)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_whatsappSupportUrl);
            },
            icon: Icon(Icons.chat, color: cyberGreen, size: 14),
            label: Text('ASSISTANCE WHATSAPP', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateConfigModal();
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
            child: Text('CRÉER FORFAIT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showExpiredAlert() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cyberCardBg,
        title: Text('⏳ LICENCE EXPIRÉE', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
        content: Text(
          'La date d\'expiration de votre licence VPN est dépassée. Veuillez générer un nouveau token ou contacter l\'assistance WhatsApp.',
          style: TextStyle(color: _text70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FERMER', style: TextStyle(color: _text60)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_whatsappSupportUrl);
            },
            icon: Icon(Icons.chat, color: cyberGreen, size: 14),
            label: Text('SUPPORT WHATSAPP', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateConfigModal();
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
            child: Text('NOUVEAU PASS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSpeedTestModal() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setMState) {
            bool isTesting = false;
            int testPing = _currentPingMs;
            double testDl = 0.0;
            double testUl = 0.0;
            int progress = 0;
            String status = 'Prêt à tester la bande passante réelle';
            String verdict = '';
            bool pingSucceeded = false;
            bool downloadSucceeded = false;
            bool uploadSucceeded = false;

            Future<void> runTest() async {
              pingSucceeded = false;
              downloadSucceeded = false;
              uploadSucceeded = false;
              if (_masterServerUrls.isEmpty) {
                setMState(() {
                  isTesting = false;
                  progress = 100;
                  status = 'API non configurée';
                  verdict = 'Configure VPN_DOMAIN dans les variables GitHub du dépôt AbessVpn-Cyber puis reconstruis l’APK.';
                });
                return;
              }
              setMState(() {
                isTesting = true;
                progress = 15;
                status = 'Mesure de la latence Ping (ms)...';
              });

              try {
                final sw = Stopwatch()..start();
                final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/ping')).timeout(Duration(seconds: 4));
                sw.stop();
                if (res.statusCode != 200) throw StateError('Ping HTTP ${res.statusCode}');
                testPing = sw.elapsedMilliseconds;
                pingSucceeded = true;
              } catch (_) {
                testPing = 0;
              }

              setMState(() {
                progress = 45;
                status = 'Test de débit descendant (Download)...';
              });

              try {
                final sw = Stopwatch()..start();
                final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/speedtest/download?bytes=1048576')).timeout(Duration(seconds: 5));
                sw.stop();
                if (res.statusCode != 200 || res.bodyBytes.isEmpty) throw StateError('Download HTTP ${res.statusCode}');
                final secs = math.max(0.05, sw.elapsedMilliseconds / 1000.0);
                final mb = res.bodyBytes.length / (1024.0 * 1024.0);
                testDl = mb / secs;
                downloadSucceeded = true;
              } catch (_) {
                testDl = 0.0;
              }

              setMState(() {
                progress = 80;
                status = 'Test de débit montant (Upload)...';
              });

              try {
                final sw = Stopwatch()..start();
                final dummy = List<int>.filled(256 * 1024, 65);
                final response = await http.post(
                  Uri.parse('${_masterServerUrls[0]}/api/v1/speedtest/upload'),
                  headers: {'Content-Type': 'application/octet-stream'},
                  body: dummy,
                ).timeout(Duration(seconds: 5));
                sw.stop();
                if (response.statusCode != 200) throw StateError('Upload HTTP ${response.statusCode}');
                final secs = math.max(0.05, sw.elapsedMilliseconds / 1000.0);
                testUl = (dummy.length / (1024.0 * 1024.0)) / secs;
                uploadSucceeded = true;
              } catch (_) {
                testUl = 0.0;
              }

              setMState(() {
                progress = 100;
                isTesting = false;
                final allSucceeded = pingSucceeded && downloadSucceeded && uploadSucceeded;
                status = allSucceeded
                    ? 'Mesures réelles terminées.'
                    : 'Test partiel : une ou plusieurs mesures ont échoué.';
                verdict = allSucceeded
                    ? (testPing < 70
                        ? 'EXCELLENT : latence mesurée sous 70 ms.'
                        : 'LATENCE MESURÉE : vérifiez les valeurs avant d’évaluer la qualité.')
                    : 'Certaines valeurs sont indisponibles. Aucun débit de remplacement n’a été inventé.';
              });
              _addLog('[SPEEDTEST] Ping: $testPing ms • DL: ${testDl.toStringAsFixed(1)} Mo/s • UL: ${testUl.toStringAsFixed(1)} Mo/s');
            }

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Color(0xFF060D1D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: cyberCyan, width: 2)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: _text24, borderRadius: BorderRadius.circular(2)),
                    ),
                    SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.speed, color: cyberCyan, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'SPEED TEST CYBER V2.5',
                          style: TextStyle(color: _textPrimary, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(status, style: TextStyle(color: _text60, fontSize: 11)),
                    SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress / 100.0,
                        minHeight: 6,
                        backgroundColor: _softSurfaceFill,
                        valueColor: const AlwaysStoppedAnimation<Color>(cyberCyan),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _metricTileFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberYellow.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                Text('LATENCE PING', style: TextStyle(color: cyberYellow, fontSize: 9, fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text('$testPing ms', style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _metricTileFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberCyan.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                Text('DOWNLOAD', style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text('${testDl.toStringAsFixed(1)} Mo/s', style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${(testDl * 8).toStringAsFixed(0)} Mbps', style: TextStyle(color: _text38, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _metricTileFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberGreen.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                Text('UPLOAD', style: TextStyle(color: cyberGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text('${testUl.toStringAsFixed(1)} Mo/s', style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${(testUl * 8).toStringAsFixed(0)} Mbps', style: TextStyle(color: _text38, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (verdict.isNotEmpty) ...[
                      SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cyberGreen.withOpacity( 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cyberGreen.withOpacity( 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: cyberGreen, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(verdict, style: TextStyle(color: _textPrimary, fontSize: 10, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: isTesting ? null : runTest,
                      icon: isTesting
                          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : Icon(Icons.play_arrow, color: Colors.black),
                      label: Text(
                        isTesting ? 'ANALYSE EN COURS...' : 'LANCER LE TEST DE DÉBIT',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyberCyan,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDiagnosticModal() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setMState) {
            bool isDiagnosing = false;
            String? dnsResult;
            String? apiPingResult;
            String? socketResult;
            String? tokenResult;
            bool? dnsOk;
            bool? apiOk;
            bool? socketOk;
            bool? tokenOk;
            String overallVerdict = '';

            Future<void> runDiagnostic() async {
              setMState(() {
                isDiagnosing = true;
                dnsResult = 'Résolution en cours...';
                apiPingResult = 'Test en cours...';
                socketResult = 'Handshake en cours...';
                tokenResult = 'Validation...';
                dnsOk = null;
                apiOk = null;
                socketOk = null;
                tokenOk = null;
                overallVerdict = '';
              });

              final host = currentServer?.address.isNotEmpty == true
                  ? currentServer!.address
                  : (_masterServerUrls.isNotEmpty
                      ? Uri.parse(_masterServerUrls[0]).host
                      : (Uri.tryParse(_configuredApiBaseUrl)?.host ?? ''));
              final port = currentServer?.port ?? 80;

              // 1. DNS Resolution
              try {
                final swDns = Stopwatch()..start();
                final addrs = await InternetAddress.lookup(host).timeout(Duration(seconds: 4));
                swDns.stop();
                if (addrs.isNotEmpty) {
                  dnsOk = true;
                  dnsResult = '${addrs.first.address} (${swDns.elapsedMilliseconds} ms)';
                } else {
                  dnsOk = false;
                  dnsResult = 'Aucune adresse IP trouvée';
                }
              } catch (e) {
                dnsOk = false;
                dnsResult = 'Échec DNS (${e.toString().split(':').first})';
              }

              // 2. Master Panel Ping
              try {
                if (_masterServerUrls.isNotEmpty) {
                  final swApi = Stopwatch()..start();
                  final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/ping')).timeout(Duration(seconds: 4));
                  swApi.stop();
                  if (res.statusCode == 200) {
                    apiOk = true;
                    apiPingResult = 'Opérationnel (${swApi.elapsedMilliseconds} ms)';
                  } else {
                    apiOk = false;
                    apiPingResult = 'HTTP ${res.statusCode}';
                  }
                } else {
                  apiOk = false;
                  apiPingResult = 'Serveur non configuré';
                }
              } catch (_) {
                apiOk = false;
                apiPingResult = 'Inaccessible ou délai dépassé';
              }

              // 3. Socket Handshake
              try {
                final swSock = Stopwatch()..start();
                final socket = await Socket.connect(host, port, timeout: Duration(seconds: 4));
                swSock.stop();
                socket.destroy();
                socketOk = true;
                socketResult = 'Port $port ouvert (${swSock.elapsedMilliseconds} ms)';
              } catch (e) {
                socketOk = false;
                socketResult = 'Port $port inaccessible';
              }

              // 4. Token & Licence Status
              if (currentServer != null && currentServer!.token?.isNotEmpty == true) {
                final now = DateTime.now();
                final days = currentServer!.expiresAt.difference(now).inDays;
                final quotaLeft = math.max(0.0, currentServer!.bandwidthGb - currentServer!.bandwidthUsedGb);
                if (days > 0 && quotaLeft > 0) {
                  tokenOk = true;
                  tokenResult = '$days j restants • ${quotaLeft.toStringAsFixed(1)} Go';
                } else {
                  tokenOk = false;
                  tokenResult = days <= 0 ? 'Expiré' : 'Quota épuisé';
                }
              } else {
                tokenOk = false;
                tokenResult = 'Aucun token actif';
              }

              setMState(() {
                isDiagnosing = false;
                final allGood = (dnsOk == true) && (apiOk == true) && (socketOk == true) && (tokenOk == true);
                if (allGood) {
                  overallVerdict = 'Réseau 100% opérationnel. Prêt pour la connexion haute vitesse.';
                } else if (dnsOk == false) {
                  overallVerdict = 'Problème de réseau local ou blocage DNS par l’opérateur FAI.';
                } else if (socketOk == false) {
                  overallVerdict = 'Le port $port est bloqué ou inaccessible sur votre connexion.';
                } else if (tokenOk == false) {
                  overallVerdict = 'Votre licence token nécessite un renouvellement ou une recharge.';
                } else {
                  overallVerdict = 'Le serveur maître répond lentement ou est en maintenance.';
                }
              });

              _addLog('[DIAGNOSTIC] DNS: $dnsResult • API: $apiPingResult • Port $port: $socketResult');
            }

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Color(0xFF060D1D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: cyberGreen, width: 2)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: _text24, borderRadius: BorderRadius.circular(2)),
                    ),
                    SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.health_and_safety_outlined, color: cyberGreen, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'DIAGNOSTIC TECHNIQUE COMPLET',
                          style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Test bout-en-bout : DNS, API Maître, Port Réseau et Licence',
                      style: TextStyle(color: _text54, fontSize: 10),
                    ),
                    SizedBox(height: 16),
                    _buildDiagItem('1. Résolution DNS Hôte', dnsResult ?? 'Non testé', dnsOk),
                    SizedBox(height: 8),
                    _buildDiagItem('2. Passerelle Serveur (API)', apiPingResult ?? 'Non testé', apiOk),
                    SizedBox(height: 8),
                    _buildDiagItem('3. Handshake Port (${currentServer?.port ?? 80})', socketResult ?? 'Non testé', socketOk),
                    SizedBox(height: 8),
                    _buildDiagItem('4. Licence & Forfait', tokenResult ?? 'Non testé', tokenOk),
                    if (overallVerdict.isNotEmpty) ...[
                      SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (overallVerdict.contains('100%') ? cyberGreen : cyberYellow).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (overallVerdict.contains('100%') ? cyberGreen : cyberYellow).withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              overallVerdict.contains('100%') ? Icons.check_circle : Icons.info_outline,
                              color: overallVerdict.contains('100%') ? cyberGreen : cyberYellow,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(overallVerdict, style: TextStyle(color: _textPrimary, fontSize: 10, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isDiagnosing ? null : runDiagnostic,
                            icon: isDiagnosing
                                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : Icon(Icons.refresh, color: Colors.black, size: 16),
                            label: Text(
                              isDiagnosing ? 'DIAGNOSTIC EN COURS...' : 'LANCER LE DIAGNOSTIC',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cyberGreen,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        if (dnsResult != null) ...[
                          SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              final host = currentServer?.address ?? (Uri.tryParse(_configuredApiBaseUrl)?.host ?? '');
                              final report = '--- RAPPORT DIAGNOSTIC ABESSVPN ---\n'
                                  'Date: ${DateTime.now().toIso8601String()}\n'
                                  'Cible: $host:${currentServer?.port ?? 80}\n'
                                  'DNS: $dnsResult\n'
                                  'API: $apiPingResult\n'
                                  'Port: $socketResult\n'
                                  'Token: $tokenResult\n'
                                  'Verdict: $overallVerdict\n'
                                  '------------------------------------';
                              Clipboard.setData(ClipboardData(text: report));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Rapport copié dans le presse-papiers pour le support !')),
                              );
                            },
                            icon: Icon(Icons.copy, color: cyberCyan, size: 16),
                            label: Text('COPIER', style: TextStyle(color: cyberCyan, fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: cyberCyan.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDiagItem(String title, String value, bool? ok) {
    Color color = _text54;
    IconData icon = Icons.help_outline;
    if (ok == true) {
      color = cyberGreen;
      icon = Icons.check_circle;
    } else if (ok == false) {
      color = cyberRed;
      icon = Icons.cancel;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _fieldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              SizedBox(width: 8),
              Text(title, style: TextStyle(color: _textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _isManagedDataPlaneReady() async {
    for (final base in _masterServerUrls) {
      try {
        final response = await http
            .get(Uri.parse('$base/api/v1/ping'))
            .timeout(Duration(seconds: 3));
        if (response.statusCode != 200) continue;

        final payload = jsonDecode(response.body);
        if (payload is Map && payload['dataPlane'] == 'ready') {
          return true;
        }
      } catch (_) {
        // Try the next configured control-plane endpoint.
      }
    }
    return false;
  }

  // Connexion / Déconnexion VPN
  Future<void> _toggleVpn() async {
    if (isConnected || isConnecting) {
      _userWantedConnection = false;
      _reconnectTimer?.cancel();
      setState(() => disconnectAlert = false);
      await _disconnectVpn();
    } else {
      _userWantedConnection = true;
      _reconnectAttempts = 0;
      setState(() => disconnectAlert = false);
      await _connectVpn();
    }
  }

  Future<void> _connectVpn() async {
    if (_isMandatoryUpdateBlocked) {
      _userWantedConnection = false;
      _showToast('Mise à jour obligatoire requise avant toute connexion.');
      _checkForAppUpdate();
      return;
    }

    if (currentServer == null) {
      _showImportModal();
      return;
    }
    final requiredDeviceId = currentServer!.allowedDeviceId?.trim() ?? '';
    if (requiredDeviceId.isNotEmpty && requiredDeviceId != _deviceId) {
      _userWantedConnection = false;
      _addLog('CONNEXION REFUSÉE : ID D’INSTALLATION NON AUTORISÉ');
      _showToast('Cette configuration est liée à une autre installation ABESS.');
      return;
    }

    if (currentServer!.isQuotaExceeded) {
      _showQuotaExceededAlert();
      return;
    }
    if (currentServer!.isExpired) {
      _showExpiredAlert();
      return;
    }

    if (currentServer!.protocol.toLowerCase() == 'ssh') {
      if (mounted) setState(() => isConnecting = false);
      _userWantedConnection = false;
      _showSshConfigDialog(currentServer!);
      return;
    }

    final selectedToken = currentServer!.token;
    final isManagedToken = selectedToken != null &&
        selectedToken != 'CUSTOM-ZERO-TOKEN' &&
        selectedToken != 'RAW-LINK-IMPORT';
    if (isManagedToken && !await _isManagedDataPlaneReady()) {
      if (mounted) setState(() {
        isConnected = false;
        isConnecting = false;
        vpnStatus = 'DISCONNECTED';
      });
      _addLog('CONNEXION REFUSÉE : MOTEUR VLESS DU SERVEUR NON OPÉRATIONNEL');
      _showToast('Le serveur ne confirme pas un moteur VPN opérationnel. Aucune connexion fictive ne sera affichée.');
      return;
    }

    if (mounted) {
      setState(() => isConnecting = true);
    }
    _addLog('ÉTABLISSEMENT DU TUNNEL CHIFFRÉ...');

    try {
      if (isV2rayInitialized) {
        final permission = await v2ray.requestPermission();
        if (!permission) {
          _addLog('PERMISSION VPN SYSTÈME REFUSÉE');
          if (mounted) setState(() => isConnecting = false);
          return;
        }

        final v2rayConfig = _buildXrayClientConfig(currentServer!);
        await v2ray.startV2Ray(
          remark: 'AbessVpn - ${currentServer!.name}',
          config: jsonEncode(v2rayConfig),
          blockedApps: const [],
          bypassSubnets: const [],
          proxyOnly: false,
        );
      } else {
        if (mounted) {
          setState(() {
            isConnected = false;
            isConnecting = false;
            vpnStatus = 'DISCONNECTED';
          });
        }
        _userWantedConnection = false;
        _addLog('CONNEXION REFUSÉE : MOTEUR XRAY NON INITIALISÉ');
        _showToast('Le moteur VPN n’est pas prêt. Vérifiez les logs puis réessayez.');
        return;
      }
      _addLog('COMMANDE DE CONNEXION ENVOYÉE AU MOTEUR XRAY');
    } catch (e) {
      _userWantedConnection = false;
      _reconnectTimer?.cancel();
      _addLog('ÉCHEC DE CONNEXION : $e');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
          vpnStatus = 'DISCONNECTED';
        });
      }
      _stopTelemetry();
      _showToast('Connexion VPN impossible. Consultez les logs.');
    }
  }

  Future<void> _disconnectVpn() async {
    _addLog('FERMETURE DU TUNNEL...');
    try {
      if (isV2rayInitialized) {
        await v2ray.stopV2Ray();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        isConnected = false;
        isConnecting = false;
      });
    }
    _stopTelemetry();
    _saveCurrentServer();
    _addLog('TUNNEL DÉCONNECTÉ');
  }

  Map<String, dynamic> _buildXrayClientConfig(ImportedVpnServer srv) {
    // Les transports HTTP sont protégés par TLS sur TCP/443.
    // RAW/TCP et mKCP/UDP sont réservés à VMess (chiffrement au niveau du protocole).
    // Shadowsocks natif transporte directement TCP et UDP sur le port 10050.
    final protocol = srv.protocol.toLowerCase();
    final transport = srv.transport.toLowerCase();
    const supportedProtocols = {'vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard', 'geny', 'ssh'};
    const supportedTransports = {'ws', 'grpc', 'httpupgrade', 'xhttp', 'raw', 'tcp', 'kcp', 'mkcp', 'native'};

    if (!supportedProtocols.contains(protocol) || !supportedTransports.contains(transport)) {
      throw UnsupportedError(
        'Configuration non prise en charge : ${protocol.toUpperCase()} + ${transport.toUpperCase()}.',
      );
    }
    if (transport == 'native' && protocol != 'shadowsocks' && protocol != 'wireguard' && protocol != 'geny') {
      throw UnsupportedError('Le mode TCP + UDP natif est disponible uniquement avec Shadowsocks ou WireGuard.');
    }
    final effectiveTransport = transport == 'mkcp' ? 'kcp' : transport;
    if ((effectiveTransport == 'raw' || effectiveTransport == 'kcp') && protocol != 'vmess' && srv.token != 'RAW-LINK-IMPORT') {
      throw UnsupportedError('RAW et mKCP/UDP sont réservés à VMess sur le serveur ABESS.');
    }
    if (protocol == 'trojan' && !srv.tls) {
      throw UnsupportedError('Trojan sur un serveur public nécessite TLS.');
    }

    final Map<String, dynamic> outboundSettings;
    switch (protocol) {
      case 'vless':
        outboundSettings = {
          'vnext': [
            {
              'address': srv.address,
              'port': srv.port,
              'users': [
                {'id': srv.uuid, 'encryption': 'none', 'level': 0}
              ]
            }
          ]
        };
        break;
      case 'vmess':
        outboundSettings = {
          'vnext': [
            {
              'address': srv.address,
              'port': srv.port,
              'users': [
                {'id': srv.uuid, 'alterId': 0, 'security': 'auto', 'level': 0}
              ]
            }
          ]
        };
        break;
      case 'trojan':
        outboundSettings = {
          'servers': [
            {
              'address': srv.address,
              'port': srv.port,
              'password': srv.uuid,
              'level': 0
            }
          ]
        };
        break;
      case 'shadowsocks':
        outboundSettings = {
          'servers': [
            {
              'address': srv.address,
              'port': srv.port,
              'method': srv.method.isNotEmpty ? srv.method : 'aes-128-gcm',
              'password': srv.uuid
            }
          ]
        };
        break;
      case 'wireguard':
      case 'geny':
        outboundSettings = {
          'secretKey': srv.uuid,
          'address': [srv.method.isNotEmpty && srv.method.contains('/') ? srv.method : '10.231.0.2/32'],
          'peers': [
            {
              'publicKey': srv.wsHost.isNotEmpty ? srv.wsHost : (srv.sni.isNotEmpty ? srv.sni : '+Qu+gVMRhaR0hL3ePZwd+l+L/NQf8jOrf7QZLGJCUCU='),
              'endpoint': '${srv.address}:${srv.port}',
              'allowedIPs': ['0.0.0.0/0'],
              'keepAlive': 25
            }
          ],
          'mtu': 1280
        };
        break;
      case 'ssh':
        outboundSettings = {
          'servers': [
            {
              'address': srv.address,
              'port': srv.port,
              'method': 'aes-128-gcm',
              'password': srv.uuid
            }
          ]
        };
        break;
      default:
        throw UnsupportedError('Protocole non pris en charge.');
    }

    final Map<String, dynamic>? streamSettings;
    if (transport == 'native' || protocol == 'wireguard' || protocol == 'geny') {
      streamSettings = null;
    } else {
      final Map<String, dynamic> transportSettings;
      switch (effectiveTransport) {
        case 'ws':
          transportSettings = {
            'network': 'ws',
            'wsSettings': {
              'path': srv.path,
              'headers': {'Host': srv.wsHost.isNotEmpty ? srv.wsHost : srv.address}
            }
          };
          break;
        case 'grpc':
          transportSettings = {
            'network': 'grpc',
            'grpcSettings': {
              'serviceName': srv.path.replaceFirst(RegExp(r'^/+'), ''),
              'authority': srv.wsHost.isNotEmpty ? srv.wsHost : srv.address,
              'multiMode': false
            }
          };
          break;
        case 'httpupgrade':
          transportSettings = {
            'network': 'httpupgrade',
            'httpupgradeSettings': {'path': srv.path, 'host': srv.wsHost.isNotEmpty ? srv.wsHost : srv.address}
          };
          break;
        case 'xhttp':
          transportSettings = {
            'network': 'xhttp',
            'xhttpSettings': {
              'path': srv.path,
              'host': srv.wsHost.isNotEmpty ? srv.wsHost : srv.address,
              'mode': 'auto'
            }
          };
          break;
        case 'tcp':
          transportSettings = {
            'network': 'tcp',
            'tcpSettings': {'header': {'type': 'none'}}
          };
          break;
        case 'raw':
          transportSettings = {
            'network': 'raw',
            'rawSettings': {'header': {'type': 'none'}}
          };
          break;
        case 'kcp':
          transportSettings = {
            'network': 'kcp',
            'kcpSettings': {
              'mtu': 1350,
              'tti': 20,
              'uplinkCapacity': 5,
              'downlinkCapacity': 20,
              'congestion': false,
              'readBufferSize': 2,
              'writeBufferSize': 2
            }
          };
          break;
        default:
          throw UnsupportedError('Transport non pris en charge.');
      }

      streamSettings = {
        ...transportSettings,
        'security': srv.tls ? 'tls' : 'none',
        if (srv.tls)
          'tlsSettings': {
            'allowInsecure': false,
            'serverName': srv.sni.isNotEmpty ? srv.sni : srv.address
          }
      };
    }

    final Map<String, dynamic> proxyOutbound = {
      'tag': 'proxy',
      'protocol': protocol,
      'settings': outboundSettings
    };
    if (streamSettings != null) {
      proxyOutbound['streamSettings'] = streamSettings;
    }
    if (_isMuxEnabled && !{'native', 'grpc', 'kcp'}.contains(effectiveTransport) && protocol != 'wireguard' && protocol != 'geny') {
      // XUDP transporte les paquets UDP dans le tunnel quand le protocole le permet.
      // Xray recommande de ne pas activer MUX pour gRPC/HTTP2; mKCP possède déjà son transport UDP.
      proxyOutbound['mux'] = {
        'enabled': true,
        'concurrency': 8,
        'xudpConcurrency': 8,
        'xudpProxyUDP443': 'allow'
      };
    }

    return {
      'log': {'loglevel': 'warning'},
      'dns': {
        'servers': _isAntiAdDnsEnabled
            ? [
                'https://dns.adguard-dns.com/dns-query',
                '1.1.1.1',
                '8.8.8.8'
              ]
            : ['1.1.1.1', '8.8.8.8']
      },
      'inbounds': [
        {
          'tag': 'socks-in',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true}
        }
      ],
      'outbounds': [
        proxyOutbound,
        {'tag': 'direct', 'protocol': 'freedom', 'settings': {}}
      ]
    };
  }


  void _showDeviceLimitDialog(String token, String errorMsg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cyberCardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cyberRed, width: 1.2),
        ),
        title: Row(
          children: [
            Icon(Icons.devices, color: cyberRed, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'LIMITE D\'APPAREILS ATTEINTE',
                style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMsg,
              style: TextStyle(color: _text70, fontSize: 12),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _fieldBackgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cyberCyan.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("VOTRE IDENTIFIANT APPAREIL (HWID) :", style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _deviceId,
                          style: TextStyle(color: _textPrimary, fontSize: 11, fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _deviceId));
                          _showToast("Identifiant appareil copié !");
                        },
                        icon: Icon(Icons.copy, color: cyberGreen, size: 16),
                        tooltip: "Copier mon ID",
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Si vous avez changé de téléphone, demandez à votre revendeur ou au support de réinitialiser vos appareils.",
              style: TextStyle(color: _text54, fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('FERMER', style: TextStyle(color: _text60)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              final msg = Uri.encodeComponent("Bonjour, mon token $token a atteint sa limite d\'appareils suite à un changement de téléphone. Mon HWID est: $_deviceId. Pourriez-vous réinitialiser mes appareils ?");
              _openUrlSafe("https://wa.me/237695140419?text=$msg");
            },
            icon: Icon(Icons.chat, color: Colors.black, size: 14),
            label: Text('WHATSAPP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_telegramSupportUrl);
            },
            icon: Icon(Icons.send, color: Colors.black, size: 14),
            label: Text('TELEGRAM', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
            style: ElevatedButton.styleFrom(backgroundColor: cyberCyan),
          ),
        ],
      ),
    );
  }

    // 1. IMPORTATION PAR CLÉ TOKEN
  Future<void> _importServerByToken(String tokenCode, {bool silent = false}) async {
    var cleanToken = tokenCode.trim();
    if (cleanToken.toUpperCase().startsWith('NY-')) {
      cleanToken = 'GE' + cleanToken;
    }
    if (cleanToken.isEmpty) {
      if (!silent) _addLog('ERREUR: VEUILLEZ SAISIR UN TOKEN');
      return;
    }
    if (!silent) _addLog('VALIDATION DU CODE D\'ACCÈS SUR LE SERVEUR...');

    for (final baseUrl in _masterServerUrls) {
      try {
        final res = await http.post(
          Uri.parse('$baseUrl/api/v1/auth/token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': cleanToken,
            'deviceId': _deviceId,
            'model': 'Android Device',
          }),
        ).timeout(Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['valid'] == true) {
            final srvConf = data['serverConfig'] ?? {};
            final isSsh = (data['protocol']?.toString().toUpperCase() == 'SSH') ||
                (srvConf['protocol']?.toString().toLowerCase() == 'ssh') ||
                (data['sshConfig'] != null) ||
                (data['configs'] is List && (data['configs'] as List).isNotEmpty && data['configs'][0]['type'] == 'SSH');

            Map<String, dynamic>? sshConfig;
            if (data['sshConfig'] is Map) {
              sshConfig = Map<String, dynamic>.from(data['sshConfig']);
            } else if (data['configs'] is List && (data['configs'] as List).isNotEmpty && data['configs'][0]['sshConfig'] is Map) {
              sshConfig = Map<String, dynamic>.from(data['configs'][0]['sshConfig']);
            }

            final newServer = ImportedVpnServer(
              name: (isSsh && sshConfig != null && (sshConfig['remarks'] ?? '').toString().isNotEmpty)
                  ? sshConfig['remarks'].toString()
                  : (data['plan'] ?? 'ABESS VIP MASTER'),
              address: isSsh && sshConfig != null
                  ? (sshConfig['sshHost']?.toString() ?? srvConf['address']?.toString() ?? '')
                  : (srvConf['address']?.toString() ?? ''),
              port: isSsh && sshConfig != null
                  ? (int.tryParse(sshConfig['sshPort']?.toString() ?? '') ?? 80)
                  : (srvConf['port'] ?? 443),
              path: srvConf['path'] ?? '/@abess237',
              wsHost: (srvConf['host'] ?? srvConf['wsHost'] ?? (isSsh ? 'm.batch.com' : '')).toString(),
              sni: srvConf['sni']?.toString() ?? (srvConf['address']?.toString() ?? ''),
              uuid: isSsh && sshConfig != null
                  ? '${sshConfig['sshUsername'] ?? ''}:${sshConfig['sshPassword'] ?? ''}'
                  : (srvConf['uuid']?.toString() ?? ''),
              protocol: isSsh ? 'ssh' : ((srvConf['protocol'] as String?) ?? 'vless'),
              transport: (srvConf['transport'] as String?) ?? 'ws',
              allowedDeviceId: srvConf['allowedDeviceId']?.toString(),
              tls: isSsh ? false : ((srvConf['security']?.toString().toLowerCase() ?? 'tls') != 'none'),
              method: isSsh && sshConfig != null
                  ? (sshConfig['payload']?.toString() ?? '')
                  : ((srvConf['method'] as String?) ?? 'aes-128-gcm'),
              bandwidthGb: (data['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
              bandwidthUsedGb: (data['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
              expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(Duration(days: 30)),
              token: cleanToken,
              deviceLimit: data['deviceLimit'] ?? 1,
            );
            const tlsWebTransports = {'ws', 'grpc', 'httpupgrade', 'xhttp'};
            if (newServer.tls &&
                tlsWebTransports.contains(newServer.transport.toLowerCase()) &&
                newServer.sni.trim().isEmpty) {
              _addLog('ALERTE TLS : le profil VPN ne contient pas de SNI. Vérifiez le nom couvert par le certificat du serveur VPN.');
            } else if (newServer.tls && tlsWebTransports.contains(newServer.transport.toLowerCase())) {
              _addLog('TLS : SNI VPN configuré indépendamment du domaine API.');
            }
            if (isSsh) {
              _addLog('PROFIL SSH-PAYLOAD IMPORTÉ : ${newServer.name} (${newServer.address}:${newServer.port})');
            } else {
              _addLog('PROFIL IMPORTÉ : ${newServer.address}:${newServer.port} • ${newServer.protocol.toUpperCase()}/${newServer.transport.toUpperCase()} • Host HTTP : ${newServer.wsHost.isEmpty ? '(destination)' : newServer.wsHost} • SNI : ${newServer.sni}');
            }
            await _storeAndSelectServer(newServer);
            _addLog('SERVEUR MAÎTRE VALIDÉ (${newServer.bandwidthGb} Go • Expiration: ${_formatRemaining(newServer.expiresAt)})');
            return;
          }
        } else if (res.statusCode == 403) {
          final data = jsonDecode(res.body);
          _addLog('REFUS SERVEUR: ${data['error']}');
          if (data is Map && data['status'] == 'device_limit_exceeded') {
            _showDeviceLimitDialog(cleanToken, data['error']?.toString() ?? 'Limite d\'appareils atteinte.');
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${data['error']}')));
          }
          return;
        } else if (res.statusCode == 429) {
          final data = jsonDecode(res.body);
          final message = data['error']?.toString() ?? 'Trop de requêtes. Veuillez patienter avant de réessayer.';
          _addLog('LIMITE DE REQUÊTES : $message');
          if (mounted && !silent) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.orange));
          }
          return;
        } else if (res.statusCode == 503) {
          final data = jsonDecode(res.body);
          final message = data['error']?.toString() ?? 'Configuration serveur indisponible.';
          _addLog('CONFIGURATION VPN REFUSÉE : $message');
          if (mounted && !silent) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          }
          return;
        }
      } catch (_) {}
    }

    if (!silent) {
      _addLog('SERVEUR EN LIGNE INACCESSIBLE OU TOKEN INVALIDE');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Token non reconnu sur le serveur maître.')),
        );
      }
    }
  }

  // 2. RÉCLAMATION DU TEST GRATUIT 1 GO / 24H (ANTI-FRAUDE PAR TÉLÉPHONE)
  Future<void> _claimFreeTrial() async {
    _addLog('RÉCLAMATION DU TEST 1 GO (SÉCURISÉ)...');
    for (final base in _masterServerUrls) {
      try {
        final res = await http.post(
          Uri.parse('$base/api/v1/client/claim-free-trial'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'deviceId': _deviceId,
            'model': 'Smartphone Android',
            'os': 'Android 14/15',
          }),
        ).timeout(Duration(seconds: 4));

        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['ok'] == true) {
          final srvConf = data['serverConfig'] ?? {};
          final newServer = ImportedVpnServer(
            name: data['plan'] ?? 'PASS 1 GO GRATUIT',
            address: srvConf['address']?.toString() ?? '',
            port: srvConf['port'] ?? 443,
            path: srvConf['path'] ?? '/@abess237',
            wsHost: (srvConf['host'] ?? srvConf['wsHost'] ?? '').toString(),
            sni: srvConf['sni']?.toString() ?? (srvConf['address']?.toString() ?? ''),
            uuid: srvConf['uuid']?.toString() ?? '',
            bandwidthGb: 1.0,
            bandwidthUsedGb: 0.0,
            expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(Duration(days: 1)),
            token: data['token'],
            encryptedLink: data['encryptedLink'],
            deviceLimit: 1,
          );
          await _storeAndSelectServer(newServer);
          _addLog('ESSAI 1 GO ACTIVÉ AVEC SUCCÈS');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Pass 1 Go / 24h activé avec succès !')),
            );
          }
          return;
        } else {
          _addLog('NOTE ANTI-FRAUDE: ${data['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${data['error']}')),
            );
          }
          return;
        }
      } catch (_) {}
    }
  }

  // 3. IMPORTATION PAR LIEN OU FICHIER CRYPTÉ
  Future<void> _importServerByEncryptedLink(String link) async {
    _addLog('VALIDATION DU LIEN CHIFFRÉ SUR LE SERVEUR...');
    final clean = link.trim();
    if (clean.isEmpty) return;
    if (!clean.startsWith('abess://')) {
      _showToast('Lien ABESS invalide');
      return;
    }
    if (_deviceId.isEmpty) await _initDeviceId();
    if (clean.startsWith('abess://profile.')) {
      _parseUniversalRawLink(clean);
      return;
    }

    for (final base in _masterServerUrls) {
      try {
        final response = await http.post(
          Uri.parse('$base/api/v1/auth/import-link'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'link': clean,
            'deviceId': _deviceId,
            'model': 'Android Device',
          }),
        ).timeout(Duration(seconds: 5));

        final dynamic decoded = jsonDecode(response.body);
        if (response.statusCode == 200 && decoded is Map && decoded['valid'] == true) {
          final data = Map<String, dynamic>.from(decoded);
          final dynamic rawConfig = data['serverConfig'];
          final srvConf = rawConfig is Map
              ? Map<String, dynamic>.from(rawConfig)
              : <String, dynamic>{};

          final newServer = ImportedVpnServer(
            name: data['plan']?.toString() ?? 'ABESS VPN',
            address: srvConf['address']?.toString() ?? '',
            port: (srvConf['port'] as num?)?.toInt() ?? 443,
            path: srvConf['path']?.toString() ?? '/@abess237',
            wsHost: (srvConf['host'] ?? srvConf['wsHost'] ?? '').toString(),
            sni: srvConf['sni']?.toString() ?? '',
            uuid: srvConf['uuid']?.toString() ?? '',
            protocol: srvConf['protocol']?.toString() ?? 'vless',
            transport: srvConf['transport']?.toString() ?? 'ws',
            allowedDeviceId: srvConf['allowedDeviceId']?.toString(),
            tls: (srvConf['security']?.toString().toLowerCase() ?? 'tls') != 'none',
            method: srvConf['method']?.toString() ?? 'aes-128-gcm',
            bandwidthGb: (data['bandwidthGb'] as num?)?.toDouble() ?? 0.0,
            bandwidthUsedGb: (data['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
            expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? '')
                ?? DateTime.now(),
            token: data['token']?.toString(),
            encryptedLink: clean,
            deviceLimit: (data['deviceLimit'] as num?)?.toInt() ?? 1,
          );

          if (newServer.address.isEmpty || newServer.uuid.isEmpty || newServer.token == null) {
            _addLog('REFUS SERVEUR : CONFIGURATION INCOMPLÈTE');
            _showToast('Le serveur a renvoyé une configuration incomplète.');
            return;
          }

          await _storeAndSelectServer(newServer);
          _addLog('LIEN ABESS VALIDÉ • ${newServer.bandwidthGb} Go • ${_formatRemaining(newServer.expiresAt)}');
          _showToast('Licence validée et configuration importée.');
          return;
        }

        if (response.statusCode == 400 ||
            response.statusCode == 401 ||
            response.statusCode == 403) {
          final message = decoded is Map
              ? decoded['error']?.toString() ?? 'Lien invalide ou licence refusée.'
              : 'Lien invalide ou licence refusée.';
          _addLog('IMPORT REFUSÉ : $message');
          _showToast(message);
          return;
        }
      } catch (_) {
        // Try the next configured control-plane endpoint.
      }
    }

    _addLog('ÉCHEC : IMPOSSIBLE DE VALIDER LE LIEN ABESS');
    _showToast('Serveur indisponible ou lien chiffré invalide.');
  }

  // 4. CRÉATION DE CONFIGURATION / TOKEN (ENREGISTRÉ SUR LE SERVEUR)
  Future<void> _submitCreateToken(StateSetter setModalState) async {
    final customCode = _createTokenCodeCtrl.text.trim();
    final plan = _createPlanNameCtrl.text.trim().isEmpty ? 'VIP Config' : _createPlanNameCtrl.text.trim();

    setModalState(() => _isCreatingToken = true);
    _addLog('CRÉATION TOKEN ($customCode • ${_createQuotaGb.toInt()} Go • $_createExpiryDays jours)...');

    bool success = false;
    for (final base in _masterServerUrls) {
      try {
        final res = await http.post(
          Uri.parse('$base/api/v1/client/create-token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': customCode.isNotEmpty ? customCode : null,
            'bandwidthGb': _createQuotaGb,
            'days': _createExpiryDays,
            'plan': plan,
            'deviceLimit': _createDeviceLimit,
            'resellerName': 'Client Application',
          }),
        ).timeout(Duration(seconds: 5));

        if (res.statusCode == 403) {
          final data = jsonDecode(res.body);
          final message = data['error']?.toString()
              ?? 'La création de tokens est réservée au panneau administrateur.';
          setModalState(() => _isCreatingToken = false);
          if (!mounted) return;
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: cyberCardBg,
              title: Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: cyberYellow),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CRÉATION VIA LE PANEL',
                      style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(message, style: TextStyle(color: _text70, fontSize: 12)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('FERMER', style: TextStyle(color: _text60)),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openUrlSafe(base);
                  },
                  icon: Icon(Icons.open_in_new, size: 14, color: Colors.black),
                  label: Text('OUVRIR LE PANEL', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                ),
              ],
            ),
          );
          success = true;
          break;
        }

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['ok'] == true) {
            final tokenGenerated = data['token'];
            final srvConf = data['serverConfig'] ?? {};

            setModalState(() => _isCreatingToken = false);
            if (!mounted) return;
            Navigator.pop(context);

            _addLog('CONFIGURATION ENREGISTRÉE SUR LE SERVEUR');

            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: cyberCardBg,
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: cyberGreen),
                    SizedBox(width: 8),
                    Text('CONFIG CRÉÉE !', style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Code Token : $tokenGenerated', style: TextStyle(color: cyberGreen, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('Quota : ${_createQuotaGb.toInt()} Go', style: TextStyle(color: _text70)),
                    Text('Durée : $_createExpiryDays jours', style: TextStyle(color: _text70)),
                    Text('Limite Appareils : $_createDeviceLimit', style: TextStyle(color: _text70)),
                    SizedBox(height: 12),
                    Text('Cette configuration a été enregistrée directement dans la base du serveur maître.', style: TextStyle(color: _text38, fontSize: 11)),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tokenGenerated));
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Token copié dans le presse-papier !')));
                    },
                    icon: Icon(Icons.copy, size: 14, color: cyberCyan),
                    label: Text('COPIER TOKEN', style: TextStyle(color: cyberCyan, fontSize: 11)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final newServer = ImportedVpnServer(
                        name: plan,
                        address: srvConf['address']?.toString() ?? '',
                        port: (srvConf['port'] as num?)?.toInt() ?? 443,
                        path: srvConf['path']?.toString() ?? '/@abess237',
                        sni: srvConf['sni']?.toString() ?? (srvConf['address']?.toString() ?? ''),
                        uuid: srvConf['uuid']?.toString() ?? '',
                        protocol: srvConf['protocol']?.toString() ?? 'vless',
                        transport: srvConf['transport']?.toString() ?? 'ws',
            allowedDeviceId: srvConf['allowedDeviceId']?.toString(),
                        tls: (srvConf['security']?.toString().toLowerCase() ?? 'tls') != 'none',
                        method: srvConf['method']?.toString() ?? 'aes-128-gcm',
                        wsHost: (srvConf['host'] ?? srvConf['wsHost'])?.toString() ?? '',
                        bandwidthGb: _createQuotaGb,
                        bandwidthUsedGb: 0.0,
                        expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(Duration(days: _createExpiryDays)),
                        token: tokenGenerated,
                        encryptedLink: data['encryptedLink'],
                        deviceLimit: _createDeviceLimit,
                      );
                      unawaited(_storeAndSelectServer(newServer));
                      _addLog('SERVEUR ACTIVÉ DIRECTEMENT DANS L\'APP');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                    child: Text('APPLIQUER COMME MON SERVEUR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            );
            success = true;
            break;
          }
        }
      } catch (_) {}
    }

    if (!success) {
      setModalState(() => _isCreatingToken = false);
      _addLog('ERREUR DE COMMUNICATION SERVEUR');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de joindre le serveur maître.')),
        );
      }
    }
  }

  // Formatters
  String _formatTimer(int totalSecs) {
    final h = (totalSecs ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatRemaining(DateTime exp) {
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return 'Expiré';
    if (diff.inDays > 0) return '${diff.inDays}j ${diff.inHours % 24}h restants';
    return '${diff.inHours}h ${diff.inMinutes % 60}m restants';
  }

  // Modale d'Importation
  void _showImportModal() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: cyberCardBg,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('IMPORTER CONFIG', style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: _text54)),
              ],
            ),
            SizedBox(height: 12),
            Text('TOKEN', style: TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            TextField(
              controller: _tokenInputCtrl,
              style: TextStyle(color: cyberGreen, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Token',
                hintStyle: TextStyle(color: _text30),
                filled: true,
                fillColor: _fieldFillColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _text24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cyberGreen)),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _importServerByToken(_tokenInputCtrl.text);
              },
              icon: Icon(Icons.key, color: Colors.black),
              label: Text('ACTIVER PAR CLÉ TOKEN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cyberGreen,
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: 18),
            Divider(color: _text12),
            SizedBox(height: 10),
            Text('ABESS:// / .ABESS', style: TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            TextField(
              controller: _fileInputCtrl,
              maxLines: 2,
              style: TextStyle(color: cyberCyan, fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'abess://',
                hintStyle: TextStyle(color: _text30),
                filled: true,
                fillColor: _fieldFillColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _text24)),
              ),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(_pickAndImportAbessFile());
                    },
                    icon: Icon(Icons.folder_open, size: 17),
                    label: Text('.ABESS'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _importServerByEncryptedLink(_fileInputCtrl.text);
                    },
                    icon: Icon(Icons.link, color: Colors.black),
                    label: Text('IMPORTER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cyberCyan,
                      minimumSize: const Size.fromHeight(45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _claimFreeTrial();
              },
              icon: Icon(Icons.bolt, color: cyberYellow),
              label: Text('ESSAI 1 GO / 24H', style: TextStyle(color: cyberYellow, fontSize: 11)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cyberYellow),
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modale de Création de Configuration & Token (Fixer Gigas & Expiration)
  void _showCreateConfigModal() {
    if (!mounted) return;
    _createTokenCodeCtrl.text = generateUnifiedToken();
    showModalBottomSheet(
      context: context,
      backgroundColor: cyberCardBg,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('CRÉER CONFIG / TOKEN (GIGAS & EXPIRATION)', style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: _text54)),
                  ],
                ),
                SizedBox(height: 10),
                Text('1. NOM DU FORFAIT / CLIENT', style: TextStyle(color: _text70, fontSize: 10)),
                SizedBox(height: 4),
                TextField(
                  controller: _createPlanNameCtrl,
                  style: TextStyle(color: _textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _fieldFillColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                SizedBox(height: 10),
                Text('2. CODE TOKEN (UNIFIÉ ABESS-XXXXXXXXXXX)', style: TextStyle(color: _text70, fontSize: 10)),
                SizedBox(height: 4),
                TextField(
                  controller: _createTokenCodeCtrl,
                  style: TextStyle(color: cyberGreen, fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _fieldFillColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh, color: cyberGreen, size: 18),
                      tooltip: 'Générer un nouveau code token',
                      onPressed: () {
                        setMState(() {
                          _createTokenCodeCtrl.text = generateUnifiedToken();
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('3. NOMBRE DE GIGAS (QUOTA)', style: TextStyle(color: _text70, fontSize: 10)),
                    Text('${_createQuotaGb.toInt()} Go', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 200.0].map((gb) {
                    final sel = _createQuotaGb == gb;
                    return ChoiceChip(
                      label: Text('${gb.toInt()} Go', style: TextStyle(color: sel ? Colors.black : _textPrimary, fontSize: 10)),
                      selected: sel,
                      selectedColor: cyberGreen,
                      backgroundColor: _softSurfaceFill,
                      onSelected: (val) => setMState(() => _createQuotaGb = gb),
                    );
                  }).toList(),
                ),
                Slider(
                  value: _createQuotaGb,
                  min: 1,
                  max: 200,
                  divisions: 199,
                  activeColor: cyberGreen,
                  onChanged: (val) => setMState(() => _createQuotaGb = val),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('4. DATE D\'EXPIRATION (DURÉE)', style: TextStyle(color: _text70, fontSize: 10)),
                    Text('$_createExpiryDays Jours', style: TextStyle(color: cyberCyan, fontWeight: FontWeight.bold)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [1, 7, 15, 30, 90, 180, 365].map((d) {
                    final sel = _createExpiryDays == d;
                    return ChoiceChip(
                      label: Text(d == 1 ? '24h' : '$d jours', style: TextStyle(color: sel ? Colors.black : _textPrimary, fontSize: 10)),
                      selected: sel,
                      selectedColor: cyberCyan,
                      backgroundColor: _softSurfaceFill,
                      onSelected: (val) => setMState(() => _createExpiryDays = d),
                    );
                  }).toList(),
                ),
                Slider(
                  value: _createExpiryDays.toDouble(),
                  min: 1,
                  max: 365,
                  divisions: 364,
                  activeColor: cyberCyan,
                  onChanged: (val) => setMState(() => _createExpiryDays = val.toInt()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('5. LIMITE D\'APPAREILS AUTORISÉS', style: TextStyle(color: _text70, fontSize: 10)),
                    Text('$_createDeviceLimit Appareil(s)', style: TextStyle(color: cyberYellow, fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: [1, 2, 3, 5].map((lim) {
                    final sel = _createDeviceLimit == lim;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                      child: ChoiceChip(
                        label: Text('$lim Téléphone(s)', style: TextStyle(color: sel ? Colors.black : _textPrimary, fontSize: 10)),
                        selected: sel,
                        selectedColor: cyberYellow,
                        backgroundColor: _softSurfaceFill,
                        onSelected: (val) => setMState(() => _createDeviceLimit = lim),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isCreatingToken ? null : () => _submitCreateToken(setMState),
                  icon: _isCreatingToken
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Icon(Icons.cloud_upload, color: Colors.black),
                  label: Text(
                    _isCreatingToken ? 'ENREGISTREMENT SERVEUR...' : 'GÉNÉRER & ENREGISTRER SUR LE SERVEUR',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cyberGreen,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final srv = currentServer;
    final usedGb = srv?.bandwidthUsedGb ?? 0.0;
    final totalGb = srv?.bandwidthGb ?? 0.0;
    final usedPercent = srv?.usedPercentage ?? 0.0;
    final remainingDays = srv != null ? _formatRemaining(srv.expiresAt) : "Non défini";

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cyberGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cyberGreen.withOpacity(0.4)),
              ),
              child: const Icon(Icons.shield, color: cyberGreen, size: 20),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _currentNavIndex == 0
                    ? "AbessVpn"
                    : _currentNavIndex == 1
                        ? "Serveurs & Tokens"
                        : "Outils & Diagnostic",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _fetchAndShowAnnouncements(userInitiated: true),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.campaign_rounded, color: cyberYellow),
                if (_hasUnreadAnnouncements)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: cyberCardBg, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: "📢 Annonces du Réseau",
          ),
          IconButton(
            onPressed: () async {
              final next = !abessDarkMode.value;
              abessDarkMode.value = next;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('abess_dark_mode', next);
            },
            icon: Icon(abessDarkMode.value ? Icons.light_mode : Icons.dark_mode, color: cyberYellow),
            tooltip: abessDarkMode.value ? 'Mode clair' : 'Mode sombre',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: cyberCyan),
            tooltip: "Menu Options Rapides",
            color: cyberCardBg,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cyberCyan.withOpacity(0.4), width: 1),
            ),
            onSelected: (value) {
              switch (value) {
                case 'speedtest':
                  _showSpeedTestModal();
                  break;
                case 'telegram':
                  _openUrlSafe(_telegramChannelUrl);
                  break;
                case 'whatsapp':
                  _openUrlSafe(_whatsappSupportUrl);
                  break;
                case 'update':
                  _checkForAppUpdate(showUpToDate: true);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'speedtest',
                child: Row(
                  children: [
                    const Icon(Icons.speed, color: cyberCyan, size: 18),
                    const SizedBox(width: 10),
                    Text('Speed Test Cyber', style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'telegram',
                child: Row(
                  children: [
                    const Icon(Icons.send_rounded, color: cyberCyan, size: 18),
                    const SizedBox(width: 10),
                    Text('Canal Telegram', style: TextStyle(color: _textPrimary, fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'whatsapp',
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: cyberGreen, size: 18),
                    const SizedBox(width: 10),
                    Text('Support WhatsApp', style: TextStyle(color: _textPrimary, fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'update',
                child: Row(
                  children: [
                    const Icon(Icons.system_update_alt, color: cyberYellow, size: 18),
                    const SizedBox(width: 10),
                    Text('Vérifier Mises à jour', style: TextStyle(color: _textPrimary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, .025), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildCurrentTab(srv, usedGb, totalGb, usedPercent, remainingDays),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cyberCardBg,
          border: Border(top: BorderSide(color: cyberGreen.withOpacity(0.2))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentNavIndex,
          onDestinationSelected: (index) {
            if (index == _currentNavIndex) return;
            HapticFeedback.selectionClick();
            setState(() => _currentNavIndex = index);
          },
          animationDuration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
          elevation: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield_rounded), label: 'Connexion'),
            NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns_rounded), label: 'Mes accès'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Outils'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab(ImportedVpnServer? srv, double usedGb, double totalGb, double usedPercent, String remainingDays) {
    switch (_currentNavIndex) {
      case 0:
        return KeyedSubtree(
          key: const ValueKey<int>(0),
          child: _buildTab1Connection(srv, usedGb, totalGb, usedPercent, remainingDays),
        );
      case 1:
        return KeyedSubtree(
          key: const ValueKey<int>(1),
          child: _buildTab2ProtocolsAndTokens(srv),
        );
      case 2:
      default:
        return KeyedSubtree(
          key: const ValueKey<int>(2),
          child: _buildTab4ToolsAndStability(srv),
        );
    }
  }

  // ==========================================================================
  // ONGLET 1 : CONNEXION VPN & DASHBOARD PRINCIPAL
  // ==========================================================================
  Widget _buildTab1Connection(ImportedVpnServer? srv, double usedGb, double totalGb, double usedPercent, String remainingDays) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          ConnectionOverview(
            connected: isConnected,
            connecting: isConnecting,
            serverName: srv?.name,
            onChooseServer: () => setState(() => _currentNavIndex = 1),
          ),
          const SizedBox(height: 24),
          if (srv != null && (srv.isExpired || srv.isQuotaExceeded || srv.usedPercentage >= 80)) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed.withOpacity(0.12) : cyberYellow.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed : cyberYellow),
              ),
              child: Row(
                children: [
                  Icon(
                    (srv.isExpired || srv.isQuotaExceeded) ? Icons.error_outline : Icons.warning_amber_rounded,
                    color: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed : cyberYellow,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (srv.isExpired || srv.isQuotaExceeded)
                          ? "FORFAIT EXPIRÉ OU QUOTA ÉPUISÉ"
                          : "ATTENTION : Plus que ${srv.remainingGb.toStringAsFixed(1)} Go restants",
                      style: TextStyle(
                        color: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed : cyberYellow,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _openUrlSafe(_whatsappSupportUrl),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed : cyberYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text("RECHARGER", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          if (srv != null && srv.protocol.toLowerCase() == 'ssh') ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cyberYellow.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cyberYellow.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal_rounded, color: cyberYellow, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "PROFIL SSH-PAYLOAD (DROPBEAR)",
                          style: TextStyle(color: cyberYellow, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                      ),
                      IconButton(
                        tooltip: "Copier la config JSON SSH",
                        onPressed: () => _copySshJsonConfig(srv),
                        icon: const Icon(Icons.copy, color: cyberYellow, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Serveur: ${srv.address}:${srv.port}  •  Utilisateur: ${srv.uuid.split(':').first}",
                    style: TextStyle(color: _textPrimary, fontSize: 10, fontFamily: "monospace"),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Payload: ${srv.method.replaceAll('\r', '').replaceAll('\n', ' ')}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _text60, fontSize: 9, fontFamily: "monospace"),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _copySshJsonConfig(srv),
                      icon: const Icon(Icons.code, size: 14),
                      label: const Text("COPIER CONFIG JSON (PEDDYGIST / SSH)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyberYellow,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ==========================================
          // ANIMATED QUANTUM REACTOR POWER STAGE
          // ==========================================
          LayoutBuilder(
            builder: (context, constraints) {
              final double outerSize = math.min(math.max(constraints.maxWidth * 0.48, 150.0), 195.0);
              final double auraSize = outerSize * 0.86;
              final double coreSize = outerSize * 0.74;

              return Semantics(
                button: true,
                enabled: !isConnecting,
                label: isConnecting ? 'Connexion en cours' : isConnected ? 'Déconnecter le VPN' : 'Connecter le VPN',
                onTap: isConnecting ? null : _toggleVpn,
                child: FocusableActionDetector(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                  },
                  actions: <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                      if (!isConnecting) _toggleVpn();
                      return null;
                    }),
                  },
                  child: GestureDetector(
                onTapDown: (_) => setState(() => _isReactorPressed = true),
                onTapUp: (_) => setState(() => _isReactorPressed = false),
                onTapCancel: () => setState(() => _isReactorPressed = false),
                onTap: isConnecting ? null : _toggleVpn,
                child: AnimatedScale(
                  scale: _isReactorPressed ? 0.94 : 1.0,
                  duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
                  curve: Curves.easeInOut,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulseController, _rotateController]),
                    builder: (ctx, child) {
                      final pulseVal = isConnected ? _pulseController.value : (isConnecting ? _pulseController.value * 0.8 : 0.0);
                      final rotateAngle = _rotateController.value * 2 * math.pi;

                      final Color coreColor = isConnected
                          ? cyberGreen
                          : isConnecting
                              ? cyberYellow
                              : (srv != null ? cyberCyan : _text38);

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer rotating cybernetic orbital ring with 3 glowing satellite nodes
                          Transform.rotate(
                            angle: rotateAngle,
                            child: Container(
                              width: outerSize,
                              height: outerSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: coreColor.withOpacity(isConnected ? 0.45 : (isConnecting ? 0.35 : 0.12)),
                                  width: 1.5,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // Satellite 1 (Top)
                                  Positioned(
                                    top: 0,
                                    left: (outerSize / 2) - 5,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: coreColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: coreColor, blurRadius: 8, spreadRadius: 2),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Satellite 2 (Bottom right)
                                  Positioned(
                                    bottom: outerSize * 0.20,
                                    right: outerSize * 0.08,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: coreColor.withOpacity(0.85),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: coreColor.withOpacity(0.8), blurRadius: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Satellite 3 (Bottom left)
                                  Positioned(
                                    bottom: outerSize * 0.20,
                                    left: outerSize * 0.08,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: coreColor.withOpacity(0.85),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: coreColor.withOpacity(0.8), blurRadius: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Middle pulsing aura ring
                          Container(
                            width: auraSize + (pulseVal * 14),
                            height: auraSize + (pulseVal * 14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.transparent,
                              border: Border.all(
                                color: coreColor.withOpacity(0.25 + (pulseVal * 0.3)),
                                width: 2,
                              ),
                              boxShadow: [
                                if (isConnected || isConnecting)
                                  BoxShadow(
                                    color: coreColor.withOpacity(0.25 + (pulseVal * 0.35)),
                                    blurRadius: 35,
                                    spreadRadius: 4 + (pulseVal * 6),
                                  ),
                              ],
                            ),
                          ),

                          // Inner Power Reactor Core
                          Container(
                            width: coreSize,
                            height: coreSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: isConnected
                                    ? [
                                        Color.lerp(const Color(0xFF065F46), const Color(0xFF047857), pulseVal)!,
                                        const Color(0xFF022C22),
                                      ]
                                    : isConnecting
                                        ? [
                                            Color.lerp(const Color(0xFFB45309), const Color(0xFFD97706), pulseVal)!,
                                            const Color(0xFF451A03),
                                          ]
                                        : [
                                            const Color(0xFF1E293B),
                                            const Color(0xFF090E17),
                                          ],
                                center: Alignment.center,
                                radius: 0.85,
                              ),
                              border: Border.all(
                                color: coreColor,
                                width: 3.2,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isConnecting)
                                    SizedBox(
                                      width: coreSize * 0.28,
                                      height: coreSize * 0.28,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 3.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(cyberYellow),
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.power_settings_new_rounded,
                                      size: coreSize * 0.32,
                                      color: isConnected ? Colors.white : (srv != null ? cyberCyan : _text38),
                                    ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                      child: Text(
                                        isConnecting
                                            ? "NÉGOCIATION..."
                                            : isConnected
                                                ? "CONNECTÉ"
                                                : (srv != null ? "ACTIVER" : "AUCUN ACCÈS"),
                                        style: TextStyle(
                                          color: isConnected ? Colors.white : (srv != null ? _textPrimary : _text54),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isConnected) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: cyberGreen,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          "PROTÉGÉ",
                                          style: TextStyle(
                                            color: cyberGreen,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // HUD Status Banner Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected
                  ? cyberGreen.withOpacity(0.12)
                  : isConnecting
                      ? cyberYellow.withOpacity(0.12)
                      : _fieldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected
                    ? cyberGreen.withOpacity(0.5)
                    : isConnecting
                        ? cyberYellow.withOpacity(0.5)
                        : _text12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? cyberGreen
                        : isConnecting
                            ? cyberYellow
                            : _text38,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (isConnected)
                        const BoxShadow(color: cyberGreen, blurRadius: 6, spreadRadius: 1),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected
                      ? "TUNNEL CHIFFRÉ ACTIF // SÉCURITÉ MAXIMALE"
                      : isConnecting
                          ? "ÉTABLISSEMENT DU TUNNEL SÉCURISÉ..."
                          : "HORS LIGNE // CYBER DÉFENSE EN VEILLE",
                  style: TextStyle(
                    color: isConnected
                        ? cyberGreen
                        : isConnecting
                            ? cyberYellow
                            : _text60,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Duration Timer
          Text(
            _formatTimer(_connectionDurationSeconds),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              fontFamily: "monospace",
            ),
          ),
          const SizedBox(height: 4),

          // Tunnel IP & HWID tags
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("IP VIRTUELLE : ", style: TextStyle(color: _text38, fontSize: 10)),
              Text(isConnected ? _virtualIp : "EN VEILLE", style: const TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Text("• ID : ", style: TextStyle(color: _text38, fontSize: 10)),
              Text(
                _deviceId.length > 10 ? "${_deviceId.substring(0, 10)}..." : _deviceId,
                style: const TextStyle(color: cyberCyan, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (srv != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cyberCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cyberGreen.withOpacity( 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pie_chart, color: cyberGreen, size: 14),
                          SizedBox(width: 4),
                          Text("GIGAS UTILISÉS / QUOTA", style: TextStyle(color: _text70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text(
                        "${usedGb.toStringAsFixed(2)} Go / ${totalGb.toStringAsFixed(1)} Go (${usedPercent.toInt()}%)",
                        style: TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: totalGb > 0 ? (usedPercent / 100.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: _softSurfaceFill,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usedPercent > 85 ? cyberRed : usedPercent > 60 ? cyberYellow : cyberGreen,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Restant: ${(totalGb - usedGb).toStringAsFixed(2)} Go", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text("Expire : $remainingDays", style: TextStyle(color: _text60, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _text10),
                    boxShadow: [
                      BoxShadow(color: cyberCyan.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.arrow_downward, color: cyberCyan, size: 13),
                          const SizedBox(width: 4),
                          Text("DÉBIT DL", style: TextStyle(color: _text54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isConnected ? "${_currentDownloadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Total: ${_totalDownloadMb.toStringAsFixed(1)} Mo",
                          style: TextStyle(color: _text38, fontSize: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _text10),
                    boxShadow: [
                      BoxShadow(color: cyberGreen.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward, color: cyberGreen, size: 13),
                          const SizedBox(width: 4),
                          Text("DÉBIT UL", style: TextStyle(color: _text54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isConnected ? "${_currentUploadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Total: ${_totalUploadMb.toStringAsFixed(1)} Mo",
                          style: TextStyle(color: _text38, fontSize: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _text10),
                    boxShadow: [
                      BoxShadow(color: cyberYellow.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.wifi,
                            color: _currentPingMs <= 0
                                ? _text54
                                : _currentPingMs < 80
                                    ? cyberGreen
                                    : _currentPingMs < 160
                                        ? cyberYellow
                                        : cyberRed,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text("PING MS", style: TextStyle(color: _text54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _currentPingMs > 0 ? '$_currentPingMs ms' : '—',
                          style: TextStyle(
                            color: _currentPingMs <= 0
                                ? _textPrimary
                                : _currentPingMs < 80
                                    ? cyberGreen
                                    : _currentPingMs < 160
                                        ? cyberYellow
                                        : cyberRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _currentPingMs > 0
                              ? (_currentPingMs < 80 ? "Ultra Fluide" : _currentPingMs < 160 ? "Normal" : "Latence")
                              : "Serveur Maître",
                          style: TextStyle(color: _text38, fontSize: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _text10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("MONITEUR BANDE PASSANTE TEMPS RÉEL", style: TextStyle(color: _text54, fontSize: 9, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Icon(Icons.circle, color: cyberCyan, size: 8),
                        SizedBox(width: 4),
                        Text("Download", style: TextStyle(color: _text60, fontSize: 9)),
                        SizedBox(width: 8),
                        Icon(Icons.circle, color: cyberGreen, size: 8),
                        SizedBox(width: 4),
                        Text("Upload", style: TextStyle(color: _text60, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 100,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _speedHistoryDownload,
                          isCurved: true,
                          color: cyberCyan,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: cyberCyan.withOpacity( 0.12)),
                        ),
                        LineChartBarData(
                          spots: _speedHistoryUpload,
                          isCurved: true,
                          color: cyberGreen,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: cyberGreen.withOpacity( 0.08)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ONGLET 2 : SERVEURS & FORFAITS
  // ==========================================================================
  Widget _buildTab2ProtocolsAndTokens(ImportedVpnServer? srv) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSavedProfilesSection(),
          const SizedBox(height: 16),

          // Activation par Clé Token
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberGreen.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key, color: cyberGreen, size: 18),
                    const SizedBox(width: 8),
                    Text("ACTIVATION PAR CLÉ TOKEN", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Saisissez votre code licence officiel pour activer votre accès réseau ultra-rapide.", style: TextStyle(color: _text60, fontSize: 10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tokenInputCtrl,
                        style: const TextStyle(color: cyberGreen, fontFamily: "monospace", fontSize: 12),
                        decoration: InputDecoration(
                          hintText: "EX: ABESS-7B2K9X4M1Q8",
                          hintStyle: TextStyle(color: _text30, fontSize: 11),
                          filled: true,
                          fillColor: _fieldBackgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cyberGreen.withOpacity(0.4))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _text24)),
                          focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: cyberGreen)),
                          suffixIcon: IconButton(
                            tooltip: "Coller depuis le presse-papier",
                            icon: const Icon(Icons.content_paste, color: cyberGreen, size: 18),
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                _tokenInputCtrl.text = data.text!.trim();
                                _showToast("Token collé avec succès !");
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_tokenInputCtrl.text.isNotEmpty) {
                          _importServerByToken(_tokenInputCtrl.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyberGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("VALIDER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _claimFreeTrial,
                  icon: const Icon(Icons.bolt, color: cyberYellow, size: 16),
                  label: const Text("RÉCLAMER MON ESSAI GRATUIT 1 GO / 24H", style: TextStyle(color: cyberYellow, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cyberYellow),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Import Fichier .abess ou Lien
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberCyan.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.file_download_outlined, color: cyberCyan, size: 18),
                    const SizedBox(width: 8),
                    Text("IMPORT CONFIGURATION", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Importez un fichier de configuration .abess ou un lien de profil reçu de votre administrateur.", style: TextStyle(color: _text60, fontSize: 10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickAndImportAbessFile,
                        icon: const Icon(Icons.file_open, size: 16),
                        label: const Text("FICHIER .ABESS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cyberCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showImportLinkDialog,
                        icon: const Icon(Icons.link, size: 16, color: cyberCyan),
                        label: const Text("COLLER LIEN", style: TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: cyberCyan),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ID d'Installation
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _text12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phonelink_lock, color: cyberGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text("ID D’INSTALLATION ABESS", style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5))),
                    IconButton(
                      tooltip: "Copier l’ID d’installation",
                      onPressed: _deviceId.isEmpty ? null : () async {
                        await Clipboard.setData(ClipboardData(text: _deviceId));
                        _showToast("ID d’installation copié");
                      },
                      icon: const Icon(Icons.copy, color: cyberCyan, size: 16),
                    ),
                  ],
                ),
                SelectableText(
                  _deviceId.isEmpty ? "Initialisation…" : _deviceId,
                  style: TextStyle(color: _textPrimary, fontFamily: "monospace", fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showImportLinkDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cyberCardBg,
        title: Text("Importer un lien", style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: _textPrimary, fontSize: 12, fontFamily: "monospace"),
          decoration: InputDecoration(
            hintText: "abess://..., JSON SSH-Payload, vless://...",
            hintStyle: TextStyle(color: _text30, fontSize: 11),
            filled: true,
            fillColor: _fieldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("ANNULER", style: TextStyle(color: _text60)),
          ),
          ElevatedButton(
            onPressed: () {
              final link = ctrl.text.trim();
              Navigator.pop(ctx);
              if (link.isNotEmpty) {
                if (link.startsWith('abess://')) {
                  _importServerByEncryptedLink(link);
                } else {
                  _parseUniversalRawLink(link);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberCyan, foregroundColor: Colors.black),
            child: const Text("IMPORTER", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }



  Widget _buildTab4ToolsAndStability(ImportedVpnServer? srv) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberCyan.withOpacity( 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.speed, color: cyberCyan, size: 18),
                        SizedBox(width: 8),
                        Text("SPEED TEST CYBER INTÉGRÉ", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _showSpeedTestModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyberCyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text("TESTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text("Mesure en direct la latence (ping) et le débit montant/descendant vers les serveurs maîtres.", style: TextStyle(color: _text60, fontSize: 10)),
              ],
            ),
          ),
          SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberGreen.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.health_and_safety_outlined, color: cyberGreen, size: 18),
                        SizedBox(width: 8),
                        Text("DIAGNOSTIC TECHNIQUE 1-CLIC", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _showDiagnosticModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyberGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text("DIAGNOSTIQUER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text("Vérifie DNS, passerelle API, handshake port réseau et génère un rapport technique pour le support.", style: TextStyle(color: _text60, fontSize: 10)),
              ],
            ),
          ),
          SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _text10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("PARAMÈTRES DE PERFORMANCE & STABILITÉ", style: TextStyle(color: _text70, fontSize: 11, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAntiAdDnsEnabled,
                  onChanged: (val) => setState(() => _isAntiAdDnsEnabled = val),
                  activeTrackColor: cyberGreen,
                  title: Text("DNS Sécurisé Anti-Pub (AdGuard DoH)", style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text("Bloque automatiquement les pubs, traceurs et contourne les restrictions DNS FAI.", style: TextStyle(color: _text54, fontSize: 10)),
                ),
                Divider(color: _text12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isMuxEnabled,
                  onChanged: (val) => setState(() => _isMuxEnabled = val),
                  activeTrackColor: cyberGreen,
                  title: Text("Multiplexage TCP (Mux)", style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text("Réutilise la même connexion TCP pour charger les pages 2x plus vite.", style: TextStyle(color: _text54, fontSize: 10)),
                ),
                Divider(color: _text12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDisconnectAlertEnabled,
                  onChanged: _setDisconnectAlertEnabled,
                  activeTrackColor: cyberRed,
                  title: Text("Alerte de déconnexion VPN", style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text("Alerte et journalise la coupure. Ne bloque pas le réseau Android hors tunnel ; activez « VPN permanent » et « Bloquer les connexions sans VPN » dans les paramètres système pour un vrai verrouillage.", style: TextStyle(color: _text54, fontSize: 10)),
                ),
                Divider(color: _text12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isAutoReconnectEnabled,
                  onChanged: _setAutoReconnectEnabled,
                  activeTrackColor: cyberYellow,
                  title: Text("Reconnexion Automatique", style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text("Tente de reconnecter le VPN automatiquement en cas de perte de réseau.", style: TextStyle(color: _text54, fontSize: 10)),
                ),
              ],
            ),
          ),
          SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _text10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.terminal, color: cyberGreen, size: 14),
                        SizedBox(width: 4),
                        Text("JOURNAL SYSTÈME V2RAY", style: TextStyle(color: _text70, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _logs.clear()),
                      child: Text("Effacer", style: TextStyle(color: _text38, fontSize: 10)),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Container(
                  height: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _fieldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _text12),
                  ),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (ctx, idx) => Text(
                      _logs[idx],
                      style: TextStyle(color: cyberGreen, fontSize: 9, fontFamily: "monospace"),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberGreen.withOpacity( 0.4)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.support_agent, color: cyberGreen, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("ASSISTANCE TECHNIQUE DIRECTE", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 2),
                          Text("WhatsApp : $_whatsappSupportPhone", style: TextStyle(color: _text60, fontSize: 10)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openUrlSafe(_whatsappSupportUrl),
                      icon: Icon(Icons.chat, color: Colors.black, size: 14),
                      label: Text("CHAT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                      style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openUrlSafe(_whatsappCommunityUrl),
                  icon: Icon(Icons.groups, color: cyberCyan, size: 16),
                  label: Text("REJOINDRE LA COMMUNAUTÉ WHATSAPP", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cyberCyan),
                    minimumSize: const Size.fromHeight(36),
                  ),
                ),
                SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openUrlSafe(_telegramChannelUrl),
                  icon: Icon(Icons.send_rounded, color: cyberGreen, size: 16),
                  label: Text("REJOINDRE LE CANAL TELEGRAM (@Abess_Vpn)", style: TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cyberGreen),
                    minimumSize: const Size.fromHeight(36),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

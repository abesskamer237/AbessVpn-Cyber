import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AbessVpnApp());
}

/// Modèle pour le serveur importé exclusivement par Token ou Fichier crypté
class ImportedVpnServer {
  final String name;
  final String address;
  final int port;
  final String path;
  final String sni;
  final String uuid;
  final String protocol;
  final String transport;
  final double bandwidthGb;
  double bandwidthUsedGb;
  final DateTime expiresAt;
  final String? token;
  final String? encryptedLink;
  final int deviceLimit;

  ImportedVpnServer({
    required this.name,
    required this.address,
    required this.port,
    required this.path,
    required this.sni,
    required this.uuid,
    this.protocol = 'vless',
    this.transport = 'ws',
    this.bandwidthGb = 10.0,
    this.bandwidthUsedGb = 0.0,
    required this.expiresAt,
    this.token,
    this.encryptedLink,
    this.deviceLimit = 1,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isQuotaExceeded => bandwidthUsedGb >= bandwidthGb;
  double get remainingGb => math.max(0.0, bandwidthGb - bandwidthUsedGb);
  double get usedPercentage => math.min(100.0, (bandwidthUsedGb / (bandwidthGb > 0 ? bandwidthGb : 1)) * 100.0);
}

class AbessVpnApp extends StatelessWidget {
  const AbessVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AbessVpn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030712),
        primaryColor: const Color(0xFF10B981),
        textTheme: GoogleFonts.orbitronTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      home: const MainVpnScreen(),
    );
  }
}

class MainVpnScreen extends StatefulWidget {
  const MainVpnScreen({super.key});

  @override
  State<MainVpnScreen> createState() => _MainVpnScreenState();
}

class _MainVpnScreenState extends State<MainVpnScreen> with SingleTickerProviderStateMixin {
  // Historique Télémétrie Graphique (fl_chart)
  final List<FlSpot> _speedHistoryDownload = [
    const FlSpot(0, 0),
    const FlSpot(1, 0.4),
    const FlSpot(2, 1.2),
    const FlSpot(3, 0.9),
    const FlSpot(4, 2.5),
    const FlSpot(5, 1.8),
    const FlSpot(6, 3.2),
  ];
  final List<FlSpot> _speedHistoryUpload = [
    const FlSpot(0, 0),
    const FlSpot(1, 0.2),
    const FlSpot(2, 0.6),
    const FlSpot(3, 0.4),
    const FlSpot(4, 1.1),
    const FlSpot(5, 0.8),
    const FlSpot(6, 1.4),
  ];

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: const Color(0xFF0F172A),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF06B6D4), width: 0.8),
        ),
      ),
    );
  }

  // Palette Cyberpunk
  static const Color cyberGreen = Color(0xFF10B981);
  static const Color cyberCyan = Color(0xFF06B6D4);
  static const Color cyberRed = Color(0xFFEF4444);
  static const Color cyberYellow = Color(0xFFF59E0B);
  static const Color cyberCardBg = Color(0xFF080F1E);

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

  // Profil Actif (Exclusivement importé)
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

  // 3 ONGLETS CYBER NAVIGATION
  int _currentNavIndex = 0;
  bool _isMuxEnabled = true;

  // MODE MULTI-PROTOCOLES AUTONOME (SANS TOKEN)
  String _customProtocol = "vless";
  String _customTransport = "ws";
  final TextEditingController _customHostCtrl = TextEditingController(text: "konoyves.shop");
  final TextEditingController _customPortCtrl = TextEditingController(text: "443");
  final TextEditingController _customPathCtrl = TextEditingController(text: "/@abess237");
  final TextEditingController _customUuidCtrl = TextEditingController(text: "abe55237-0237-4237-8237-ab3552370237");
  final TextEditingController _customSniCtrl = TextEditingController(text: "crashlyticsreports-pa.googleapis.com");
  final TextEditingController _customNameCtrl = TextEditingController(text: "Serveur Cyber Personnalisé");
  final TextEditingController _rawLinkInputCtrl = TextEditingController();

  void _generateRandomUuid() {
    final rand = math.Random();
    String s(int len) => List.generate(len, (_) => rand.nextInt(16).toRadixString(16)).join();
    final newUuid = "${s(8)}-${s(4)}-4${s(3)}-${(8 + rand.nextInt(4)).toRadixString(16)}${s(3)}-${s(12)}";
    setState(() => _customUuidCtrl.text = newUuid);
    _showToast("Nouvel UUID conforme généré !");
  }

  void _saveCustomServerManual() {
    final host = _customHostCtrl.text.trim();
    if (host.isEmpty) {
      _showToast("Veuillez indiquer un hôte ou une IP");
      return;
    }
    final enteredPort = int.tryParse(_customPortCtrl.text.trim()) ?? 443;
    final port = _customProtocol == 'shadowsocks' && _customTransport == 'native' && enteredPort == 443
        ? 10050
        : enteredPort;
    final uuid = _customUuidCtrl.text.trim().isEmpty ? "abe55237-0237-4237-8237-ab3552370237" : _customUuidCtrl.text.trim();
    final path = _customPathCtrl.text.trim().isEmpty ? "/@abess237" : _customPathCtrl.text.trim();
    final sni = _customSniCtrl.text.trim().isEmpty ? host : _customSniCtrl.text.trim();
    final name = _customNameCtrl.text.trim().isEmpty ? "Custom ($_customProtocol/$_customTransport)" : _customNameCtrl.text.trim();

    final customSrv = ImportedVpnServer(
      name: name,
      address: host,
      port: port,
      path: path,
      sni: sni,
      uuid: uuid,
      protocol: _customProtocol,
      transport: _customTransport,
      bandwidthGb: 999.0,
      bandwidthUsedGb: 0.0,
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      token: "CUSTOM-ZERO-TOKEN",
    );

    setState(() {
      currentServer = customSrv;
      _currentNavIndex = 0; // Basculer sur l'onglet de connexion
    });
    _saveCurrentServer();
    _addLog("SERVEUR MULTI-PROTOCOLE ACTIF ($_customProtocol/$_customTransport)");
    _showToast("Serveur $_customProtocol configuré avec succès ! Prêt pour connexion.");
  }

  void _parseUniversalRawLink(String raw) {
    final link = raw.trim();
    if (link.isEmpty) return;
    try {
      if (link.startsWith("vless://")) {
        final uri = Uri.parse(link.replaceAll("#", "?tag="));
        final proto = uri.scheme;
        final host = uri.host;
        final port = uri.port > 0 ? uri.port : 443;
        final uuid = uri.userInfo;
        final path = uri.queryParameters["path"] ?? "/@abess237";
        final sni = uri.queryParameters["sni"] ?? host;

        final newSrv = ImportedVpnServer(
          name: uri.queryParameters["tag"] ?? "Serveur Importé ($proto)",
          address: host.isNotEmpty ? host : "konoyves.shop",
          port: port,
          path: path,
          sni: sni,
          uuid: uuid.isNotEmpty ? uuid : "abe55237-0237-4237-8237-ab3552370237",
          protocol: proto,
          transport: uri.queryParameters["type"] ?? "ws",
          bandwidthGb: 50.0,
          bandwidthUsedGb: 0.0,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          token: "RAW-LINK-IMPORT",
        );
        setState(() {
          currentServer = newSrv;
          _currentNavIndex = 0;
        });
        _saveCurrentServer();
        _showToast("Lien $proto importé avec succès !");
      } else if (link.startsWith("vmess://") || link.startsWith("trojan://") || link.startsWith("ss://")) {
        _addLog('IMPORT REFUSÉ : PROTOCOLE NON PRIS EN CHARGE PAR CETTE VERSION');
        _showToast('Les profils compatibles sont VLESS, VMess, Trojan et Shadowsocks, selon le transport configuré.');
      } else {
        _showToast("Format de lien non reconnu");
      }
    } catch (e) {
      _showToast("Erreur analyse lien: $e");
    }
  }

  // Amélioration 1 : Kill Switch & Reconnexion Auto
  bool isKillSwitchEnabled = true;
  bool isAutoReconnectEnabled = true;
  bool killSwitchAlert = false;
  int _reconnectAttempts = 0;
  bool _userWantedConnection = false;
  Timer? _reconnectTimer;

  // Amélioration 5 : Liens WhatsApp Officiels
  static const String _whatsappCommunityUrl = 'https://chat.whatsapp.com/IR0pjvSbTvL0Wp4YlbCjhF';
  static const String _whatsappSupportUrl = 'https://wa.me/237695140419?text=Bonjour%20AbessVpn%2C%20j%27ai%20besoin%20d%27assistance%20technique%20pour%20mon%20accès%20VPN';
  static const String _whatsappSupportPhone = '+237 695 14 04 19';

  // Journal des logs
  final List<String> _logs = [];

  // URLs Serveurs Maîtres AbessVpn
  static const String _configuredApiBaseUrl = String.fromEnvironment('ABESS_API_BASE_URL', defaultValue: '');

  // Production builds configured with ABESS_API_BASE_URL must use only that
  // control plane. Falling back to legacy demo hosts could validate a licence
  // against another environment if the production VPS is temporarily offline.
  final List<String> _masterServerUrls = _configuredApiBaseUrl.trim().isNotEmpty
      ? [
          _configuredApiBaseUrl.trim().replaceFirst(RegExp(r'/+

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initDeviceId();
    _initV2Ray();
    _loadSavedServer();
    _measureRealPing();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _telemetryTimer?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _tokenInputCtrl.dispose();
    _fileInputCtrl.dispose();
    _createTokenCodeCtrl.dispose();
    _createPlanNameCtrl.dispose();
    _customHostCtrl.dispose();
    _customPortCtrl.dispose();
    _customPathCtrl.dispose();
    _customUuidCtrl.dispose();
    _customSniCtrl.dispose();
    _customNameCtrl.dispose();
    _rawLinkInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('abess_device_id');
    if (id == null) {
      final rand = math.Random().nextInt(899999) + 100000;
      id = 'HWID-PHONE-CYBER-$rand';
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
              killSwitchAlert = false;
              if (!wasConnected) _startTelemetry();
            } else if (status.state == 'DISCONNECTED') {
              isConnected = false;
              isConnecting = false;
              _stopTelemetry();
              if (_userWantedConnection) {
                if (isKillSwitchEnabled) {
                  killSwitchAlert = true;
                  _addLog('KILL SWITCH ACTIF : TOUT TRAFIC NON CHIFFRÉ BLOQUÉ');
                }
                if (isAutoReconnectEnabled && _reconnectAttempts < 5) {
                  _reconnectAttempts++;
                  _addLog('RECONNEXION AUTO DANS 3s (TENTATIVE $_reconnectAttempts/5)...');
                  _reconnectTimer?.cancel();
                  _reconnectTimer = Timer(const Duration(seconds: 3), () {
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

  // Chargement du serveur sauvegardé
  Future<void> _loadSavedServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isKillSwitchEnabled = prefs.getBool('abess_kill_switch') ?? true;
      isAutoReconnectEnabled = prefs.getBool('abess_auto_reconnect') ?? true;
    });
    final savedData = prefs.getString('abess_imported_server');
    if (savedData != null) {
      try {
        final Map<String, dynamic> map = jsonDecode(savedData);
        if (mounted) {
          setState(() {
            currentServer = ImportedVpnServer(
              name: map['name'] ?? 'ABESS VIP IMPORTÉ',
              address: map['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
              port: map['port'] ?? 443,
              path: map['path'] ?? '/@abess237',
              sni: map['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
              uuid: map['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
              bandwidthGb: (map['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
              bandwidthUsedGb: (map['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
              expiresAt: DateTime.tryParse(map['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(days: 30)),
              token: map['token'],
              encryptedLink: map['encryptedLink'],
              deviceLimit: map['deviceLimit'] ?? 1,
            );
          });
          _addLog('SERVEUR RESTAURÉ: ${currentServer!.name}');
        }
      } catch (_) {}
    } else {
      _addLog('AUCUN SERVEUR ACTIF: VEUILLEZ IMPORTER UN ACCÈS');
    }
  }

  Future<void> _saveCurrentServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (currentServer == null) {
      await prefs.remove('abess_imported_server');
      return;
    }
    final map = {
      'name': currentServer!.name,
      'address': currentServer!.address,
      'port': currentServer!.port,
      'path': currentServer!.path,
      'sni': currentServer!.sni,
      'uuid': currentServer!.uuid,
      'bandwidthGb': currentServer!.bandwidthGb,
      'bandwidthUsedGb': currentServer!.bandwidthUsedGb,
      'expiresAt': currentServer!.expiresAt.toIso8601String(),
      'token': currentServer!.token,
      'encryptedLink': currentServer!.encryptedLink,
      'deviceLimit': currentServer!.deviceLimit,
    };
    await prefs.setString('abess_imported_server', jsonEncode(map));
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
        final res = await http.get(Uri.parse('$base/api/v1/ping')).timeout(const Duration(seconds: 3));
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

    _pingTimer = Timer.periodic(const Duration(seconds: 6), (_) => _measureRealPing());

    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isConnected || !mounted) return;

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

      if (_connectionDurationSeconds % 10 == 0 && currentServer?.token != null) {
        _syncUsageWithServer();
      }
    });
  }

  Future<void> _syncUsageWithServer() async {
    if (currentServer?.token == null) return;
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
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 401 || res.statusCode == 403) {
          _addLog('ACCÈS VPN REFUSÉ PAR LE SERVEUR (HTTP ${res.statusCode})');
          await _disconnectVpn();
          _showToast('Votre accès VPN n’est plus autorisé. Vérifiez votre licence ou contactez le support.');
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
            const SnackBar(
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
          const SnackBar(
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
        title: const Text('🛑 QUOTA ÉPUISÉ', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
        content: Text(
          'Votre quota de ${currentServer?.bandwidthGb.toStringAsFixed(1)} Go est totalement consommé. Veuillez renouveler votre accès ou contacter l\'assistance WhatsApp ($_whatsappSupportPhone).',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('FERMER', style: TextStyle(color: Colors.white60)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_whatsappSupportUrl);
            },
            icon: const Icon(Icons.chat, color: cyberGreen, size: 14),
            label: const Text('ASSISTANCE WHATSAPP', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateConfigModal();
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
            child: const Text('CRÉER FORFAIT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
        title: const Text('⏳ LICENCE EXPIRÉE', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
        content: const Text(
          'La date d\'expiration de votre licence VPN est dépassée. Veuillez générer un nouveau token ou contacter l\'assistance WhatsApp.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('FERMER', style: TextStyle(color: Colors.white60)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_whatsappSupportUrl);
            },
            icon: const Icon(Icons.chat, color: cyberGreen, size: 14),
            label: const Text('SUPPORT WHATSAPP', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateConfigModal();
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
            child: const Text('NOUVEAU PASS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
              setMState(() {
                isTesting = true;
                progress = 15;
                status = 'Mesure de la latence Ping (ms)...';
              });

              try {
                final sw = Stopwatch()..start();
                final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/ping')).timeout(const Duration(seconds: 4));
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
                final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/speedtest/download?bytes=1048576')).timeout(const Duration(seconds: 5));
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
                ).timeout(const Duration(seconds: 5));
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
              decoration: const BoxDecoration(
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
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.speed, color: cyberCyan, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'SPEED TEST CYBER V2.5',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(status, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress / 100.0,
                        minHeight: 6,
                        backgroundColor: Colors.black45,
                        valueColor: const AlwaysStoppedAnimation<Color>(cyberCyan),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberYellow.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                const Text('LATENCE PING', style: TextStyle(color: cyberYellow, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('$testPing ms', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberCyan.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                const Text('DOWNLOAD', style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${testDl.toStringAsFixed(1)} Mo/s', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${(testDl * 8).toStringAsFixed(0)} Mbps', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberGreen.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                const Text('UPLOAD', style: TextStyle(color: cyberGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${testUl.toStringAsFixed(1)} Mo/s', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${(testUl * 8).toStringAsFixed(0)} Mbps', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (verdict.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cyberGreen.withOpacity( 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cyberGreen.withOpacity( 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: cyberGreen, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(verdict, style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: isTesting ? null : runTest,
                      icon: isTesting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.play_arrow, color: Colors.black),
                      label: Text(
                        isTesting ? 'ANALYSE EN COURS...' : 'LANCER LE TEST DE DÉBIT',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
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

  Future<bool> _isManagedDataPlaneReady() async {
    for (final base in _masterServerUrls) {
      try {
        final response = await http
            .get(Uri.parse('$base/api/v1/ping'))
            .timeout(const Duration(seconds: 3));
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
      setState(() => killSwitchAlert = false);
      await _disconnectVpn();
    } else {
      _userWantedConnection = true;
      _reconnectAttempts = 0;
      setState(() => killSwitchAlert = false);
      await _connectVpn();
    }
  }

  Future<void> _connectVpn() async {
    if (currentServer == null) {
      _showImportModal();
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

        final v2rayConfig = _buildV2RayVlessConfig(currentServer!);
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

  Map<String, dynamic> _buildV2RayVlessConfig(ImportedVpnServer srv) {
    // Mirror the server panel's supported matrix. HTTP-based transports use
    // TLS on port 443; native TCP/UDP is intentionally only for Shadowsocks.
    final protocol = srv.protocol.toLowerCase();
    final transport = srv.transport.toLowerCase();
    const supportedProtocols = {'vless', 'vmess', 'trojan', 'shadowsocks'};
    const supportedTransports = {'ws', 'grpc', 'httpupgrade', 'xhttp', 'native'};

    if (!supportedProtocols.contains(protocol) || !supportedTransports.contains(transport)) {
      throw UnsupportedError(
        'Configuration non prise en charge : ${protocol.toUpperCase()} + ${transport.toUpperCase()}.',
      );
    }
    if (transport == 'native' && protocol != 'shadowsocks') {
      throw UnsupportedError('Le mode TCP + UDP natif est disponible uniquement avec Shadowsocks.');
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
    if (transport == 'native') {
      streamSettings = null;
    } else {
      final Map<String, dynamic> transportSettings;
      switch (transport) {
        case 'ws':
          transportSettings = {
            'network': 'ws',
            'wsSettings': {
              'path': srv.path,
              'headers': {'Host': srv.address}
            }
          };
          break;
        case 'grpc':
          transportSettings = {
            'network': 'grpc',
            'grpcSettings': {
              'serviceName': srv.path.replaceFirst(RegExp(r'^/+'), ''),
              'multiMode': false
            }
          };
          break;
        case 'httpupgrade':
          transportSettings = {
            'network': 'httpupgrade',
            'httpupgradeSettings': {'path': srv.path, 'host': srv.address}
          };
          break;
        case 'xhttp':
          transportSettings = {
            'network': 'xhttp',
            'xhttpSettings': {'path': srv.path, 'mode': 'auto'}
          };
          break;
        default:
          throw UnsupportedError('Transport non pris en charge.');
      }

      streamSettings = {
        ...transportSettings,
        'security': 'tls',
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
    if (_isMuxEnabled && transport != 'native') {
      // XUDP carries UDP datagrams over the proxy connection when supported.
      proxyOutbound['mux'] = {
        'enabled': true,
        'concurrency': 8,
        'xudpConcurrency': 8,
        'xudpProxyUDP443': 'allow'
      };
    }

    return {
      'log': {'loglevel': 'warning'},
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

  // 1. IMPORTATION PAR CLÉ TOKEN
  Future<void> _importServerByToken(String tokenCode, {bool silent = false}) async {
    final cleanToken = tokenCode.trim().toUpperCase();
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
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['valid'] == true) {
            final srvConf = data['serverConfig'] ?? {};
            final newServer = ImportedVpnServer(
              name: data['plan'] ?? 'ABESS VIP MASTER',
              address: srvConf['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
              port: srvConf['port'] ?? 443,
              path: srvConf['path'] ?? '/@abess237',
              sni: srvConf['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
              uuid: srvConf['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
              protocol: (srvConf['protocol'] as String?) ?? 'vless',
              transport: (srvConf['transport'] as String?) ?? 'ws',
              bandwidthGb: (data['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
              bandwidthUsedGb: (data['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
              expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(days: 30)),
              token: cleanToken,
              deviceLimit: data['deviceLimit'] ?? 1,
            );
            if (mounted) {
              setState(() => currentServer = newServer);
            }
            _saveCurrentServer();
            _addLog('SERVEUR MAÎTRE VALIDÉ (${newServer.bandwidthGb} Go • Expiration: ${_formatRemaining(newServer.expiresAt)})');
            return;
          }
        } else if (res.statusCode == 403) {
          final data = jsonDecode(res.body);
          _addLog('REFUS SERVEUR: ${data['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${data['error']}')));
          }
          return;
        }
      } catch (_) {}
    }

    if (!silent) {
      _addLog('SERVEUR EN LIGNE INACCESSIBLE OU TOKEN INVALIDE');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Token non reconnu sur le serveur maître.')),
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
        ).timeout(const Duration(seconds: 4));

        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['ok'] == true) {
          final srvConf = data['serverConfig'] ?? {};
          final newServer = ImportedVpnServer(
            name: data['plan'] ?? 'PASS 1 GO GRATUIT',
            address: srvConf['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
            port: srvConf['port'] ?? 443,
            path: srvConf['path'] ?? '/@abess237',
            sni: srvConf['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
            uuid: srvConf['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
            bandwidthGb: 1.0,
            bandwidthUsedGb: 0.0,
            expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(days: 1)),
            token: data['token'],
            encryptedLink: data['encryptedLink'],
            deviceLimit: 1,
          );
          if (mounted) {
            setState(() => currentServer = newServer);
          }
          _saveCurrentServer();
          _addLog('ESSAI 1 GO ACTIVÉ AVEC SUCCÈS');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pass 1 Go / 24h activé avec succès !')),
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
      _showToast('Le lien doit commencer par abess://');
      return;
    }
    if (_deviceId.isEmpty) await _initDeviceId();

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
        ).timeout(const Duration(seconds: 5));

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
            sni: srvConf['sni']?.toString() ?? '',
            uuid: srvConf['uuid']?.toString() ?? '',
            protocol: srvConf['protocol']?.toString() ?? 'vless',
            transport: srvConf['transport']?.toString() ?? 'ws',
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

          if (mounted) setState(() {
            currentServer = newServer;
            _currentNavIndex = 0;
          });
          await _saveCurrentServer();
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
        ).timeout(const Duration(seconds: 5));

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
              title: const Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: cyberYellow),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CRÉATION VIA LE PANEL',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('FERMER', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openUrlSafe(base);
                  },
                  icon: const Icon(Icons.open_in_new, size: 14, color: Colors.black),
                  label: const Text('OUVRIR LE PANEL', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
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
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: cyberGreen),
                    SizedBox(width: 8),
                    Text('CONFIG CRÉÉE !', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Code Token : $tokenGenerated', style: const TextStyle(color: cyberGreen, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Quota : ${_createQuotaGb.toInt()} Go', style: const TextStyle(color: Colors.white70)),
                    Text('Durée : $_createExpiryDays jours', style: const TextStyle(color: Colors.white70)),
                    Text('Limite Appareils : $_createDeviceLimit', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    const Text('Cette configuration a été enregistrée directement dans la base du serveur maître.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tokenGenerated));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Token copié dans le presse-papier !')));
                    },
                    icon: const Icon(Icons.copy, size: 14, color: cyberCyan),
                    label: const Text('COPIER TOKEN', style: TextStyle(color: cyberCyan, fontSize: 11)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final newServer = ImportedVpnServer(
                        name: plan,
                        address: srvConf['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
                        port: srvConf['port'] ?? 443,
                        path: srvConf['path'] ?? '/@abess237',
                        sni: srvConf['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
                        uuid: srvConf['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
                        bandwidthGb: _createQuotaGb,
                        bandwidthUsedGb: 0.0,
                        expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(Duration(days: _createExpiryDays)),
                        token: tokenGenerated,
                        encryptedLink: data['encryptedLink'],
                        deviceLimit: _createDeviceLimit,
                      );
                      if (mounted) {
                        setState(() => currentServer = newServer);
                      }
                      _saveCurrentServer();
                      _addLog('SERVEUR ACTIVÉ DIRECTEMENT DANS L\'APP');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                    child: const Text('APPLIQUER COMME MON SERVEUR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
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
          const SnackBar(content: Text('Impossible de joindre le serveur maître.')),
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
      shape: const RoundedRectangleBorder(
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
                const Text('IMPORTER UN ACCÈS SERVEUR', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('OPTION 1 : CLÉ TOKEN FOURNIE PAR L\'ADMINISTRATEUR', style: TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _tokenInputCtrl,
              style: const TextStyle(color: cyberGreen, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Ex: ABESS-VIP-ROOT-2026',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cyberGreen)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _importServerByToken(_tokenInputCtrl.text);
              },
              icon: const Icon(Icons.key, color: Colors.black),
              label: const Text('ACTIVER PAR CLÉ TOKEN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cyberGreen,
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            const Text('OPTION 2 : LIEN CRYPTÉ ABESS:// OU FICHIER .ABESS', style: TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _fileInputCtrl,
              maxLines: 2,
              style: const TextStyle(color: cyberCyan, fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Collez le lien crypté abess://...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _importServerByEncryptedLink(_fileInputCtrl.text);
              },
              icon: const Icon(Icons.file_download, color: Colors.black),
              label: const Text('DÉCHIFFRER & CHARGER FICHIER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cyberCyan,
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _claimFreeTrial();
              },
              icon: const Icon(Icons.bolt, color: cyberYellow),
              label: const Text('RÉCLAMER ESSAI GRATUIT 1 GO / 24H (ANTI-FRAUDE)', style: TextStyle(color: cyberYellow, fontSize: 11)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: cyberYellow),
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
    _createTokenCodeCtrl.text = 'ABESS-VIP-${math.Random().nextInt(8999) + 1000}';
    showModalBottomSheet(
      context: context,
      backgroundColor: cyberCardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
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
                    const Text('CRÉER CONFIG / TOKEN (GIGAS & EXPIRATION)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('1. NOM DU FORFAIT / CLIENT', style: TextStyle(color: Colors.white70, fontSize: 10)),
                const SizedBox(height: 4),
                TextField(
                  controller: _createPlanNameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black45,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('2. CODE TOKEN', style: TextStyle(color: Colors.white70, fontSize: 10)),
                const SizedBox(height: 4),
                TextField(
                  controller: _createTokenCodeCtrl,
                  style: const TextStyle(color: cyberGreen, fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black45,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('3. NOMBRE DE GIGAS (QUOTA)', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Text('${_createQuotaGb.toInt()} Go', style: const TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 200.0].map((gb) {
                    final sel = _createQuotaGb == gb;
                    return ChoiceChip(
                      label: Text('${gb.toInt()} Go', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10)),
                      selected: sel,
                      selectedColor: cyberGreen,
                      backgroundColor: Colors.black45,
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
                    const Text('4. DATE D\'EXPIRATION (DURÉE)', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Text('$_createExpiryDays Jours', style: const TextStyle(color: cyberCyan, fontWeight: FontWeight.bold)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [1, 7, 15, 30, 90, 180, 365].map((d) {
                    final sel = _createExpiryDays == d;
                    return ChoiceChip(
                      label: Text(d == 1 ? '24h' : '$d jours', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10)),
                      selected: sel,
                      selectedColor: cyberCyan,
                      backgroundColor: Colors.black45,
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
                    const Text('5. LIMITE D\'APPAREILS AUTORISÉS', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Text('$_createDeviceLimit Appareil(s)', style: const TextStyle(color: cyberYellow, fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: [1, 2, 3, 5].map((lim) {
                    final sel = _createDeviceLimit == lim;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                      child: ChoiceChip(
                        label: Text('$lim Téléphone(s)', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10)),
                        selected: sel,
                        selectedColor: cyberYellow,
                        backgroundColor: Colors.black45,
                        onSelected: (val) => setMState(() => _createDeviceLimit = lim),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isCreatingToken ? null : () => _submitCreateToken(setMState),
                  icon: _isCreatingToken
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.cloud_upload, color: Colors.black),
                  label: Text(
                    _isCreatingToken ? 'ENREGISTREMENT SERVEUR...' : 'GÉNÉRER & ENREGISTRER SUR LE SERVEUR',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cyberGreen.withOpacity( 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cyberGreen.withOpacity( 0.4)),
              ),
              child: const Icon(Icons.shield, color: cyberGreen, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              _currentNavIndex == 0
                  ? "AbessVpn Cyber"
                  : _currentNavIndex == 1
                      ? "Serveurs & Protocoles"
                      : "Outils & Diagnostic",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _openUrlSafe(_whatsappSupportUrl),
            icon: const Icon(Icons.chat_bubble_outline, color: cyberGreen),
            tooltip: "Support WhatsApp ($_whatsappSupportPhone)",
          ),
          IconButton(
            onPressed: _showSpeedTestModal,
            icon: const Icon(Icons.speed, color: cyberCyan),
            tooltip: "Speed Test",
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _currentNavIndex,
          children: [
            _buildTab1Connection(srv, usedGb, totalGb, usedPercent, remainingDays),
            _buildTab2ProtocolsAndTokens(srv),
            _buildTab3ToolsAndStability(srv),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cyberCardBg,
          border: Border(top: BorderSide(color: cyberCyan.withOpacity( 0.25))),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: (index) => setState(() => _currentNavIndex = index),
          backgroundColor: cyberCardBg,
          selectedItemColor: cyberGreen,
          unselectedItemColor: Colors.white38,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield, color: cyberGreen),
              label: "Connexion VPN",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune_outlined),
              activeIcon: Icon(Icons.tune, color: cyberCyan),
              label: "Serveurs & Tokens",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed_outlined),
              activeIcon: Icon(Icons.speed, color: cyberGreen),
              label: "Outils & Vitesse",
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // ONGLET 1 : CONNEXION VPN & DASHBOARD PRINCIPAL
  // ==========================================================================
  Widget _buildTab1Connection(ImportedVpnServer? srv, double usedGb, double totalGb, double usedPercent, String remainingDays) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          if (srv == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cyberCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cyberCyan.withOpacity( 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: cyberCyan, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("AUCUN SERVEUR CONFIGURÉ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 2),
                        Text("Importez un token ou configurez un serveur dans l'onglet Serveurs.", style: TextStyle(color: Colors.white60, fontSize: 10)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentNavIndex = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cyberCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("CONFIGURER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cyberCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cyberGreen.withOpacity( 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("SERVEUR ACTIF IMPORTÉ", style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(
                          srv.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          "${srv.protocol.toUpperCase()} • ${srv.transport.toUpperCase()} • TLS 1.3 CHIFFRÉ",
                          style: const TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentNavIndex = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: cyberGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: cyberGreen),
                      ),
                    ),
                    child: const Text("CHANGER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (srv != null && (srv.isExpired || srv.isQuotaExceeded || srv.usedPercentage >= 80)) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed.withOpacity( 0.12) : cyberYellow.withOpacity( 0.12),
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

          GestureDetector(
            onTap: isConnecting ? null : _toggleVpn,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (ctx, child) {
                final pulseVal = isConnected ? _pulseController.value : 0.0;
                return Container(
                  width: 165,
                  height: 165,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? Color.lerp(const Color(0xFF042F24), const Color(0xFF064E3B), pulseVal)
                        : const Color(0xFF0B132B),
                    border: Border.all(
                      color: isConnected ? cyberGreen : Colors.white24,
                      width: 4,
                    ),
                    boxShadow: [
                      if (isConnected)
                        BoxShadow(
                          color: cyberGreen.withOpacity( 0.3 + pulseVal * 0.3),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new,
                          size: 46,
                          color: isConnected ? cyberGreen : (srv != null ? Colors.white70 : Colors.white24),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isConnecting
                              ? "CONNEXION..."
                              : isConnected
                                  ? "CONNECTÉ"
                                  : (srv != null ? "ACTIVER" : "AUCUN ACCÈS"),
                          style: TextStyle(
                            color: isConnected ? cyberGreen : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          Text(
            _formatTimer(_connectionDurationSeconds),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("IP TUNNEL : ", style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text(isConnected ? _virtualIp : "EN VEILLE", style: const TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              const Text("• HWID : ", style: TextStyle(color: Colors.white38, fontSize: 10)),
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
                      const Row(
                        children: [
                          Icon(Icons.pie_chart, color: cyberGreen, size: 14),
                          SizedBox(width: 4),
                          Text("GIGAS UTILISÉS / QUOTA", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text(
                        "${usedGb.toStringAsFixed(2)} Go / ${totalGb.toStringAsFixed(1)} Go (${usedPercent.toInt()}%)",
                        style: const TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: totalGb > 0 ? (usedPercent / 100.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: Colors.black45,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usedPercent > 85 ? cyberRed : usedPercent > 60 ? cyberYellow : cyberGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Restant: ${(totalGb - usedGb).toStringAsFixed(2)} Go", style: const TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text("Expire : $remainingDays", style: const TextStyle(color: Colors.white60, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.arrow_downward, color: cyberCyan, size: 14),
                          SizedBox(width: 4),
                          Text("DÉBIT DL", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isConnected ? "${_currentDownloadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Total: ${_totalDownloadMb.toStringAsFixed(1)} Mo",
                        style: const TextStyle(color: Colors.white38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.arrow_upward, color: cyberGreen, size: 14),
                          SizedBox(width: 4),
                          Text("DÉBIT UL", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isConnected ? "${_currentUploadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Total: ${_totalUploadMb.toStringAsFixed(1)} Mo",
                        style: const TextStyle(color: Colors.white38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.wifi, color: cyberYellow, size: 14),
                          SizedBox(width: 4),
                          Text("PING MS", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentPingMs > 0 ? '$_currentPingMs ms' : '—',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const Text(
                        "Serv. Maître",
                        style: TextStyle(color: Colors.white38, fontSize: 8),
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
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("MONITEUR BANDE PASSANTE TEMPS RÉEL", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Icon(Icons.circle, color: cyberCyan, size: 8),
                        SizedBox(width: 4),
                        Text("Download", style: TextStyle(color: Colors.white60, fontSize: 9)),
                        SizedBox(width: 8),
                        Icon(Icons.circle, color: cyberGreen, size: 8),
                        SizedBox(width: 4),
                        Text("Upload", style: TextStyle(color: Colors.white60, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 100,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _speedHistoryDownload,
                          isCurved: true,
                          color: cyberCyan,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: cyberCyan.withOpacity( 0.12)),
                        ),
                        LineChartBarData(
                          spots: _speedHistoryUpload,
                          isCurved: true,
                          color: cyberGreen,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
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
  // ONGLET 2 : STUDIO SERVEURS, TOKENS & MODE MULTI-PROTOCOLES (ZERO-TOKEN)
  // ==========================================================================
  Widget _buildTab2ProtocolsAndTokens(ImportedVpnServer? srv) {
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
              border: Border.all(color: cyberGreen.withOpacity( 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.vpn_key, color: cyberGreen, size: 18),
                    SizedBox(width: 8),
                    Text("ACTIVATION PAR CLÉ TOKEN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text("Saisissez votre code licence fourni par votre revendeur officiel pour activer votre accès sécurisé.", style: TextStyle(color: Colors.white60, fontSize: 10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tokenInputCtrl,
                        style: const TextStyle(color: cyberGreen, fontFamily: "monospace", fontSize: 12),
                        decoration: InputDecoration(
                          hintText: "EX: ABESS-VIP-ROOT-2026",
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                          filled: true,
                          fillColor: const Color(0xFF030712),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cyberGreen.withOpacity( 0.4))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: cyberGreen)),
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

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberCyan.withOpacity( 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune, color: cyberCyan, size: 18),
                        SizedBox(width: 8),
                        Text("MODE SANS TOKEN (MULTI-PROTOCOLES)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cyberCyan.withOpacity( 0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Text("AUTONOME", style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text("En cas d'absence de token, configurez directement vos paramètres de connexion pour n'importe quel protocole et transport.", style: TextStyle(color: Colors.white60, fontSize: 10)),
                const SizedBox(height: 14),

                const Text("PROTOCOLE RÉSEAU", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildProtocolChip("vless", "VLESS (Recommandé)"),
                    const SizedBox(width: 6),
                    _buildProtocolChip("vmess", "VMess"),
                    const SizedBox(width: 6),
                    _buildProtocolChip("trojan", "Trojan"),
                    const SizedBox(width: 6),
                    _buildProtocolChip("shadowsocks", "Shadowsocks"),
                  ],
                ),
                const SizedBox(height: 12),

                const Text("TRANSPORT STREAM", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildTransportChip("ws", "WebSocket"),
                    const SizedBox(width: 6),
                    _buildTransportChip("grpc", "gRPC"),
                    const SizedBox(width: 6),
                    _buildTransportChip("httpupgrade", "HTTPUpgrade"),
                    const SizedBox(width: 6),
                    _buildTransportChip("xhttp", "XHTTP"),
                  ],
                ),
                if (_customProtocol == "shadowsocks") ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTransportChip("native", "TCP + UDP natifs"),
                      const Expanded(child: SizedBox()),
                      const Expanded(child: SizedBox()),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildFormField("Hôte / Domaine / IP", _customHostCtrl, "ex: konoyves.shop"),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: _buildFormField("Port", _customPortCtrl, "443"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _buildFormField("Chemin WebSocket / xHTTP", _customPathCtrl, "/@abess237"),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFormField("SNI Bug Host (Zero-Rating)", _customSniCtrl, "crashlyticsreports-pa.googleapis.com"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Identifiant UUID / Mot de passe", style: TextStyle(color: Colors.white60, fontSize: 10)),
                        GestureDetector(
                          onTap: _generateRandomUuid,
                          child: const Text("Générer UUID Aléatoire", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _customUuidCtrl,
                      style: const TextStyle(color: cyberCyan, fontFamily: "monospace", fontSize: 11),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF030712),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                ElevatedButton.icon(
                  onPressed: _saveCustomServerManual,
                  icon: const Icon(Icons.flash_on, color: Colors.black, size: 16),
                  label: const Text("ACTIVER CE SERVEUR PERSONNEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cyberCyan,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("IMPORTATION RAPIDE PAR LIEN BRUT", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text("Collez un lien vless://, vmess://, trojan:// ou ss:// généré par un autre outil.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rawLinkInputCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: "monospace"),
                        decoration: InputDecoration(
                          hintText: "Coller vless://... ou vmess://...",
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 10),
                          filled: true,
                          fillColor: const Color(0xFF030712),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_rawLinkInputCtrl.text.isNotEmpty) {
                          _parseUniversalRawLink(_rawLinkInputCtrl.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("IMPORTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ONGLET 3 : OUTILS, STABILITÉ & LOGS EN DIRECT
  // ==========================================================================
  Widget _buildTab3ToolsAndStability(ImportedVpnServer? srv) {
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
                    const Row(
                      children: [
                        Icon(Icons.speed, color: cyberCyan, size: 18),
                        SizedBox(width: 8),
                        Text("SPEED TEST CYBER INTÉGRÉ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                      child: const Text("TESTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text("Mesure en direct la latence (ping) et le débit montant/descendant vers les serveurs maîtres.", style: TextStyle(color: Colors.white60, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("PARAMÈTRES DE PERFORMANCE & STABILITÉ", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isMuxEnabled,
                  onChanged: (val) => setState(() => _isMuxEnabled = val),
                  activeTrackColor: cyberGreen,
                  title: const Text("Multiplexage TCP (Mux)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Réutilise la même connexion TCP pour charger les pages 2x plus vite.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ),
                const Divider(color: Colors.white12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isKillSwitchEnabled,
                  onChanged: (val) => setState(() => isKillSwitchEnabled = val),
                  activeTrackColor: cyberRed,
                  title: const Text("Kill Switch Anti-Fuite", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Coupe automatiquement le trafic si le tunnel VPN se déconnecte.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ),
                const Divider(color: Colors.white12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isAutoReconnectEnabled,
                  onChanged: (val) => setState(() => isAutoReconnectEnabled = val),
                  activeTrackColor: cyberYellow,
                  title: const Text("Reconnexion Automatique", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Tente de reconnecter le VPN automatiquement en cas de perte de réseau.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal, color: cyberGreen, size: 14),
                        SizedBox(width: 4),
                        Text("JOURNAL SYSTÈME V2RAY", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _logs.clear()),
                      child: const Text("Effacer", style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF030712),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (ctx, idx) => Text(
                      _logs[idx],
                      style: const TextStyle(color: cyberGreen, fontSize: 9, fontFamily: "monospace"),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

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
                    const Icon(Icons.support_agent, color: cyberGreen, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("ASSISTANCE TECHNIQUE DIRECTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 2),
                          Text("WhatsApp : $_whatsappSupportPhone", style: TextStyle(color: Colors.white60, fontSize: 10)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openUrlSafe(_whatsappSupportUrl),
                      icon: const Icon(Icons.chat, color: Colors.black, size: 14),
                      label: const Text("CHAT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                      style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openUrlSafe(_whatsappCommunityUrl),
                  icon: const Icon(Icons.groups, color: cyberCyan, size: 16),
                  label: const Text("REJOINDRE LA COMMUNAUTÉ WHATSAPP", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cyberCyan),
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

  Widget _buildProtocolChip(String id, String label) {
    final isSelected = _customProtocol == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          if (id != 'shadowsocks' && _customTransport == 'native') {
            _customTransport = 'ws';
            if (_customPortCtrl.text.trim() == '10050') _customPortCtrl.text = '443';
          }
          _customProtocol = id;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyberCyan.withOpacity( 0.25) : const Color(0xFF030712),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cyberCyan : Colors.white12),
          ),
          child: Center(
            child: Text(
              label.split(" ")[0],
              style: TextStyle(
                color: isSelected ? cyberCyan : Colors.white60,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransportChip(String id, String label) {
    final isSelected = _customTransport == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          if (id == 'native' && _customProtocol == 'shadowsocks' && _customPortCtrl.text.trim() == '443') {
            _customPortCtrl.text = '10050';
          } else if (_customTransport == 'native' && _customPortCtrl.text.trim() == '10050' && id != 'native') {
            _customPortCtrl.text = '443';
          }
          _customTransport = id;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyberGreen.withOpacity( 0.25) : const Color(0xFF030712),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cyberGreen : Colors.white12),
          ),
          child: Center(
            child: Text(
              label.split(" ")[0],
              style: TextStyle(
                color: isSelected ? cyberGreen : Colors.white60,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: "monospace"),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
            filled: true,
            fillColor: const Color(0xFF030712),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
          ),
        ),
      ],
    );
  }
}
), ''),
        ]
      : [
          'https://ais-pre-byhlddl5hshwycdttmipl7-953522022413.europe-west2.run.app',
          'https://ais-dev-byhlddl5hshwycdttmipl7-953522022413.europe-west2.run.app',
          'https://abess-ops-hub-d-ploiement-docker-1.ai.studio',
          'https://ais-pre-23z4ejavtx4qwesb3fw46m-293855677478.us-west2.run.app',
          'https://abess-ops-hub-d-ploiement-docker.ai.studio',
          'https://ais-dev-23z4ejavtx4qwesb3fw46m-293855677478.us-west2.run.app',
        ];

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initDeviceId();
    _initV2Ray();
    _loadSavedServer();
    _measureRealPing();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _telemetryTimer?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _tokenInputCtrl.dispose();
    _fileInputCtrl.dispose();
    _createTokenCodeCtrl.dispose();
    _createPlanNameCtrl.dispose();
    _customHostCtrl.dispose();
    _customPortCtrl.dispose();
    _customPathCtrl.dispose();
    _customUuidCtrl.dispose();
    _customSniCtrl.dispose();
    _customNameCtrl.dispose();
    _rawLinkInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('abess_device_id');
    if (id == null) {
      final rand = math.Random().nextInt(899999) + 100000;
      id = 'HWID-PHONE-CYBER-$rand';
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
              killSwitchAlert = false;
              if (!wasConnected) _startTelemetry();
            } else if (status.state == 'DISCONNECTED') {
              isConnected = false;
              isConnecting = false;
              _stopTelemetry();
              if (_userWantedConnection) {
                if (isKillSwitchEnabled) {
                  killSwitchAlert = true;
                  _addLog('KILL SWITCH ACTIF : TOUT TRAFIC NON CHIFFRÉ BLOQUÉ');
                }
                if (isAutoReconnectEnabled && _reconnectAttempts < 5) {
                  _reconnectAttempts++;
                  _addLog('RECONNEXION AUTO DANS 3s (TENTATIVE $_reconnectAttempts/5)...');
                  _reconnectTimer?.cancel();
                  _reconnectTimer = Timer(const Duration(seconds: 3), () {
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

  // Chargement du serveur sauvegardé
  Future<void> _loadSavedServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isKillSwitchEnabled = prefs.getBool('abess_kill_switch') ?? true;
      isAutoReconnectEnabled = prefs.getBool('abess_auto_reconnect') ?? true;
    });
    final savedData = prefs.getString('abess_imported_server');
    if (savedData != null) {
      try {
        final Map<String, dynamic> map = jsonDecode(savedData);
        if (mounted) {
          setState(() {
            currentServer = ImportedVpnServer(
              name: map['name'] ?? 'ABESS VIP IMPORTÉ',
              address: map['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
              port: map['port'] ?? 443,
              path: map['path'] ?? '/@abess237',
              sni: map['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
              uuid: map['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
              bandwidthGb: (map['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
              bandwidthUsedGb: (map['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
              expiresAt: DateTime.tryParse(map['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(days: 30)),
              token: map['token'],
              encryptedLink: map['encryptedLink'],
              deviceLimit: map['deviceLimit'] ?? 1,
            );
          });
          _addLog('SERVEUR RESTAURÉ: ${currentServer!.name}');
        }
      } catch (_) {}
    } else {
      _addLog('AUCUN SERVEUR ACTIF: VEUILLEZ IMPORTER UN ACCÈS');
    }
  }

  Future<void> _saveCurrentServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (currentServer == null) {
      await prefs.remove('abess_imported_server');
      return;
    }
    final map = {
      'name': currentServer!.name,
      'address': currentServer!.address,
      'port': currentServer!.port,
      'path': currentServer!.path,
      'sni': currentServer!.sni,
      'uuid': currentServer!.uuid,
      'bandwidthGb': currentServer!.bandwidthGb,
      'bandwidthUsedGb': currentServer!.bandwidthUsedGb,
      'expiresAt': currentServer!.expiresAt.toIso8601String(),
      'token': currentServer!.token,
      'encryptedLink': currentServer!.encryptedLink,
      'deviceLimit': currentServer!.deviceLimit,
    };
    await prefs.setString('abess_imported_server', jsonEncode(map));
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
        final res = await http.get(Uri.parse('$base/api/v1/ping')).timeout(const Duration(seconds: 3));
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

    _pingTimer = Timer.periodic(const Duration(seconds: 6), (_) => _measureRealPing());

    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isConnected || !mounted) return;

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

      if (_connectionDurationSeconds % 10 == 0 && currentServer?.token != null) {
        _syncUsageWithServer();
      }
    });
  }

  Future<void> _syncUsageWithServer() async {
    if (currentServer?.token == null) return;
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
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 401 || res.statusCode == 403) {
          _addLog('ACCÈS VPN REFUSÉ PAR LE SERVEUR (HTTP ${res.statusCode})');
          await _disconnectVpn();
          _showToast('Votre accès VPN n’est plus autorisé. Vérifiez votre licence ou contactez le support.');
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
            const SnackBar(
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
          const SnackBar(
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
        title: const Text('🛑 QUOTA ÉPUISÉ', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
        content: Text(
          'Votre quota de ${currentServer?.bandwidthGb.toStringAsFixed(1)} Go est totalement consommé. Veuillez renouveler votre accès ou contacter l\'assistance WhatsApp ($_whatsappSupportPhone).',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('FERMER', style: TextStyle(color: Colors.white60)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_whatsappSupportUrl);
            },
            icon: const Icon(Icons.chat, color: cyberGreen, size: 14),
            label: const Text('ASSISTANCE WHATSAPP', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateConfigModal();
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
            child: const Text('CRÉER FORFAIT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
        title: const Text('⏳ LICENCE EXPIRÉE', style: TextStyle(color: cyberRed, fontWeight: FontWeight.bold)),
        content: const Text(
          'La date d\'expiration de votre licence VPN est dépassée. Veuillez générer un nouveau token ou contacter l\'assistance WhatsApp.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('FERMER', style: TextStyle(color: Colors.white60)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrlSafe(_whatsappSupportUrl);
            },
            icon: const Icon(Icons.chat, color: cyberGreen, size: 14),
            label: const Text('SUPPORT WHATSAPP', style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateConfigModal();
            },
            style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
            child: const Text('NOUVEAU PASS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
              setMState(() {
                isTesting = true;
                progress = 15;
                status = 'Mesure de la latence Ping (ms)...';
              });

              try {
                final sw = Stopwatch()..start();
                final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/ping')).timeout(const Duration(seconds: 4));
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
                final res = await http.get(Uri.parse('${_masterServerUrls[0]}/api/v1/speedtest/download?bytes=1048576')).timeout(const Duration(seconds: 5));
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
                ).timeout(const Duration(seconds: 5));
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
              decoration: const BoxDecoration(
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
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.speed, color: cyberCyan, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'SPEED TEST CYBER V2.5',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(status, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress / 100.0,
                        minHeight: 6,
                        backgroundColor: Colors.black45,
                        valueColor: const AlwaysStoppedAnimation<Color>(cyberCyan),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberYellow.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                const Text('LATENCE PING', style: TextStyle(color: cyberYellow, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('$testPing ms', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberCyan.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                const Text('DOWNLOAD', style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${testDl.toStringAsFixed(1)} Mo/s', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${(testDl * 8).toStringAsFixed(0)} Mbps', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: cyberGreen.withOpacity( 0.4))),
                            child: Column(
                              children: [
                                const Text('UPLOAD', style: TextStyle(color: cyberGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${testUl.toStringAsFixed(1)} Mo/s', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${(testUl * 8).toStringAsFixed(0)} Mbps', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (verdict.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cyberGreen.withOpacity( 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cyberGreen.withOpacity( 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: cyberGreen, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(verdict, style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: isTesting ? null : runTest,
                      icon: isTesting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.play_arrow, color: Colors.black),
                      label: Text(
                        isTesting ? 'ANALYSE EN COURS...' : 'LANCER LE TEST DE DÉBIT',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
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

  Future<bool> _isManagedDataPlaneReady() async {
    for (final base in _masterServerUrls) {
      try {
        final response = await http
            .get(Uri.parse('$base/api/v1/ping'))
            .timeout(const Duration(seconds: 3));
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
      setState(() => killSwitchAlert = false);
      await _disconnectVpn();
    } else {
      _userWantedConnection = true;
      _reconnectAttempts = 0;
      setState(() => killSwitchAlert = false);
      await _connectVpn();
    }
  }

  Future<void> _connectVpn() async {
    if (currentServer == null) {
      _showImportModal();
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

        final v2rayConfig = _buildV2RayVlessConfig(currentServer!);
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

  Map<String, dynamic> _buildV2RayVlessConfig(ImportedVpnServer srv) {
    if (srv.protocol.toLowerCase() != 'vless' || srv.transport.toLowerCase() != 'ws') {
      throw UnsupportedError(
        'Configuration non prise en charge par ce client : ${srv.protocol.toUpperCase()} + ${srv.transport.toUpperCase()}. '
        'Cette version attend VLESS + WebSocket + TLS.',
      );
    }
    return {
      "log": {"loglevel": "warning"},
      "inbounds": [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "settings": {"auth": "noauth", "udp": true}
        }
      ],
      "outbounds": [
        {
          "tag": "proxy",
          "protocol": "vless",
          "settings": {
            "vnext": [
              {
                "address": srv.address,
                "port": srv.port,
                "users": [
                  {
                    "id": srv.uuid,
                    "encryption": "none",
                    "level": 0
                  }
                ]
              }
            ]
          },
          "streamSettings": {
            "network": "ws",
            "security": "tls",
            "tlsSettings": {
              "allowInsecure": false,
              "serverName": srv.sni
            },
            "wsSettings": {
              "path": srv.path,
              "headers": {"Host": srv.address}
            }
          }
        },
        {
          "tag": "direct",
          "protocol": "freedom",
          "settings": {}
        }
      ]
    };
  }

  // 1. IMPORTATION PAR CLÉ TOKEN
  Future<void> _importServerByToken(String tokenCode, {bool silent = false}) async {
    final cleanToken = tokenCode.trim().toUpperCase();
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
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['valid'] == true) {
            final srvConf = data['serverConfig'] ?? {};
            final newServer = ImportedVpnServer(
              name: data['plan'] ?? 'ABESS VIP MASTER',
              address: srvConf['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
              port: srvConf['port'] ?? 443,
              path: srvConf['path'] ?? '/@abess237',
              sni: srvConf['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
              uuid: srvConf['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
              protocol: (srvConf['protocol'] as String?) ?? 'vless',
              transport: (srvConf['transport'] as String?) ?? 'ws',
              bandwidthGb: (data['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
              bandwidthUsedGb: (data['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
              expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(days: 30)),
              token: cleanToken,
              deviceLimit: data['deviceLimit'] ?? 1,
            );
            if (mounted) {
              setState(() => currentServer = newServer);
            }
            _saveCurrentServer();
            _addLog('SERVEUR MAÎTRE VALIDÉ (${newServer.bandwidthGb} Go • Expiration: ${_formatRemaining(newServer.expiresAt)})');
            return;
          }
        } else if (res.statusCode == 403) {
          final data = jsonDecode(res.body);
          _addLog('REFUS SERVEUR: ${data['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${data['error']}')));
          }
          return;
        }
      } catch (_) {}
    }

    if (!silent) {
      _addLog('SERVEUR EN LIGNE INACCESSIBLE OU TOKEN INVALIDE');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Token non reconnu sur le serveur maître.')),
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
        ).timeout(const Duration(seconds: 4));

        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['ok'] == true) {
          final srvConf = data['serverConfig'] ?? {};
          final newServer = ImportedVpnServer(
            name: data['plan'] ?? 'PASS 1 GO GRATUIT',
            address: srvConf['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
            port: srvConf['port'] ?? 443,
            path: srvConf['path'] ?? '/@abess237',
            sni: srvConf['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
            uuid: srvConf['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
            bandwidthGb: 1.0,
            bandwidthUsedGb: 0.0,
            expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(days: 1)),
            token: data['token'],
            encryptedLink: data['encryptedLink'],
            deviceLimit: 1,
          );
          if (mounted) {
            setState(() => currentServer = newServer);
          }
          _saveCurrentServer();
          _addLog('ESSAI 1 GO ACTIVÉ AVEC SUCCÈS');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pass 1 Go / 24h activé avec succès !')),
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
      _showToast('Le lien doit commencer par abess://');
      return;
    }
    if (_deviceId.isEmpty) await _initDeviceId();

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
        ).timeout(const Duration(seconds: 5));

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
            sni: srvConf['sni']?.toString() ?? '',
            uuid: srvConf['uuid']?.toString() ?? '',
            protocol: srvConf['protocol']?.toString() ?? 'vless',
            transport: srvConf['transport']?.toString() ?? 'ws',
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

          if (mounted) setState(() {
            currentServer = newServer;
            _currentNavIndex = 0;
          });
          await _saveCurrentServer();
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
        ).timeout(const Duration(seconds: 5));

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
              title: const Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: cyberYellow),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CRÉATION VIA LE PANEL',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('FERMER', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openUrlSafe(base);
                  },
                  icon: const Icon(Icons.open_in_new, size: 14, color: Colors.black),
                  label: const Text('OUVRIR LE PANEL', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
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
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: cyberGreen),
                    SizedBox(width: 8),
                    Text('CONFIG CRÉÉE !', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Code Token : $tokenGenerated', style: const TextStyle(color: cyberGreen, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Quota : ${_createQuotaGb.toInt()} Go', style: const TextStyle(color: Colors.white70)),
                    Text('Durée : $_createExpiryDays jours', style: const TextStyle(color: Colors.white70)),
                    Text('Limite Appareils : $_createDeviceLimit', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    const Text('Cette configuration a été enregistrée directement dans la base du serveur maître.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tokenGenerated));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Token copié dans le presse-papier !')));
                    },
                    icon: const Icon(Icons.copy, size: 14, color: cyberCyan),
                    label: const Text('COPIER TOKEN', style: TextStyle(color: cyberCyan, fontSize: 11)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final newServer = ImportedVpnServer(
                        name: plan,
                        address: srvConf['address'] ?? 'abess-ops-hub-d-ploiement-docker.ai.studio',
                        port: srvConf['port'] ?? 443,
                        path: srvConf['path'] ?? '/@abess237',
                        sni: srvConf['sni'] ?? 'crashlyticsreports-pa.googleapis.com',
                        uuid: srvConf['uuid'] ?? 'abe55237-0237-4237-8237-ab3552370237',
                        bandwidthGb: _createQuotaGb,
                        bandwidthUsedGb: 0.0,
                        expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(Duration(days: _createExpiryDays)),
                        token: tokenGenerated,
                        encryptedLink: data['encryptedLink'],
                        deviceLimit: _createDeviceLimit,
                      );
                      if (mounted) {
                        setState(() => currentServer = newServer);
                      }
                      _saveCurrentServer();
                      _addLog('SERVEUR ACTIVÉ DIRECTEMENT DANS L\'APP');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                    child: const Text('APPLIQUER COMME MON SERVEUR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
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
          const SnackBar(content: Text('Impossible de joindre le serveur maître.')),
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
      shape: const RoundedRectangleBorder(
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
                const Text('IMPORTER UN ACCÈS SERVEUR', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('OPTION 1 : CLÉ TOKEN FOURNIE PAR L\'ADMINISTRATEUR', style: TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _tokenInputCtrl,
              style: const TextStyle(color: cyberGreen, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Ex: ABESS-VIP-ROOT-2026',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cyberGreen)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _importServerByToken(_tokenInputCtrl.text);
              },
              icon: const Icon(Icons.key, color: Colors.black),
              label: const Text('ACTIVER PAR CLÉ TOKEN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cyberGreen,
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            const Text('OPTION 2 : LIEN CRYPTÉ ABESS:// OU FICHIER .ABESS', style: TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _fileInputCtrl,
              maxLines: 2,
              style: const TextStyle(color: cyberCyan, fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Collez le lien crypté abess://...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _importServerByEncryptedLink(_fileInputCtrl.text);
              },
              icon: const Icon(Icons.file_download, color: Colors.black),
              label: const Text('DÉCHIFFRER & CHARGER FICHIER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cyberCyan,
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _claimFreeTrial();
              },
              icon: const Icon(Icons.bolt, color: cyberYellow),
              label: const Text('RÉCLAMER ESSAI GRATUIT 1 GO / 24H (ANTI-FRAUDE)', style: TextStyle(color: cyberYellow, fontSize: 11)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: cyberYellow),
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
    _createTokenCodeCtrl.text = 'ABESS-VIP-${math.Random().nextInt(8999) + 1000}';
    showModalBottomSheet(
      context: context,
      backgroundColor: cyberCardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
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
                    const Text('CRÉER CONFIG / TOKEN (GIGAS & EXPIRATION)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('1. NOM DU FORFAIT / CLIENT', style: TextStyle(color: Colors.white70, fontSize: 10)),
                const SizedBox(height: 4),
                TextField(
                  controller: _createPlanNameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black45,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('2. CODE TOKEN', style: TextStyle(color: Colors.white70, fontSize: 10)),
                const SizedBox(height: 4),
                TextField(
                  controller: _createTokenCodeCtrl,
                  style: const TextStyle(color: cyberGreen, fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black45,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('3. NOMBRE DE GIGAS (QUOTA)', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Text('${_createQuotaGb.toInt()} Go', style: const TextStyle(color: cyberGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 200.0].map((gb) {
                    final sel = _createQuotaGb == gb;
                    return ChoiceChip(
                      label: Text('${gb.toInt()} Go', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10)),
                      selected: sel,
                      selectedColor: cyberGreen,
                      backgroundColor: Colors.black45,
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
                    const Text('4. DATE D\'EXPIRATION (DURÉE)', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Text('$_createExpiryDays Jours', style: const TextStyle(color: cyberCyan, fontWeight: FontWeight.bold)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [1, 7, 15, 30, 90, 180, 365].map((d) {
                    final sel = _createExpiryDays == d;
                    return ChoiceChip(
                      label: Text(d == 1 ? '24h' : '$d jours', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10)),
                      selected: sel,
                      selectedColor: cyberCyan,
                      backgroundColor: Colors.black45,
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
                    const Text('5. LIMITE D\'APPAREILS AUTORISÉS', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Text('$_createDeviceLimit Appareil(s)', style: const TextStyle(color: cyberYellow, fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: [1, 2, 3, 5].map((lim) {
                    final sel = _createDeviceLimit == lim;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                      child: ChoiceChip(
                        label: Text('$lim Téléphone(s)', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10)),
                        selected: sel,
                        selectedColor: cyberYellow,
                        backgroundColor: Colors.black45,
                        onSelected: (val) => setMState(() => _createDeviceLimit = lim),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isCreatingToken ? null : () => _submitCreateToken(setMState),
                  icon: _isCreatingToken
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.cloud_upload, color: Colors.black),
                  label: Text(
                    _isCreatingToken ? 'ENREGISTREMENT SERVEUR...' : 'GÉNÉRER & ENREGISTRER SUR LE SERVEUR',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cyberGreen.withOpacity( 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cyberGreen.withOpacity( 0.4)),
              ),
              child: const Icon(Icons.shield, color: cyberGreen, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              _currentNavIndex == 0
                  ? "AbessVpn Cyber"
                  : _currentNavIndex == 1
                      ? "Serveurs & Protocoles"
                      : "Outils & Diagnostic",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _openUrlSafe(_whatsappSupportUrl),
            icon: const Icon(Icons.chat_bubble_outline, color: cyberGreen),
            tooltip: "Support WhatsApp ($_whatsappSupportPhone)",
          ),
          IconButton(
            onPressed: _showSpeedTestModal,
            icon: const Icon(Icons.speed, color: cyberCyan),
            tooltip: "Speed Test",
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _currentNavIndex,
          children: [
            _buildTab1Connection(srv, usedGb, totalGb, usedPercent, remainingDays),
            _buildTab2ProtocolsAndTokens(srv),
            _buildTab3ToolsAndStability(srv),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cyberCardBg,
          border: Border(top: BorderSide(color: cyberCyan.withOpacity( 0.25))),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: (index) => setState(() => _currentNavIndex = index),
          backgroundColor: cyberCardBg,
          selectedItemColor: cyberGreen,
          unselectedItemColor: Colors.white38,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield, color: cyberGreen),
              label: "Connexion VPN",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune_outlined),
              activeIcon: Icon(Icons.tune, color: cyberCyan),
              label: "Serveurs & Tokens",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed_outlined),
              activeIcon: Icon(Icons.speed, color: cyberGreen),
              label: "Outils & Vitesse",
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // ONGLET 1 : CONNEXION VPN & DASHBOARD PRINCIPAL
  // ==========================================================================
  Widget _buildTab1Connection(ImportedVpnServer? srv, double usedGb, double totalGb, double usedPercent, String remainingDays) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          if (srv == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cyberCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cyberCyan.withOpacity( 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: cyberCyan, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("AUCUN SERVEUR CONFIGURÉ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 2),
                        Text("Importez un token ou configurez un serveur dans l'onglet Serveurs.", style: TextStyle(color: Colors.white60, fontSize: 10)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentNavIndex = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cyberCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("CONFIGURER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cyberCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cyberGreen.withOpacity( 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("SERVEUR ACTIF IMPORTÉ", style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(
                          srv.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          "${srv.protocol.toUpperCase()} • ${srv.transport.toUpperCase()} • TLS 1.3 CHIFFRÉ",
                          style: const TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentNavIndex = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: cyberGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: cyberGreen),
                      ),
                    ),
                    child: const Text("CHANGER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (srv != null && (srv.isExpired || srv.isQuotaExceeded || srv.usedPercentage >= 80)) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (srv.isExpired || srv.isQuotaExceeded) ? cyberRed.withOpacity( 0.12) : cyberYellow.withOpacity( 0.12),
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

          GestureDetector(
            onTap: isConnecting ? null : _toggleVpn,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (ctx, child) {
                final pulseVal = isConnected ? _pulseController.value : 0.0;
                return Container(
                  width: 165,
                  height: 165,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? Color.lerp(const Color(0xFF042F24), const Color(0xFF064E3B), pulseVal)
                        : const Color(0xFF0B132B),
                    border: Border.all(
                      color: isConnected ? cyberGreen : Colors.white24,
                      width: 4,
                    ),
                    boxShadow: [
                      if (isConnected)
                        BoxShadow(
                          color: cyberGreen.withOpacity( 0.3 + pulseVal * 0.3),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new,
                          size: 46,
                          color: isConnected ? cyberGreen : (srv != null ? Colors.white70 : Colors.white24),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isConnecting
                              ? "CONNEXION..."
                              : isConnected
                                  ? "CONNECTÉ"
                                  : (srv != null ? "ACTIVER" : "AUCUN ACCÈS"),
                          style: TextStyle(
                            color: isConnected ? cyberGreen : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          Text(
            _formatTimer(_connectionDurationSeconds),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("IP TUNNEL : ", style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text(isConnected ? _virtualIp : "EN VEILLE", style: const TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              const Text("• HWID : ", style: TextStyle(color: Colors.white38, fontSize: 10)),
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
                      const Row(
                        children: [
                          Icon(Icons.pie_chart, color: cyberGreen, size: 14),
                          SizedBox(width: 4),
                          Text("GIGAS UTILISÉS / QUOTA", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text(
                        "${usedGb.toStringAsFixed(2)} Go / ${totalGb.toStringAsFixed(1)} Go (${usedPercent.toInt()}%)",
                        style: const TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: totalGb > 0 ? (usedPercent / 100.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: Colors.black45,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usedPercent > 85 ? cyberRed : usedPercent > 60 ? cyberYellow : cyberGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Restant: ${(totalGb - usedGb).toStringAsFixed(2)} Go", style: const TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text("Expire : $remainingDays", style: const TextStyle(color: Colors.white60, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.arrow_downward, color: cyberCyan, size: 14),
                          SizedBox(width: 4),
                          Text("DÉBIT DL", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isConnected ? "${_currentDownloadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Total: ${_totalDownloadMb.toStringAsFixed(1)} Mo",
                        style: const TextStyle(color: Colors.white38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.arrow_upward, color: cyberGreen, size: 14),
                          SizedBox(width: 4),
                          Text("DÉBIT UL", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isConnected ? "${_currentUploadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Total: ${_totalUploadMb.toStringAsFixed(1)} Mo",
                        style: const TextStyle(color: Colors.white38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.wifi, color: cyberYellow, size: 14),
                          SizedBox(width: 4),
                          Text("PING MS", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentPingMs > 0 ? '$_currentPingMs ms' : '—',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const Text(
                        "Serv. Maître",
                        style: TextStyle(color: Colors.white38, fontSize: 8),
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
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("MONITEUR BANDE PASSANTE TEMPS RÉEL", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Icon(Icons.circle, color: cyberCyan, size: 8),
                        SizedBox(width: 4),
                        Text("Download", style: TextStyle(color: Colors.white60, fontSize: 9)),
                        SizedBox(width: 8),
                        Icon(Icons.circle, color: cyberGreen, size: 8),
                        SizedBox(width: 4),
                        Text("Upload", style: TextStyle(color: Colors.white60, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 100,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _speedHistoryDownload,
                          isCurved: true,
                          color: cyberCyan,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: cyberCyan.withOpacity( 0.12)),
                        ),
                        LineChartBarData(
                          spots: _speedHistoryUpload,
                          isCurved: true,
                          color: cyberGreen,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
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
  // ONGLET 2 : STUDIO SERVEURS, TOKENS & MODE MULTI-PROTOCOLES (ZERO-TOKEN)
  // ==========================================================================
  Widget _buildTab2ProtocolsAndTokens(ImportedVpnServer? srv) {
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
              border: Border.all(color: cyberGreen.withOpacity( 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.vpn_key, color: cyberGreen, size: 18),
                    SizedBox(width: 8),
                    Text("ACTIVATION PAR CLÉ TOKEN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text("Saisissez votre code licence fourni par votre revendeur officiel pour activer votre accès sécurisé.", style: TextStyle(color: Colors.white60, fontSize: 10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tokenInputCtrl,
                        style: const TextStyle(color: cyberGreen, fontFamily: "monospace", fontSize: 12),
                        decoration: InputDecoration(
                          hintText: "EX: ABESS-VIP-ROOT-2026",
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                          filled: true,
                          fillColor: const Color(0xFF030712),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cyberGreen.withOpacity( 0.4))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: cyberGreen)),
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

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cyberCyan.withOpacity( 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune, color: cyberCyan, size: 18),
                        SizedBox(width: 8),
                        Text("MODE SANS TOKEN (MULTI-PROTOCOLES)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cyberCyan.withOpacity( 0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Text("AUTONOME", style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text("En cas d'absence de token, configurez directement vos paramètres de connexion pour n'importe quel protocole et transport.", style: TextStyle(color: Colors.white60, fontSize: 10)),
                const SizedBox(height: 14),

                const Text("PROTOCOLE RÉSEAU", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildProtocolChip("vless", "VLESS (Recommandé)"),
                    const SizedBox(width: 6),
                    _buildProtocolChip("vmess", "VMess"),
                    const SizedBox(width: 6),
                    _buildProtocolChip("trojan", "Trojan"),
                    const SizedBox(width: 6),
                    _buildProtocolChip("shadowsocks", "Shadowsocks"),
                  ],
                ),
                const SizedBox(height: 12),

                const Text("TRANSPORT STREAM", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildTransportChip("ws", "WebSocket"),
                    const SizedBox(width: 6),
                    _buildTransportChip("grpc", "gRPC"),
                    const SizedBox(width: 6),
                    _buildTransportChip("httpupgrade", "HTTPUpgrade"),
                    const SizedBox(width: 6),
                    _buildTransportChip("xhttp", "XHTTP"),
                  ],
                ),
                if (_customProtocol == "shadowsocks") ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTransportChip("native", "TCP + UDP natifs"),
                      const Expanded(child: SizedBox()),
                      const Expanded(child: SizedBox()),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildFormField("Hôte / Domaine / IP", _customHostCtrl, "ex: konoyves.shop"),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: _buildFormField("Port", _customPortCtrl, "443"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _buildFormField("Chemin WebSocket / xHTTP", _customPathCtrl, "/@abess237"),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFormField("SNI Bug Host (Zero-Rating)", _customSniCtrl, "crashlyticsreports-pa.googleapis.com"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Identifiant UUID / Mot de passe", style: TextStyle(color: Colors.white60, fontSize: 10)),
                        GestureDetector(
                          onTap: _generateRandomUuid,
                          child: const Text("Générer UUID Aléatoire", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _customUuidCtrl,
                      style: const TextStyle(color: cyberCyan, fontFamily: "monospace", fontSize: 11),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF030712),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                ElevatedButton.icon(
                  onPressed: _saveCustomServerManual,
                  icon: const Icon(Icons.flash_on, color: Colors.black, size: 16),
                  label: const Text("ACTIVER CE SERVEUR PERSONNEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cyberCyan,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("IMPORTATION RAPIDE PAR LIEN BRUT", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text("Collez un lien vless://, vmess://, trojan:// ou ss:// généré par un autre outil.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rawLinkInputCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: "monospace"),
                        decoration: InputDecoration(
                          hintText: "Coller vless://... ou vmess://...",
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 10),
                          filled: true,
                          fillColor: const Color(0xFF030712),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_rawLinkInputCtrl.text.isNotEmpty) {
                          _parseUniversalRawLink(_rawLinkInputCtrl.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("IMPORTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ONGLET 3 : OUTILS, STABILITÉ & LOGS EN DIRECT
  // ==========================================================================
  Widget _buildTab3ToolsAndStability(ImportedVpnServer? srv) {
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
                    const Row(
                      children: [
                        Icon(Icons.speed, color: cyberCyan, size: 18),
                        SizedBox(width: 8),
                        Text("SPEED TEST CYBER INTÉGRÉ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                      child: const Text("TESTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text("Mesure en direct la latence (ping) et le débit montant/descendant vers les serveurs maîtres.", style: TextStyle(color: Colors.white60, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("PARAMÈTRES DE PERFORMANCE & STABILITÉ", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isMuxEnabled,
                  onChanged: (val) => setState(() => _isMuxEnabled = val),
                  activeTrackColor: cyberGreen,
                  title: const Text("Multiplexage TCP (Mux)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Réutilise la même connexion TCP pour charger les pages 2x plus vite.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ),
                const Divider(color: Colors.white12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isKillSwitchEnabled,
                  onChanged: (val) => setState(() => isKillSwitchEnabled = val),
                  activeTrackColor: cyberRed,
                  title: const Text("Kill Switch Anti-Fuite", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Coupe automatiquement le trafic si le tunnel VPN se déconnecte.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ),
                const Divider(color: Colors.white12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isAutoReconnectEnabled,
                  onChanged: (val) => setState(() => isAutoReconnectEnabled = val),
                  activeTrackColor: cyberYellow,
                  title: const Text("Reconnexion Automatique", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Tente de reconnecter le VPN automatiquement en cas de perte de réseau.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal, color: cyberGreen, size: 14),
                        SizedBox(width: 4),
                        Text("JOURNAL SYSTÈME V2RAY", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _logs.clear()),
                      child: const Text("Effacer", style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF030712),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (ctx, idx) => Text(
                      _logs[idx],
                      style: const TextStyle(color: cyberGreen, fontSize: 9, fontFamily: "monospace"),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

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
                    const Icon(Icons.support_agent, color: cyberGreen, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("ASSISTANCE TECHNIQUE DIRECTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 2),
                          Text("WhatsApp : $_whatsappSupportPhone", style: TextStyle(color: Colors.white60, fontSize: 10)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openUrlSafe(_whatsappSupportUrl),
                      icon: const Icon(Icons.chat, color: Colors.black, size: 14),
                      label: const Text("CHAT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                      style: ElevatedButton.styleFrom(backgroundColor: cyberGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openUrlSafe(_whatsappCommunityUrl),
                  icon: const Icon(Icons.groups, color: cyberCyan, size: 16),
                  label: const Text("REJOINDRE LA COMMUNAUTÉ WHATSAPP", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cyberCyan),
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

  Widget _buildProtocolChip(String id, String label) {
    final isSelected = _customProtocol == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _customProtocol = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyberCyan.withOpacity( 0.25) : const Color(0xFF030712),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cyberCyan : Colors.white12),
          ),
          child: Center(
            child: Text(
              label.split(" ")[0],
              style: TextStyle(
                color: isSelected ? cyberCyan : Colors.white60,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransportChip(String id, String label) {
    final isSelected = _customTransport == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _customTransport = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyberGreen.withOpacity( 0.25) : const Color(0xFF030712),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cyberGreen : Colors.white12),
          ),
          child: Center(
            child: Text(
              label.split(" ")[0],
              style: TextStyle(
                color: isSelected ? cyberGreen : Colors.white60,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: "monospace"),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
            filled: true,
            fillColor: const Color(0xFF030712),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
          ),
        ),
      ],
    );
  }
}

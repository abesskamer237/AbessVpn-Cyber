import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';

final ValueNotifier<bool> abessDarkMode = ValueNotifier<bool>(true);

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

class AbessVpnApp extends StatelessWidget {
  const AbessVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: abessDarkMode,
      builder: (context, isDarkMode, _) {
        final brightness = isDarkMode ? Brightness.dark : Brightness.light;
        return MaterialApp(
          title: 'AbessVpn',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: brightness,
            scaffoldBackgroundColor: isDarkMode ? const Color(0xFF030712) : const Color(0xFFF1F5F9),
            primaryColor: isDarkMode ? const Color(0xFF10B981) : const Color(0xFF047857),
            colorScheme: ColorScheme.fromSeed(
              seedColor: isDarkMode ? const Color(0xFF10B981) : const Color(0xFF047857),
              brightness: brightness,
            ),
            textTheme: GoogleFonts.orbitronTextTheme(
              (isDarkMode ? ThemeData.dark() : ThemeData.light()).textTheme,
            ),
          ),
          home: MainVpnScreen(),
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

class _MainVpnScreenState extends State<MainVpnScreen> with SingleTickerProviderStateMixin {
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

  // 4 ONGLETS CYBER NAVIGATION
  int _currentNavIndex = 0;
  bool _isMuxEnabled = true;

  // MODE MULTI-PROTOCOLES AUTONOME (SANS TOKEN)
  String _customProtocol = "vless";
  String _customTransport = "ws";
  bool _customTlsEnabled = true;
  final TextEditingController _customHostCtrl = TextEditingController();
  final TextEditingController _customWsHostCtrl = TextEditingController();
  final TextEditingController _customPortCtrl = TextEditingController(text: "443");
  final TextEditingController _customPathCtrl = TextEditingController(text: "/@abess237");
  final TextEditingController _customUuidCtrl = TextEditingController();
  final TextEditingController _customSniCtrl = TextEditingController();
  final TextEditingController _customNameCtrl = TextEditingController(text: "Serveur Cyber Personnalisé");
  final TextEditingController _rawLinkInputCtrl = TextEditingController();

  String _newUuid() {
    final rand = math.Random.secure();
    String s(int len) => List.generate(len, (_) => rand.nextInt(16).toRadixString(16)).join();
    return "${s(8)}-${s(4)}-4${s(3)}-${(8 + rand.nextInt(4)).toRadixString(16)}${s(3)}-${s(12)}";
  }

  void _generateRandomUuid() {
    setState(() => _customUuidCtrl.text = _newUuid());
    _showToast("Nouvel UUID conforme généré !");
  }

  ImportedVpnServer? _manualProfileFromFields() {
    final host = _customHostCtrl.text.trim();
    if (host.isEmpty) {
      _showToast("Adresse requise");
      return null;
    }
    final port = int.tryParse(_customPortCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _showToast("Port invalide");
      return null;
    }
    if (_customUuidCtrl.text.trim().isEmpty) _customUuidCtrl.text = _newUuid();
    final uuid = _customUuidCtrl.text.trim();
    final path = _customPathCtrl.text.trim().isEmpty ? "/@abess237" : _customPathCtrl.text.trim();
    final sni = _customSniCtrl.text.trim().isEmpty ? host : _customSniCtrl.text.trim();
    final name = _customNameCtrl.text.trim().isEmpty
        ? "Custom ($_customProtocol/$_customTransport)"
        : _customNameCtrl.text.trim();
    final isDirect = {'native', 'raw', 'tcp', 'kcp', 'mkcp'}.contains(_customTransport);
    if (_customProtocol == 'trojan' && (isDirect || !_customTlsEnabled)) {
      _showToast("Trojan nécessite TLS");
      return null;
    }
    if (_customProtocol == 'shadowsocks' && _customTransport != 'native') {
      _showToast("Shadowsocks utilise TCP + UDP natifs");
      return null;
    }
    return ImportedVpnServer(
      name: name,
      address: host,
      port: port,
      path: path,
      sni: sni,
      uuid: uuid,
      protocol: _customProtocol,
      transport: _customTransport,
      tls: _customTlsEnabled && !isDirect,
      wsHost: _customWsHostCtrl.text.trim(),
      bandwidthGb: 999.0,
      bandwidthUsedGb: 0.0,
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      token: "CUSTOM-ZERO-TOKEN",
    );
  }

  void _saveCustomServerManual() {
    final customSrv = _manualProfileFromFields();
    if (customSrv == null) return;
    unawaited(_storeAndSelectServer(customSrv, switchToConnection: true));
    _addLog("CONFIG MANUELLE : ${customSrv.protocol.toUpperCase()} / ${customSrv.transport.toUpperCase()}");
    _showToast("Configuration enregistrée");
  }

  String _localAbessProfileLink(
    ImportedVpnServer server, {
    required double quotaGb,
    required DateTime expiresAt,
    required String allowedDeviceId,
  }) {
    final payload = jsonEncode({
      'v': 2,
      'licenseId': 'manual-${DateTime.now().microsecondsSinceEpoch}-${_newUuid()}',
      'name': server.name,
      'address': server.address,
      'port': server.port,
      'path': server.path,
      'sni': server.sni,
      'uuid': server.uuid,
      'protocol': server.protocol,
      'transport': server.transport,
      'tls': server.tls,
      'method': server.method,
      'wsHost': server.wsHost,
      'bandwidthGb': quotaGb,
      'bandwidthUsedGb': 0,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'allowedDeviceId': allowedDeviceId.trim(),
    });
    final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    return 'abess://profile.$encoded';
  }

  Future<Map<String, dynamic>?> _promptManualExportOptions() async {
    if (_deviceId.isEmpty) await _initDeviceId();
    final quotaController = TextEditingController(text: '10');
    final deviceController = TextEditingController();
    var expiresAt = DateTime.now().add(const Duration(days: 30));
    String? validationError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: cyberCardBg,
          title: Text('Créer un accès ABESS limité', style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Définis le quota, la date et l’heure d’expiration ainsi que l’installation autorisée avant de générer le lien ou le fichier.', style: TextStyle(color: _text70, fontSize: 11, height: 1.35)),
                const SizedBox(height: 14),
                Text('Quota de données (Go)', style: TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                TextField(
                  controller: quotaController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: _textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Ex. 10',
                    filled: true,
                    fillColor: _fieldBackgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Expiration (date et heure locales)', style: TextStyle(color: cyberYellow, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final selectedDate = await showDatePicker(
                        context: dialogContext,
                        initialDate: expiresAt.isAfter(now) ? expiresAt : now.add(const Duration(days: 1)),
                        firstDate: DateTime(now.year, now.month, now.day),
                        lastDate: DateTime(now.year + 10, now.month, now.day),
                      );
                      if (selectedDate == null || !dialogContext.mounted) return;
                      final selectedTime = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(expiresAt),
                      );
                      if (selectedTime == null) return;
                      setDialogState(() {
                        expiresAt = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, selectedTime.hour, selectedTime.minute);
                        validationError = null;
                      });
                    },
                    icon: Icon(Icons.event, size: 16, color: cyberYellow),
                    label: Text('${expiresAt.toLocal().toString().substring(0, 16)}', style: TextStyle(color: _textPrimary, fontSize: 11)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('ID d’installation autorisée', style: TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                TextField(
                  controller: deviceController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: cyberCyan, fontFamily: 'monospace', fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'Coller l’ID du téléphone destinataire',
                    filled: true,
                    fillColor: _fieldBackgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 5),
                Text('Le destinataire trouve cet identifiant dans Mode manuel → ID d’installation, puis te l’envoie. Le lien sera refusé par ABESS VPN sur une autre installation.', style: TextStyle(color: _text54, fontSize: 10, height: 1.3)),
                const SizedBox(height: 8),
                Text('Limite technique : un profil manuel est contrôlé par l’application locale. Pour une licence suivie côté serveur, utilise aussi le panel et renseigne le même ID dans le champ de verrouillage de la licence.', style: TextStyle(color: _text38, fontSize: 9, height: 1.3)),
                if (validationError != null) ...[
                  const SizedBox(height: 10),
                  Text(validationError!, style: const TextStyle(color: cyberRed, fontSize: 11)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text('Annuler', style: TextStyle(color: _text60))),
            ElevatedButton(
              onPressed: () {
                final quota = double.tryParse(quotaController.text.trim().replaceAll(',', '.'));
                final deviceId = deviceController.text.trim();
                if (quota == null || !quota.isFinite || quota <= 0 || quota > 100000) {
                  setDialogState(() => validationError = 'Le quota doit être supérieur à 0 et ne pas dépasser 100000 Go.');
                  return;
                }
                if (!expiresAt.isAfter(DateTime.now())) {
                  setDialogState(() => validationError = 'Choisis une date et une heure futures.');
                  return;
                }
                if (deviceId.length < 8 || deviceId.length > 128 || RegExp(r'\s').hasMatch(deviceId)) {
                  setDialogState(() => validationError = 'L’ID doit contenir 8 à 128 caractères sans espace.');
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'bandwidthGb': quota,
                  'expiresAt': expiresAt,
                  'allowedDeviceId': deviceId,
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: cyberGreen, foregroundColor: Colors.black),
              child: const Text('Continuer', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    quotaController.dispose();
    deviceController.dispose();
    return result;
  }

  Future<void> _copyManualProfileLink() async {
    final server = _manualProfileFromFields();
    if (server == null) return;
    final options = await _promptManualExportOptions();
    if (options == null) return;
    final link = _localAbessProfileLink(
      server,
      quotaGb: options['bandwidthGb'] as double,
      expiresAt: options['expiresAt'] as DateTime,
      allowedDeviceId: options['allowedDeviceId'] as String,
    );
    await Clipboard.setData(ClipboardData(text: link));
    _showToast('Lien ABESS limité généré et copié.');
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

  Future<void> _exportManualProfileFile() async {
    final server = _manualProfileFromFields();
    if (server == null) return;
    final options = await _promptManualExportOptions();
    if (options == null) return;
    try {
      final link = _localAbessProfileLink(
        server,
        quotaGb: options['bandwidthGb'] as double,
        expiresAt: options['expiresAt'] as DateTime,
        allowedDeviceId: options['allowedDeviceId'] as String,
      );
      final safeName = server.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${safeName.isEmpty ? 'abess-profile' : safeName}.abess');
      await file.writeAsString('$link\n', flush: true);
      await Share.shareXFiles([XFile(file.path)], text: '${server.name} • ${options['bandwidthGb']} Go', subject: 'Configuration ABESS VPN limitée');
    } catch (error) {
      _addLog('EXPORT .ABESS ÉCHOUÉ : $error');
      _showToast("Export impossible");
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

      _showToast('Format inconnu. Utilisez vless://, vmess://, trojan:// ou ss://.');
    } catch (e) {
      _addLog('ÉCHEC IMPORT LIEN : ' + e.toString());
      _showToast('Lien invalide ou transport non pris en charge.');
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

  // The control-plane address is supplied at build time; no legacy demo hosts are used.
  final List<String> _masterServerUrls = _configuredApiBaseUrl.trim().isNotEmpty
      ? [_configuredApiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '')]
      : const <String>[];

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
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
    _customWsHostCtrl.dispose();
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

  Future<void> _persistProfileState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedProfilesKey,
      jsonEncode(savedServers.map(_serverToJsonMap).toList()),
    );
    if (currentServer == null) {
      await prefs.remove(_selectedProfileKey);
      await prefs.remove('abess_imported_server');
    } else {
      await prefs.setString(_selectedProfileKey, currentServer!.id);
      // Keep the legacy key in sync so older builds can still recover the active profile.
      await prefs.setString('abess_imported_server', jsonEncode(_serverToJsonMap(currentServer!)));
    }
  }

  Future<void> _loadSavedServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isKillSwitchEnabled = prefs.getBool('abess_kill_switch') ?? true;
      isAutoReconnectEnabled = prefs.getBool('abess_auto_reconnect') ?? true;
    });

    final loaded = <ImportedVpnServer>[];
    final storedList = prefs.getString(_savedProfilesKey);
    try {
      if (storedList != null) {
        final decoded = jsonDecode(storedList);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final server = _serverFromJsonMap(Map<String, dynamic>.from(item));
              if (server.address.isNotEmpty && server.uuid.isNotEmpty) loaded.add(server);
            }
          }
        }
      } else {
        // One-time migration from the previous single-profile storage key.
        final legacy = prefs.getString('abess_imported_server');
        if (legacy != null) {
          final decoded = jsonDecode(legacy);
          if (decoded is Map) {
            final server = _serverFromJsonMap(Map<String, dynamic>.from(decoded));
            if (server.address.isNotEmpty && server.uuid.isNotEmpty) loaded.add(server);
          }
        }
      }
    } catch (error) {
      _addLog('PROFILS SAUVEGARDÉS ILLISIBLES : $error');
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
    if (storedList == null && loaded.isNotEmpty) await _persistProfileState();
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

  Widget _buildSavedProfilesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cyberCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cyberCyan.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, color: cyberCyan, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('MES CONFIGURATIONS', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
              ),
              Text('${savedServers.length}', style: TextStyle(color: cyberCyan, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          if (savedServers.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucune configuration enregistrée. Ajoutez un token ou importez un lien ci-dessous.', style: TextStyle(color: _text54, fontSize: 10)),
            )
          else
            ...savedServers.map((profile) {
              final selected = currentServer?.id == profile.id;
              return Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: selected ? cyberGreen.withOpacity(0.10) : _fieldBackgroundColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? cyberGreen : _text12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => unawaited(_selectSavedServer(profile)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? cyberGreen : _text38, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? cyberGreen : _textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 3),
                                    Text('${profile.protocol.toUpperCase()} · ${profile.transport.toUpperCase()} · ${profile.tls ? "TLS" : "sans TLS"} · ${profile.address}:${profile.port}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _text54, fontSize: 9)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Supprimer cette configuration',
                      onPressed: () => unawaited(_deleteSavedServer(profile)),
                      icon: Icon(Icons.delete_outline, color: cyberRed, size: 19),
                    ),
                  ],
                ),
              );
            }),
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
            ? 'ACCÈS MANUEL EXPIRÉ : DÉCONNEXION AUTOMATIQUE'
            : 'QUOTA MANUEL ÉPUISÉ : DÉCONNEXION AUTOMATIQUE');
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
    const supportedProtocols = {'vless', 'vmess', 'trojan', 'shadowsocks'};
    const supportedTransports = {'ws', 'grpc', 'httpupgrade', 'xhttp', 'raw', 'tcp', 'kcp', 'mkcp', 'native'};

    if (!supportedProtocols.contains(protocol) || !supportedTransports.contains(transport)) {
      throw UnsupportedError(
        'Configuration non prise en charge : ${protocol.toUpperCase()} + ${transport.toUpperCase()}.',
      );
    }
    if (transport == 'native' && protocol != 'shadowsocks') {
      throw UnsupportedError('Le mode TCP + UDP natif est disponible uniquement avec Shadowsocks.');
    }
    if (protocol == 'shadowsocks' && transport != 'native') {
      throw UnsupportedError('Pour avoir TCP et UDP avec Shadowsocks, sélectionne le transport natif sur le port 10050.');
    }
    final effectiveTransport = transport == 'tcp' ? 'raw' : (transport == 'mkcp' ? 'kcp' : transport);
    if ((effectiveTransport == 'raw' || effectiveTransport == 'kcp') && protocol != 'vmess' && srv.token != 'RAW-LINK-IMPORT') {
      throw UnsupportedError('RAW/TCP et mKCP/UDP sont réservés à VMess sur le serveur ABESS.');
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
      default:
        throw UnsupportedError('Protocole non pris en charge.');
    }

    final Map<String, dynamic>? streamSettings;
    if (transport == 'native') {
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
    if (_isMuxEnabled && !{'native', 'grpc', 'kcp'}.contains(effectiveTransport)) {
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
      // Résolveurs publics rapides avec repli. Ceci améliore surtout le temps
      // de résolution des noms ; cela n'augmente pas directement le débit brut.
      'dns': {
        'servers': ['1.1.1.1', '1.0.0.1', '8.8.8.8'],
        'queryStrategy': 'UseIP'
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
      ],
      // Si le moteur reçoit les requêtes DNS via son routage, privilégier
      // le tunnel proxy plutôt qu'une sortie directe.
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'type': 'field',
            'network': 'tcp,udp',
            'port': '53',
            'outboundTag': 'proxy'
          }
        ]
      }
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
        ).timeout(Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['valid'] == true) {
            final srvConf = data['serverConfig'] ?? {};
            final newServer = ImportedVpnServer(
              name: data['plan'] ?? 'ABESS VIP MASTER',
              address: srvConf['address']?.toString() ?? '',
              port: srvConf['port'] ?? 443,
              path: srvConf['path'] ?? '/@abess237',
              sni: srvConf['sni']?.toString() ?? (srvConf['address']?.toString() ?? ''),
              uuid: srvConf['uuid']?.toString() ?? '',
              protocol: (srvConf['protocol'] as String?) ?? 'vless',
              transport: (srvConf['transport'] as String?) ?? 'ws',
              allowedDeviceId: srvConf['allowedDeviceId']?.toString(),
              tls: (srvConf['security']?.toString().toLowerCase() ?? 'tls') != 'none',
              method: (srvConf['method'] as String?) ?? 'aes-128-gcm',
              wsHost: (srvConf['host'] ?? srvConf['wsHost'])?.toString() ?? '',
              bandwidthGb: (data['bandwidthGb'] as num?)?.toDouble() ?? 10.0,
              bandwidthUsedGb: (data['bandwidthUsedGb'] as num?)?.toDouble() ?? 0.0,
              expiresAt: DateTime.tryParse(data['expiresAt'] ?? '') ?? DateTime.now().add(Duration(days: 30)),
              token: cleanToken,
              deviceLimit: data['deviceLimit'] ?? 1,
            );
            final apiTlsHost = Uri.tryParse(_configuredApiBaseUrl)?.host.toLowerCase() ?? '';
            const tlsWebTransports = {'ws', 'grpc', 'httpupgrade', 'xhttp'};
            if (newServer.tls &&
                tlsWebTransports.contains(newServer.transport.toLowerCase()) &&
                apiTlsHost.isNotEmpty &&
                newServer.sni.toLowerCase() != apiTlsHost) {
              _addLog('ALERTE TLS : SNI ${newServer.sni} différent du domaine HTTPS ${apiTlsHost}. Le certificat peut être refusé et aucun trafic ne passera. Recréez le profil avec le SNI couvert par le certificat.');
            }
            _addLog('PROFIL IMPORTÉ : ${newServer.address}:${newServer.port} • ${newServer.protocol.toUpperCase()}/${newServer.transport.toUpperCase()} • Host HTTP : ${newServer.wsHost.isEmpty ? '(destination)' : newServer.wsHost} • SNI : ${newServer.sni}');
            await _storeAndSelectServer(newServer);
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
            sni: srvConf['sni']?.toString() ?? '',
            uuid: srvConf['uuid']?.toString() ?? '',
            protocol: srvConf['protocol']?.toString() ?? 'vless',
            transport: srvConf['transport']?.toString() ?? 'ws',
            allowedDeviceId: srvConf['allowedDeviceId']?.toString(),
            tls: (srvConf['security']?.toString().toLowerCase() ?? 'tls') != 'none',
            method: srvConf['method']?.toString() ?? 'aes-128-gcm',
            wsHost: (srvConf['host'] ?? srvConf['wsHost'])?.toString() ?? '',
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
    _createTokenCodeCtrl.text = 'ABESS-VIP-${math.Random().nextInt(8999) + 1000}';
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
                Text('2. CODE TOKEN', style: TextStyle(color: _text70, fontSize: 10)),
                SizedBox(height: 4),
                TextField(
                  controller: _createTokenCodeCtrl,
                  style: TextStyle(color: cyberGreen, fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _fieldFillColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                color: cyberGreen.withOpacity( 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cyberGreen.withOpacity( 0.4)),
              ),
              child: Icon(Icons.shield, color: cyberGreen, size: 20),
            ),
            SizedBox(width: 10),
            Text(
              _currentNavIndex == 0
                  ? "AbessVpn Cyber"
                  : _currentNavIndex == 1
                      ? "Serveurs & Tokens"
                      : _currentNavIndex == 2
                          ? "Mode manuel"
                          : "Outils & Diagnostic",
              style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _openUrlSafe(_whatsappSupportUrl),
            icon: Icon(Icons.chat_bubble_outline, color: cyberGreen),
            tooltip: "Support WhatsApp ($_whatsappSupportPhone)",
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
          IconButton(
            onPressed: _showSpeedTestModal,
            icon: Icon(Icons.speed, color: cyberCyan),
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
            _buildTab3ManualProfiles(srv),
            _buildTab4ToolsAndStability(srv),
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
          unselectedItemColor: _text38,
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
              icon: Icon(Icons.tune_outlined),
              activeIcon: Icon(Icons.tune, color: cyberCyan),
              label: "Manuel",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed_outlined),
              activeIcon: Icon(Icons.speed, color: cyberGreen),
              label: "Outils",
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
                  Icon(Icons.info_outline, color: cyberCyan, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("AUCUN SERVEUR CONFIGURÉ", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 2),
                        Text("Importez un token ou configurez un serveur dans l'onglet Serveurs.", style: TextStyle(color: _text60, fontSize: 10)),
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
                    child: Text("CONFIGURER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
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
                        Text("SERVEUR ACTIF IMPORTÉ", style: TextStyle(color: _text54, fontSize: 9, letterSpacing: 1.2)),
                        SizedBox(height: 2),
                        Text(
                          srv.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          "${srv.protocol.toUpperCase()} • ${srv.transport.toUpperCase()} • ${srv.tls ? "TLS activé" : "TLS non utilisé"}",
                          style: TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentNavIndex = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _softSurfaceFill,
                      foregroundColor: cyberGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: cyberGreen),
                      ),
                    ),
                    child: Text("CHANGER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
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
                  SizedBox(width: 10),
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
                    child: Text("RECHARGER", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
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
                        ? Color.lerp(Color(0xFF042F24), Color(0xFF064E3B), pulseVal)
                        : Color(0xFF0B132B),
                    border: Border.all(
                      color: isConnected ? cyberGreen : _text24,
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
                          color: isConnected ? cyberGreen : (srv != null ? _text70 : _text24),
                        ),
                        SizedBox(height: 6),
                        Text(
                          isConnecting
                              ? "CONNEXION..."
                              : isConnected
                                  ? "CONNECTÉ"
                                  : (srv != null ? "ACTIVER" : "AUCUN ACCÈS"),
                          style: TextStyle(
                            color: isConnected ? cyberGreen : _text70,
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
          SizedBox(height: 12),

          Text(
            _formatTimer(_connectionDurationSeconds),
            style: TextStyle(color: _textPrimary, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("IP TUNNEL : ", style: TextStyle(color: _text38, fontSize: 10)),
              Text(isConnected ? _virtualIp : "EN VEILLE", style: TextStyle(color: cyberGreen, fontSize: 10, fontWeight: FontWeight.bold)),
              SizedBox(width: 10),
              Text("• HWID : ", style: TextStyle(color: _text38, fontSize: 10)),
              Text(
                _deviceId.length > 10 ? "${_deviceId.substring(0, 10)}..." : _deviceId,
                style: TextStyle(color: cyberCyan, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 16),

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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _text10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_downward, color: cyberCyan, size: 14),
                          SizedBox(width: 4),
                          Text("DÉBIT DL", style: TextStyle(color: _text54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        isConnected ? "${_currentDownloadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                        style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Total: ${_totalDownloadMb.toStringAsFixed(1)} Mo",
                        style: TextStyle(color: _text38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _text10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_upward, color: cyberGreen, size: 14),
                          SizedBox(width: 4),
                          Text("DÉBIT UL", style: TextStyle(color: _text54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        isConnected ? "${_currentUploadSpeed.toStringAsFixed(2)} Mo/s" : "0.00 Mo/s",
                        style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Total: ${_totalUploadMb.toStringAsFixed(1)} Mo",
                        style: TextStyle(color: _text38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _text10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.wifi, color: cyberYellow, size: 14),
                          SizedBox(width: 4),
                          Text("PING MS", style: TextStyle(color: _text54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        _currentPingMs > 0 ? '$_currentPingMs ms' : '—',
                        style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        "Serv. Maître",
                        style: TextStyle(color: _text38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),

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
  // ONGLET 2 : SERVEURS & TOKENS
  // ==========================================================================
  Widget _buildTab2ProtocolsAndTokens(ImportedVpnServer? srv) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSavedProfilesSection(),
          SizedBox(height: 16),
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
                Row(
                  children: [
                    Icon(Icons.vpn_key, color: cyberGreen, size: 18),
                    SizedBox(width: 8),
                    Text("ACTIVATION PAR CLÉ TOKEN", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                  ],
                ),
                SizedBox(height: 6),
                Text("Saisissez votre code licence fourni par votre revendeur officiel pour activer votre accès sécurisé.", style: TextStyle(color: _text60, fontSize: 10)),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tokenInputCtrl,
                        style: TextStyle(color: cyberGreen, fontFamily: "monospace", fontSize: 12),
                        decoration: InputDecoration(
                          hintText: "EX: ABESS-VIP-ROOT-2026",
                          hintStyle: TextStyle(color: _text30, fontSize: 11),
                          filled: true,
                          fillColor: _fieldBackgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cyberGreen.withOpacity( 0.4))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _text24)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cyberGreen)),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
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
                      child: Text("VALIDER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _claimFreeTrial,
                  icon: Icon(Icons.bolt, color: cyberYellow, size: 16),
                  label: Text("RÉCLAMER MON ESSAI GRATUIT 1 GO / 24H", style: TextStyle(color: cyberYellow, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cyberYellow),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

        ],
      ),
    );
  }

  // ONGLET 3 : CONFIGURATION MANUELLE
  Widget _buildTab3ManualProfiles(ImportedVpnServer? srv) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyberCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cyberGreen.withOpacity(0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phonelink_lock, color: cyberGreen, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text("ID D’INSTALLATION ABESS", style: TextStyle(color: cyberGreen, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5))),
                    IconButton(
                      tooltip: "Copier l’ID d’installation",
                      onPressed: _deviceId.isEmpty ? null : () async {
                        await Clipboard.setData(ClipboardData(text: _deviceId));
                        _showToast("ID d’installation copié");
                      },
                      icon: Icon(Icons.copy, color: cyberCyan, size: 18),
                    ),
                  ],
                ),
                SelectableText(
                  _deviceId.isEmpty ? "Initialisation…" : _deviceId,
                  style: TextStyle(color: _textPrimary, fontFamily: "monospace", fontSize: 12, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Text("Pour limiter un lien .abess à un téléphone précis, copie cet ID depuis le téléphone destinataire et colle-le dans le champ « ID d’installation autorisée » lors de l’export.", style: TextStyle(color: _text60, fontSize: 10, height: 1.35)),
                SizedBox(height: 4),
                Text("C’est un identifiant ABESS propre à l’installation de l’application, pas l’IMEI matériel du téléphone.", style: TextStyle(color: _text38, fontSize: 9, height: 1.3)),
              ],
            ),
          ),
          SizedBox(height: 12),
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
                    Row(
                      children: [
                        Icon(Icons.tune, color: cyberCyan, size: 18),
                        SizedBox(width: 8),
                        Text("MODE SANS TOKEN (MULTI-PROTOCOLES)", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cyberCyan.withOpacity( 0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text("AUTONOME", style: TextStyle(color: cyberCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                SizedBox(height: 14),

                Text("PROTOCOLE RÉSEAU", style: TextStyle(color: _text70, fontSize: 10, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Row(
                  children: [
                    _buildProtocolChip("vless", "VLESS (Recommandé)"),
                    SizedBox(width: 6),
                    _buildProtocolChip("vmess", "VMess"),
                    SizedBox(width: 6),
                    _buildProtocolChip("trojan", "Trojan"),
                    SizedBox(width: 6),
                    _buildProtocolChip("shadowsocks", "Shadowsocks"),
                  ],
                ),
                SizedBox(height: 12),

                Text("TRANSPORT STREAM", style: TextStyle(color: _text70, fontSize: 10, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                if (_customProtocol != "shadowsocks")
                  Row(
                    children: [
                      _buildTransportChip("ws", "WebSocket"),
                      SizedBox(width: 6),
                      _buildTransportChip("grpc", "gRPC"),
                      SizedBox(width: 6),
                      _buildTransportChip("httpupgrade", "HTTPUpgrade"),
                      SizedBox(width: 6),
                      _buildTransportChip("xhttp", "XHTTP"),
                    ],
                  ),
                if (_customProtocol == "vmess") ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTransportChip("raw", "RAW / TCP 10060"),
                      SizedBox(width: 6),
                      _buildTransportChip("kcp", "mKCP / UDP 10061"),
                      Expanded(child: SizedBox()),
                      Expanded(child: SizedBox()),
                    ],
                  ),
                ],
                if (_customProtocol == "shadowsocks") ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTransportChip("native", "TCP + UDP natifs"),
                      Expanded(child: SizedBox()),
                      Expanded(child: SizedBox()),
                      Expanded(child: SizedBox()),
                    ],
                  ),
                ],
                SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cyberGreen.withOpacity(0.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "ADRESSE DE DESTINATION — DOMAINE/IP + PORT",
                        style: TextStyle(color: cyberGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.7),
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildFormField("Domaine/IP de destination", _customHostCtrl, "vpn.ton-domaine.com"),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: _buildFormField("Port", _customPortCtrl, "443"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberCyan.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cyberCyan.withOpacity(0.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "HOST HTTP",
                        style: TextStyle(color: cyberCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.7),
                      ),
                      SizedBox(height: 4),
                      SizedBox(height: 10),
                      _buildFormField("Host HTTP / WebSocket (facultatif)", _customWsHostCtrl, "host.exemple.com"),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cyberYellow.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cyberYellow.withOpacity(0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "SNI TLS",
                        style: TextStyle(color: cyberYellow, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.7),
                      ),
                      SizedBox(height: 4),
                      SizedBox(height: 10),
                      _buildFormField("SNI TLS (domaine du certificat)", _customSniCtrl, "vpn.ton-domaine.com"),
                    ],
                  ),
                ),
                SizedBox(height: 10),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customTlsEnabled && !{'native', 'raw', 'tcp', 'kcp', 'mkcp'}.contains(_customTransport),
                  onChanged: (enabled) {
                    if (_customProtocol == 'trojan' && !enabled) {
                      _showToast('Trojan nécessite TLS sur un serveur public.');
                      return;
                    }
                    if (!enabled && _customProtocol == 'trojan') return;
                    if ({'native', 'raw', 'tcp', 'kcp', 'mkcp'}.contains(_customTransport) && enabled) {
                      _showToast('Ce transport direct ne prend pas en charge TLS dans ce profil.');
                      return;
                    }
                    setState(() => _customTlsEnabled = enabled);
                  },
                  activeTrackColor: cyberGreen,
                  title: Text('Sécurité TLS', style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _buildFormField("Chemin WebSocket / XHTTP", _customPathCtrl, "/@abess237"),
                    ),
                    Expanded(child: SizedBox()),
                  ],
                ),
                SizedBox(height: 10),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Identifiant UUID / Mot de passe", style: TextStyle(color: _text60, fontSize: 10)),
                        GestureDetector(
                          onTap: _generateRandomUuid,
                          child: Text("Générer UUID Aléatoire", style: TextStyle(color: cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    TextField(
                      controller: _customUuidCtrl,
                      style: TextStyle(color: cyberCyan, fontFamily: "monospace", fontSize: 11),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _fieldBackgroundColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                ElevatedButton.icon(
                  onPressed: _saveCustomServerManual,
                  icon: Icon(Icons.flash_on, color: Colors.black, size: 16),
                  label: Text("ACTIVER CE SERVEUR PERSONNEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cyberCyan,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyManualProfileLink,
                        icon: Icon(Icons.link, size: 16),
                        label: Text('ABESS://', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _exportManualProfileFile,
                        icon: Icon(Icons.file_download, size: 16),
                        label: Text('.ABESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: cyberGreen, foregroundColor: Colors.black),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

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
                Text("IMPORTATION RAPIDE PAR LIEN BRUT", style: TextStyle(color: _text70, fontSize: 11, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rawLinkInputCtrl,
                        style: TextStyle(color: _textPrimary, fontSize: 11, fontFamily: "monospace"),
                        decoration: InputDecoration(
                          hintText: "Coller vless://... ou vmess://...",
                          hintStyle: TextStyle(color: _text30, fontSize: 10),
                          filled: true,
                          fillColor: _fieldBackgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_rawLinkInputCtrl.text.isNotEmpty) {
                          _parseUniversalRawLink(_rawLinkInputCtrl.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _text24,
                        foregroundColor: _textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text("IMPORTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
              border: Border.all(color: _text10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("PARAMÈTRES DE PERFORMANCE & STABILITÉ", style: TextStyle(color: _text70, fontSize: 11, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),

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
                  value: isKillSwitchEnabled,
                  onChanged: (val) => setState(() => isKillSwitchEnabled = val),
                  activeTrackColor: cyberRed,
                  title: Text("Kill Switch Anti-Fuite", style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text("Coupe automatiquement le trafic si le tunnel VPN se déconnecte.", style: TextStyle(color: _text54, fontSize: 10)),
                ),
                Divider(color: _text12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isAutoReconnectEnabled,
                  onChanged: (val) => setState(() => isAutoReconnectEnabled = val),
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
          final oldTransport = _customTransport;
          if (id == 'shadowsocks') {
            _customTransport = 'native';
            _customPortCtrl.text = '10050';
            _customTlsEnabled = false;
          } else {
            if (id == 'trojan' || oldTransport == 'native' || oldTransport == 'kcp' || oldTransport == 'mkcp') {
              _customTlsEnabled = true;
            }
            final incompatibleNative = oldTransport == 'native';
            final incompatibleDirect = id != 'vmess' && (oldTransport == 'raw' || oldTransport == 'kcp');
            if (incompatibleNative || incompatibleDirect) {
              _customTransport = 'ws';
              if (['10050', '10060', '10061'].contains(_customPortCtrl.text.trim())) {
                _customPortCtrl.text = '443';
              }
            }
          }
          _customProtocol = id;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyberCyan.withOpacity( 0.25) : _fieldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cyberCyan : _text12),
          ),
          child: Center(
            child: Text(
              label.split(" ")[0],
              style: TextStyle(
                color: isSelected ? cyberCyan : _text60,
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
        onTap: () {
          if (_customProtocol == 'shadowsocks' && id != 'native') {
            _showToast('Pour TCP + UDP, Shadowsocks doit utiliser le transport natif.');
            return;
          }
          if (id == 'native' && _customProtocol != 'shadowsocks') {
            _showToast('Le transport TCP + UDP natif nécessite Shadowsocks.');
            return;
          }
          if ((id == 'raw' || id == 'kcp') && _customProtocol != 'vmess') {
            _showToast('RAW/TCP et mKCP/UDP nécessitent VMess sur le serveur ABESS.');
            return;
          }
          setState(() {
            final oldTransport = _customTransport;
            if (id == 'native') {
              _customPortCtrl.text = '10050';
              _customTlsEnabled = false;
            } else if (id == 'kcp') {
              _customPortCtrl.text = '10061';
              _customTlsEnabled = false;
            } else if (id == 'raw') {
              _customPortCtrl.text = '10060';
              _customTlsEnabled = false;
            } else if (id == 'kcp') {
              _customPortCtrl.text = '10061';
            } else if (oldTransport == 'native' || oldTransport == 'raw' || oldTransport == 'kcp') {
              _customPortCtrl.text = '443';
            }
            if (['ws', 'grpc', 'httpupgrade', 'xhttp'].contains(id)) _customTlsEnabled = true;
            _customTransport = id;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? cyberGreen.withOpacity( 0.25) : _fieldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cyberGreen : _text12),
          ),
          child: Center(
            child: Text(
              label.split(" ")[0],
              style: TextStyle(
                color: isSelected ? cyberGreen : _text60,
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
        Text(label, style: TextStyle(color: _text60, fontSize: 10)),
        SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: TextStyle(color: _textPrimary, fontSize: 11, fontFamily: "monospace"),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _text24, fontSize: 10),
            filled: true,
            fillColor: _fieldBackgroundColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _text24)),
          ),
        ),
      ],
    );
  }
}

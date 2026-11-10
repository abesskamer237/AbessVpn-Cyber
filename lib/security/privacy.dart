/// Logs and support reports must not carry reusable VPN credentials.
String redactDiagnostics(String text) {
  return text
      .replaceAll(RegExp(r'(?:abess|vless|vmess|trojan|ss|wg|wireguard)://[^\s]+', caseSensitive: false), '[configuration masquée]')
      .replaceAll(RegExp(r'(?:ABESS|GENY|NY)-[A-Z0-9-]+', caseSensitive: false), '[identifiant masqué]')
      .replaceAll(RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', caseSensitive: false), '[UUID masqué]')
      .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '[IP masquée]')
      .replaceAll(RegExp(r'\b(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4}\b|(?:[0-9a-f]{0,4}:){1,7}:[0-9a-f:]{0,39}', caseSensitive: false), '[IPv6 masquée]')
      .replaceAll(RegExp(r'(?:token|password|authorization|secret)\s*[:=]\s*[^\s,;]+', caseSensitive: false), '[secret masqué]');
}

bool isTrustedUpdateUrl(String value, String apiOrigin) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) return false;
  final control = Uri.tryParse(apiOrigin);
  if (control != null && control.scheme == 'https' && uri.origin == control.origin) return true;
  return uri.host == 'github.com' && uri.port == 443 &&
      uri.path.startsWith('/abesskamer237/AbessVpn-Cyber/releases/');
}

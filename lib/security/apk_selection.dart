/// Prefer a single-architecture release. Unknown devices get the universal APK,
/// never an arbitrary first asset (which can be ARM32 on an ARM64-only phone).
String? selectApkAsset(
  List<Map<String, dynamic>> assets,
  List<String> supportedAbis,
) {
  final suffixes = <String>[];
  for (final abi in supportedAbis) {
    if (abi == 'arm64-v8a') suffixes.add('-arm64.apk');
    if (abi == 'armeabi-v7a') suffixes.add('-arm32.apk');
    if (abi == 'x86_64') {
      suffixes.add('-x86_64.apk');
      break;
    }
  }
  suffixes.add('-universal.apk');
  for (final suffix in suffixes) {
    for (final asset in assets) {
      final name = asset['name']?.toString().toLowerCase() ?? '';
      final url = asset['browser_download_url']?.toString() ?? '';
      if (name.endsWith(suffix) && url.isNotEmpty) return url;
    }
  }
  return null;
}

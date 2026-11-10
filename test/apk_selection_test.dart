import 'package:flutter_test/flutter_test.dart';
import 'package:abess_vpn/security/apk_selection.dart';

void main() {
  final assets = [
    {
      'name': 'ABESS-VPN-v2.5.2-arm32.apk',
      'browser_download_url': 'https://example.test/arm32',
    },
    {
      'name': 'ABESS-VPN-v2.5.2-universal.apk',
      'browser_download_url': 'https://example.test/universal',
    },
    {
      'name': 'ABESS-VPN-v2.5.2-arm64.apk',
      'browser_download_url': 'https://example.test/arm64',
    },
  ];
  test(
    'ARM64 update chooses the small compatible APK instead of the first asset',
    () {
      expect(
        selectApkAsset(assets, ['arm64-v8a', 'armeabi-v7a']),
        endsWith('/arm64'),
      );
    },
  );
  test('ARM32 phone receives ARM32', () {
    expect(selectApkAsset(assets, ['armeabi-v7a']), endsWith('/arm32'));
  });
  test(
    'unknown architecture and x86 use the compatible universal fallback',
    () {
      expect(selectApkAsset(assets, []), endsWith('/universal'));
      expect(
        selectApkAsset(assets, ['x86_64', 'arm64-v8a']),
        endsWith('/universal'),
      );
    },
  );
  test('no arbitrary incompatible APK when universal is absent', () {
    expect(selectApkAsset([assets.first], ['arm64-v8a']), isNull);
    expect(selectApkAsset([], ['arm64-v8a']), isNull);
  });
}

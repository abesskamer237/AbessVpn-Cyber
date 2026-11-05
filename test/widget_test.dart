import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:abess_vpn/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'AbessVpn',
      packageName: 'com.abessvpn.app',
      version: '2.2.0',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  testWidgets('AbessVpnApp renders title correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const AbessVpnApp());
    expect(find.text('AbessVpn'), findsWidgets);
  });
}


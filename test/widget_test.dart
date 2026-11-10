import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
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
      version: '2.4.0',
      buildNumber: '2004000',
      buildSignature: '',
    );
  });

  testWidgets('AbessVpnApp renders title correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const AbessVpnApp());
    expect(find.text('AbessVpn'), findsWidgets);
    expect(find.text('Votre connexion,\nen toute simplicité.'), findsOneWidget);
    expect(find.text('Mes accès'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}


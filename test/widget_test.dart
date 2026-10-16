import 'package:flutter_test/flutter_test.dart';
import 'package:abess_vpn/main.dart';

void main() {
  testWidgets('AbessVpnApp renders title correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const AbessVpnApp());
    expect(find.text('AbessVpn Cyber'), findsOneWidget);
  });
}

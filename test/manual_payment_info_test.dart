import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abess_vpn/widgets/manual_payment_info.dart';
void main() {
  testWidgets('manual instructions show the exact beneficiaries without automatic payment', (tester) async {
    var contacted = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ManualPaymentInfo(onContactSupport: () => contacted = true)))));
    expect(find.text('MTN MoMo · 681328753'), findsOneWidget);
    expect(find.text('Orange Money · 695140419'), findsOneWidget);
    expect(find.text('Bénéficiaire : manga Ghislain'), findsOneWidget);
    expect(find.text('Bénéficiaire : mengue belinga'), findsOneWidget);
    await tester.ensureVisible(find.text('Contacter le support'));
    await tester.tap(find.text('Contacter le support'));
    expect(contacted, isTrue);
  });
}

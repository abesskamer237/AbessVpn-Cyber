import 'package:abess_vpn/widgets/connection_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget overview({bool connected = false, bool connecting = false, String? name, VoidCallback? choose}) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: ConnectionOverview(
        connected: connected,
        connecting: connecting,
        serverName: name,
        onChooseServer: choose ?? () {},
      )),
    );
  }

  testWidgets('empty state stays disconnected and opens server selection', (tester) async {
    var tapped = false;
    await tester.pumpWidget(overview(choose: () => tapped = true));
    expect(find.text('Déconnecté'), findsOneWidget);
    expect(find.text('VPN connecté'), findsNothing);
    expect(find.text('Ajoutez votre premier accès'), findsOneWidget);
    await tester.tap(find.byTooltip('Choisir un serveur'));
    expect(tapped, isTrue);
  });

  testWidgets('connection state follows the engine input', (tester) async {
    await tester.pumpWidget(overview(connecting: true, name: 'Mon serveur'));
    expect(find.text('Connexion en cours'), findsOneWidget);
    await tester.pumpWidget(overview(connected: true, name: 'Mon serveur'));
    await tester.pumpAndSettle();
    expect(find.text('VPN connecté'), findsOneWidget);
    expect(find.text('Connexion en cours'), findsNothing);
  });

  testWidgets('small screen, long names and larger text remain usable', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 760), textScaler: TextScaler.linear(1.4), disableAnimations: true),
      child: Scaffold(body: ConnectionOverview(
        connected: false, connecting: false,
        serverName: 'Un nom de serveur particulièrement long pour tester la lisibilité',
        onChooseServer: () {},
      )),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Changer de serveur'), findsOneWidget);
  });
}

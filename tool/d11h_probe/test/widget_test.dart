import 'package:flutter_test/flutter_test.dart';

import 'package:d11h_probe/main.dart';

void main() {
  testWidgets('shows the package-backed BLE readiness state', (tester) async {
    await tester.pumpWidget(const D11hProbeApp());

    expect(find.text('NIIMBOT D11H Probe'), findsOneWidget);
    expect(find.text('BLE readiness: ready'), findsOneWidget);
  });
}

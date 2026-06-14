import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_niimbot/niimbot.dart';

import 'support/fake_ble_transport.dart';

void main() {
  test('package exposes the stable BLE readiness states', () {
    expect(BleReadiness.values, [
      BleReadiness.unknown,
      BleReadiness.unsupported,
      BleReadiness.unauthorized,
      BleReadiness.poweredOff,
      BleReadiness.locationServicesDisabled,
      BleReadiness.ready,
    ]);
  });

  test('BLE failure exposes normalized details', () {
    const cause = 'platform error';
    const failure = BleFailure(
      code: BleFailureCode.poweredOff,
      message: 'Bluetooth is unavailable',
      cause: cause,
    );

    expect(failure.code, BleFailureCode.poweredOff);
    expect(failure.message, 'Bluetooth is unavailable');
    expect(failure.cause, cause);
    expect(
      failure.toString(),
      'BleFailure(BleFailureCode.poweredOff, Bluetooth is unavailable)',
    );
  });

  test(
    'stable API exposes the D11H printer facade and media presets',
    () async {
      final printer = D11hPrinter.withTransport(FakeBleTransport());

      expect(LabelSize.d11h12x22.widthMm, 22);
      expect(LabelSize.d11h12x30.widthMm, 30);
      expect(printer.isConnected, isFalse);

      await printer.dispose();
    },
  );
}

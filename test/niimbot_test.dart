import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';

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
}

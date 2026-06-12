import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/src/ble/ble_models.dart';
import 'package:niimbot_lib/src/ble/reactive_ble_mapper.dart';

void main() {
  test('maps every backend BLE status to domain readiness', () {
    expect(
      {for (final status in BleStatus.values) status: mapBleStatus(status)},
      {
        BleStatus.unknown: BleReadiness.unknown,
        BleStatus.unsupported: BleReadiness.unsupported,
        BleStatus.unauthorized: BleReadiness.unauthorized,
        BleStatus.poweredOff: BleReadiness.poweredOff,
        BleStatus.locationServicesDisabled:
            BleReadiness.locationServicesDisabled,
        BleStatus.ready: BleReadiness.ready,
      },
    );
  });

  test('maps every backend connection state to domain status', () {
    expect(
      {
        for (final state in DeviceConnectionState.values)
          state: mapConnectionState(state),
      },
      {
        DeviceConnectionState.connecting: BleConnectionStatus.connecting,
        DeviceConnectionState.connected: BleConnectionStatus.connected,
        DeviceConnectionState.disconnecting: BleConnectionStatus.disconnecting,
        DeviceConnectionState.disconnected: BleConnectionStatus.disconnected,
      },
    );
  });

  test('normalizes UUIDs to lowercase canonical strings', () {
    expect(
      normalizeUuid(Uuid.parse('0000FFF0-0000-1000-8000-00805F9B34FB')),
      '0000fff0-0000-1000-8000-00805f9b34fb',
    );
    expect(normalizeUuid(Uuid.parse('FFF0')), 'fff0');
  });
}

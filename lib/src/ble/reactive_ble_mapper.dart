import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_models.dart';

BleReadiness mapBleStatus(BleStatus status) => switch (status) {
  BleStatus.unknown => BleReadiness.unknown,
  BleStatus.unsupported => BleReadiness.unsupported,
  BleStatus.unauthorized => BleReadiness.unauthorized,
  BleStatus.poweredOff => BleReadiness.poweredOff,
  BleStatus.locationServicesDisabled => BleReadiness.locationServicesDisabled,
  BleStatus.ready => BleReadiness.ready,
};

BleConnectionStatus mapConnectionState(DeviceConnectionState state) =>
    switch (state) {
      DeviceConnectionState.connecting => BleConnectionStatus.connecting,
      DeviceConnectionState.connected => BleConnectionStatus.connected,
      DeviceConnectionState.disconnecting => BleConnectionStatus.disconnecting,
      DeviceConnectionState.disconnected => BleConnectionStatus.disconnected,
    };

String normalizeUuid(Uuid uuid) => uuid.toString().toLowerCase();

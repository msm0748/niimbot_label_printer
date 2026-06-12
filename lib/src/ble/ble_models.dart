import 'dart:typed_data';

import 'ble_failure.dart';

enum BleReadiness {
  unknown,
  unsupported,
  unauthorized,
  poweredOff,
  locationServicesDisabled,
  ready,
}

enum BleConnectionStatus { disconnected, connecting, connected, disconnecting }

enum BleCharacteristicProperty {
  read,
  write,
  writeWithoutResponse,
  notify,
  indicate,
}

final class BleDeviceId {
  const BleDeviceId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BleDeviceId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class BleAdvertisement {
  BleAdvertisement({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required Uint8List manufacturerData,
    required List<String> serviceUuids,
  }) : manufacturerData = Uint8List.fromList(
         manufacturerData,
       ).asUnmodifiableView(),
       serviceUuids = List.unmodifiable(serviceUuids);

  final BleDeviceId deviceId;
  final String? name;
  final int rssi;
  final Uint8List manufacturerData;
  final List<String> serviceUuids;
}

final class BleConnectionUpdate {
  const BleConnectionUpdate({
    required this.deviceId,
    required this.status,
    this.failure,
  });

  final BleDeviceId deviceId;
  final BleConnectionStatus status;
  final BleFailure? failure;
}

final class BleCharacteristic {
  BleCharacteristic({
    required this.serviceUuid,
    required this.characteristicUuid,
    required Set<BleCharacteristicProperty> properties,
  }) : properties = Set.unmodifiable(properties);

  final String serviceUuid;
  final String characteristicUuid;
  final Set<BleCharacteristicProperty> properties;

  bool get canRead => properties.contains(BleCharacteristicProperty.read);

  bool get canWrite =>
      properties.contains(BleCharacteristicProperty.write) ||
      properties.contains(BleCharacteristicProperty.writeWithoutResponse);

  bool get canNotify =>
      properties.contains(BleCharacteristicProperty.notify) ||
      properties.contains(BleCharacteristicProperty.indicate);
}

final class BleService {
  BleService({
    required this.serviceUuid,
    required List<BleCharacteristic> characteristics,
  }) : characteristics = List.unmodifiable(characteristics);

  final String serviceUuid;
  final List<BleCharacteristic> characteristics;
}

enum BleWriteMode { withResponse, withoutResponse }

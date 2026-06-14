import '../ble/ble_models.dart';

const _bluetoothBaseUuidSuffix = '-0000-1000-8000-00805f9b34fb';

BleCharacteristic? findD11hPrintCharacteristic(List<BleService> services) {
  for (final service in services) {
    if (_normalizeUuid(service.serviceUuid) != 'fff0') {
      continue;
    }
    for (final characteristic in service.characteristics) {
      if (_normalizeUuid(characteristic.serviceUuid) == 'fff0' &&
          _normalizeUuid(characteristic.characteristicUuid) == 'fff1' &&
          characteristic.properties.contains(
            BleCharacteristicProperty.notify,
          ) &&
          characteristic.properties.contains(
            BleCharacteristicProperty.writeWithoutResponse,
          )) {
        return characteristic;
      }
    }
  }
  return null;
}

String _normalizeUuid(String uuid) {
  final normalized = uuid.trim().toLowerCase();
  if (normalized.length == 36 &&
      normalized.startsWith('0000') &&
      normalized.endsWith(_bluetoothBaseUuidSuffix)) {
    return normalized.substring(4, 8);
  }
  return normalized;
}

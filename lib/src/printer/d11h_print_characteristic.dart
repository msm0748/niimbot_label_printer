import '../ble/ble_models.dart';

const _bluetoothBaseUuidSuffix = '-0000-1000-8000-00805f9b34fb';

/// Returns the D11H print characteristic, matching [d11h_probe] discovery.
///
/// Prefers FFF0/FFF1 when present, then falls back to any notify +
/// writeWithoutResponse characteristic (required for [ProbeController.printRaster]).
BleCharacteristic? findD11hPrintCharacteristic(List<BleService> services) {
  for (final service in services) {
    if (_normalizeUuid(service.serviceUuid) != 'fff0') {
      continue;
    }
    for (final characteristic in service.characteristics) {
      if (_normalizeUuid(characteristic.characteristicUuid) == 'fff1' &&
          _canPrint(characteristic)) {
        return characteristic;
      }
    }
  }

  for (final service in services) {
    for (final characteristic in service.characteristics) {
      if (_canPrint(characteristic)) {
        return characteristic;
      }
    }
  }
  return null;
}

bool _canPrint(BleCharacteristic characteristic) {
  return characteristic.canNotify &&
      characteristic.properties.contains(
        BleCharacteristicProperty.writeWithoutResponse,
      );
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

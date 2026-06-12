import 'dart:typed_data';

import 'ble_models.dart';

abstract interface class BleTransport {
  BleReadiness get currentReadiness;

  Stream<BleReadiness> get readiness;

  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> stopScan();

  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> disconnect(BleDeviceId deviceId);

  Future<List<BleService>> discoverServices(BleDeviceId deviceId);

  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  );

  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List value, {
    required BleWriteMode mode,
  });

  Future<int> requestMtu(BleDeviceId deviceId, int mtu);

  Future<void> dispose();
}

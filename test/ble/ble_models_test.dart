import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_niimbot/niimbot.dart';

void main() {
  group('BleDeviceId', () {
    test('uses value equality and a value-based hash code', () {
      const first = BleDeviceId('device-1');
      const same = BleDeviceId('device-1');
      const different = BleDeviceId('device-2');

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(different));
      expect(first.toString(), 'device-1');
    });
  });

  group('BleAdvertisement', () {
    test('defensively copies manufacturer data and service UUIDs', () {
      final manufacturerData = Uint8List.fromList([1, 2, 3]);
      final serviceUuids = <String>['service-1'];
      final advertisement = BleAdvertisement(
        deviceId: const BleDeviceId('device-1'),
        name: 'NIIMBOT',
        rssi: -42,
        manufacturerData: manufacturerData,
        serviceUuids: serviceUuids,
      );

      manufacturerData[0] = 9;
      serviceUuids.add('service-2');

      expect(advertisement.manufacturerData, [1, 2, 3]);
      expect(advertisement.serviceUuids, ['service-1']);
    });

    test('rejects mutation through exposed collection views', () {
      final advertisement = BleAdvertisement(
        deviceId: const BleDeviceId('device-1'),
        name: null,
        rssi: -60,
        manufacturerData: Uint8List.fromList([1]),
        serviceUuids: const ['service-1'],
      );

      expect(
        () => advertisement.manufacturerData[0] = 2,
        throwsUnsupportedError,
      );
      expect(
        () => advertisement.serviceUuids.add('service-2'),
        throwsUnsupportedError,
      );
    });
  });

  group('BleCharacteristic', () {
    test('derives supported operations from immutable properties', () {
      final properties = <BleCharacteristicProperty>{
        BleCharacteristicProperty.read,
        BleCharacteristicProperty.writeWithoutResponse,
        BleCharacteristicProperty.indicate,
      };
      final characteristic = BleCharacteristic(
        serviceUuid: 'service-1',
        characteristicUuid: 'characteristic-1',
        properties: properties,
      );

      properties
        ..clear()
        ..add(BleCharacteristicProperty.write);

      expect(characteristic.canRead, isTrue);
      expect(characteristic.canWrite, isTrue);
      expect(characteristic.canNotify, isTrue);
      expect(
        () => characteristic.properties.add(BleCharacteristicProperty.notify),
        throwsUnsupportedError,
      );
    });

    test('reports unsupported operations as false', () {
      final characteristic = BleCharacteristic(
        serviceUuid: 'service-1',
        characteristicUuid: 'characteristic-1',
        properties: const {},
      );

      expect(characteristic.canRead, isFalse);
      expect(characteristic.canWrite, isFalse);
      expect(characteristic.canNotify, isFalse);
    });
  });

  group('BleService', () {
    test('defensively copies and exposes immutable characteristics', () {
      final characteristics = <BleCharacteristic>[
        BleCharacteristic(
          serviceUuid: 'service-1',
          characteristicUuid: 'characteristic-1',
          properties: const {},
        ),
      ];
      final service = BleService(
        serviceUuid: 'service-1',
        characteristics: characteristics,
      );

      characteristics.clear();

      expect(service.characteristics, hasLength(1));
      expect(() => service.characteristics.clear(), throwsUnsupportedError);
    });
  });

  test('connection updates can carry normalized failures', () {
    const failure = BleFailure(
      code: BleFailureCode.connectionFailed,
      message: 'Connection failed',
    );
    const update = BleConnectionUpdate(
      deviceId: BleDeviceId('device-1'),
      status: BleConnectionStatus.disconnected,
      failure: failure,
    );

    expect(update.deviceId, const BleDeviceId('device-1'));
    expect(update.status, BleConnectionStatus.disconnected);
    expect(update.failure, failure);
  });

  test('defines backend-neutral connection, property, and write states', () {
    expect(BleConnectionStatus.values, [
      BleConnectionStatus.disconnected,
      BleConnectionStatus.connecting,
      BleConnectionStatus.connected,
      BleConnectionStatus.disconnecting,
    ]);
    expect(BleCharacteristicProperty.values, [
      BleCharacteristicProperty.read,
      BleCharacteristicProperty.write,
      BleCharacteristicProperty.writeWithoutResponse,
      BleCharacteristicProperty.notify,
      BleCharacteristicProperty.indicate,
    ]);
    expect(BleWriteMode.values, [
      BleWriteMode.withResponse,
      BleWriteMode.withoutResponse,
    ]);
  });
}

import 'package:flutter_niimbot/niimbot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BleCharacteristic characteristic({
    String serviceUuid = 'fff0',
    String characteristicUuid = 'fff1',
    Set<BleCharacteristicProperty> properties =
        const <BleCharacteristicProperty>{
          BleCharacteristicProperty.notify,
          BleCharacteristicProperty.writeWithoutResponse,
        },
  }) => BleCharacteristic(
    serviceUuid: serviceUuid,
    characteristicUuid: characteristicUuid,
    properties: properties,
  );

  BleService service(
    BleCharacteristic characteristic, {
    String serviceUuid = 'fff0',
  }) => BleService(
    serviceUuid: serviceUuid,
    characteristics: <BleCharacteristic>[characteristic],
  );

  test('finds the exact uppercase FFF0 and FFF1 characteristic', () {
    final expected = characteristic(
      serviceUuid: 'FFF0',
      characteristicUuid: 'FFF1',
    );

    expect(
      findD11hPrintCharacteristic(<BleService>[
        service(expected, serviceUuid: 'FFF0'),
      ]),
      same(expected),
    );
  });

  test('accepts Bluetooth-base 128-bit UUIDs', () {
    final expected = characteristic(
      serviceUuid: '0000fff0-0000-1000-8000-00805f9b34fb',
      characteristicUuid: '0000fff1-0000-1000-8000-00805f9b34fb',
    );

    expect(
      findD11hPrintCharacteristic(<BleService>[
        service(expected, serviceUuid: '0000FFF0-0000-1000-8000-00805F9B34FB'),
      ]),
      same(expected),
    );
  });

  test('rejects the right characteristic under the wrong service', () {
    final candidate = characteristic(serviceUuid: 'aaa0');

    expect(
      findD11hPrintCharacteristic(<BleService>[
        service(candidate, serviceUuid: 'aaa0'),
      ]),
      isNull,
    );
  });

  test('rejects another characteristic with compatible properties', () {
    final candidate = characteristic(characteristicUuid: 'fff2');

    expect(
      findD11hPrintCharacteristic(<BleService>[service(candidate)]),
      isNull,
    );
  });

  test('requires notify and writeWithoutResponse together', () {
    final notifyOnly = characteristic(
      properties: const <BleCharacteristicProperty>{
        BleCharacteristicProperty.notify,
      },
    );
    final writeOnly = characteristic(
      properties: const <BleCharacteristicProperty>{
        BleCharacteristicProperty.writeWithoutResponse,
      },
    );

    expect(
      findD11hPrintCharacteristic(<BleService>[
        BleService(
          serviceUuid: 'fff0',
          characteristics: <BleCharacteristic>[notifyOnly, writeOnly],
        ),
      ]),
      isNull,
    );
  });
}

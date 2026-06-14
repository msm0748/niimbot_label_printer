import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_niimbot/niimbot.dart';
import 'package:flutter_niimbot/niimbot_research.dart' show buildD11hCommand;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_ble_transport.dart';

const _deviceId = BleDeviceId('d11h-device');

final _printCharacteristic = BleCharacteristic(
  serviceUuid: 'fff0',
  characteristicUuid: 'fff1',
  properties: const <BleCharacteristicProperty>{
    BleCharacteristicProperty.notify,
    BleCharacteristicProperty.writeWithoutResponse,
  },
);

final _printService = BleService(
  serviceUuid: 'fff0',
  characteristics: <BleCharacteristic>[_printCharacteristic],
);

final _document = LabelDocument(
  size: LabelSize(widthMm: 1, heightMm: 1),
  elements: const <LabelElement>[],
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached before timeout.');
}

Future<void> _completeConnection(
  Future<void> connection,
  FakeBleTransport transport,
) async {
  await _waitFor(() => transport.connectCallCount > 0);
  transport.emitConnectionUpdate(
    const BleConnectionUpdate(
      deviceId: _deviceId,
      status: BleConnectionStatus.connected,
    ),
  );
  await connection;
}

void _respondToPrintWrites(FakeBleTransport transport) {
  transport.writeResponder = (write) {
    final command = write.bytes[2];
    final response = switch (command) {
      0x2C => buildD11hCommand(0x00, const <int>[1]),
      0x23 => buildD11hCommand(0x33, const <int>[1]),
      0x21 => buildD11hCommand(0x31, const <int>[1]),
      0x01 => buildD11hCommand(0x02, const <int>[1]),
      0x13 => buildD11hCommand(0x14, const <int>[1]),
      0xE3 => buildD11hCommand(0xE4, const <int>[1]),
      0xA3 => buildD11hCommand(0xB3, const <int>[0, 1, 0, 0]),
      0xF3 => buildD11hCommand(0xF4, const <int>[1]),
      _ => null,
    };
    if (response != null) {
      transport.emitNotification(
        write.deviceId,
        write.characteristic,
        response,
      );
    }
  };
}

void main() {
  test('scan returns the de-duplicated advertisement snapshot', () async {
    final transport = FakeBleTransport();
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);

    final scan = printer.scan();
    await _waitFor(() => transport.scanCallCount == 1);
    transport.emitAdvertisement(
      BleAdvertisement(
        deviceId: _deviceId,
        name: 'D11_H',
        rssi: -70,
        manufacturerData: Uint8List(0),
        serviceUuids: const <String>[],
      ),
    );
    transport.emitAdvertisement(
      BleAdvertisement(
        deviceId: _deviceId,
        name: 'D11_H',
        rssi: -40,
        manufacturerData: Uint8List(0),
        serviceUuids: const <String>[],
      ),
    );
    await transport.closeScan();

    final devices = await scan;

    expect(devices, hasLength(1));
    expect(devices.single.rssi, -40);
  });

  test(
    'scan completes with discovered devices without manual closeScan',
    () async {
      final transport = FakeBleTransport();
      final printer = D11hPrinter.withTransport(transport);
      addTearDown(printer.dispose);

      final scan = printer.scan(timeout: const Duration(milliseconds: 80));
      await _waitFor(() => transport.scanCallCount == 1);
      transport.emitAdvertisement(
        BleAdvertisement(
          deviceId: _deviceId,
          name: 'D11_H',
          rssi: -38,
          manufacturerData: Uint8List(0),
          serviceUuids: const <String>['fff0'],
        ),
      );

      final devices = await scan;

      expect(devices, hasLength(1));
      expect(devices.single.name, 'D11_H');
      expect(transport.stopScanCallCount, greaterThanOrEqualTo(1));
    },
  );

  test('scan disconnects an active connection before discovery', () async {
    final transport = FakeBleTransport(services: <BleService>[_printService]);
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);
    await _completeConnection(printer.connect(_deviceId), transport);

    final scan = printer.scan();
    await _waitFor(() => transport.scanCallCount == 1);

    expect(printer.isConnected, isFalse);
    expect(transport.disconnectCallCount, 1);

    await transport.closeScan();
    await scan;
  });

  test('connect and disconnect update connection state', () async {
    final transport = FakeBleTransport(services: <BleService>[_printService]);
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);

    await _completeConnection(printer.connect(_deviceId), transport);
    expect(printer.isConnected, isTrue);

    await printer.disconnect();

    expect(printer.isConnected, isFalse);
    expect(transport.disconnectCallCount, 1);
  });

  test('printLabel reconnects to the remembered device', () async {
    final transport = FakeBleTransport(services: <BleService>[_printService]);
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);
    _respondToPrintWrites(transport);

    await _completeConnection(printer.connect(_deviceId), transport);
    await printer.disconnect();

    final print = printer.printLabel(_document);
    await _waitFor(() => transport.connectCallCount == 2);
    transport.emitConnectionUpdate(
      const BleConnectionUpdate(
        deviceId: _deviceId,
        status: BleConnectionStatus.connected,
      ),
    );
    await print;

    expect(transport.writes, isNotEmpty);
    expect(
      transport.writes.every(
        (write) =>
            write.characteristic.characteristicUuid ==
            _printCharacteristic.characteristicUuid,
      ),
      isTrue,
    );
  });

  test('printLabel rejects use before selecting a device', () async {
    final printer = D11hPrinter.withTransport(FakeBleTransport());
    addTearDown(printer.dispose);

    await expectLater(printer.printLabel(_document), throwsStateError);
  });

  test('printLabel rejects a missing D11H print characteristic', () async {
    final transport = FakeBleTransport();
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);
    await _completeConnection(printer.connect(_deviceId), transport);

    final print = printer.printLabel(_document);
    await _waitFor(() => transport.connectCallCount == 2);
    transport.emitConnectionUpdate(
      const BleConnectionUpdate(
        deviceId: _deviceId,
        status: BleConnectionStatus.connected,
      ),
    );

    await expectLater(print, throwsStateError);

    expect(transport.writes, isEmpty);
  });

  test('print requests execute in FIFO order', () async {
    final transport = FakeBleTransport(services: <BleService>[_printService]);
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);
    await _completeConnection(printer.connect(_deviceId), transport);
    _respondToPrintWrites(transport);
    final sessionStartCount = transport.connectCallCount;
    final session = printer.beginPrintSession();
    await _waitFor(() => transport.connectCallCount > sessionStartCount);
    transport.emitConnectionUpdate(
      const BleConnectionUpdate(
        deviceId: _deviceId,
        status: BleConnectionStatus.connected,
      ),
    );
    await session;

    final firstWrite = Completer<void>();
    transport.writeCompleter = firstWrite;

    final first = printer.printLabel(_document);
    final second = printer.printLabel(_document);
    await _waitFor(() => transport.writes.length == 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(transport.writes, hasLength(1));

    transport.writeCompleter = null;
    firstWrite.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(
      transport.writes.where((write) => write.bytes[2] == 0x2C),
      hasLength(2),
    );
  });

  test('a failed queued operation does not poison later operations', () async {
    final transport = FakeBleTransport(services: <BleService>[_printService]);
    final printer = D11hPrinter.withTransport(transport);
    addTearDown(printer.dispose);
    _respondToPrintWrites(transport);

    await expectLater(printer.printLabel(_document), throwsStateError);
    await _completeConnection(printer.connect(_deviceId), transport);
    final sessionStartCount = transport.connectCallCount;
    final session = printer.beginPrintSession();
    await _waitFor(() => transport.connectCallCount > sessionStartCount);
    transport.emitConnectionUpdate(
      const BleConnectionUpdate(
        deviceId: _deviceId,
        status: BleConnectionStatus.connected,
      ),
    );
    await session;
    await printer.printLabel(_document);

    expect(transport.writes, isNotEmpty);
  });

  test('dispose is idempotent and rejects later operations', () async {
    final transport = FakeBleTransport();
    final printer = D11hPrinter.withTransport(transport);

    await Future.wait(<Future<void>>[printer.dispose(), printer.dispose()]);

    expect(transport.disposeCallCount, 1);
    await expectLater(printer.scan(), throwsStateError);
    await expectLater(printer.connect(_deviceId), throwsStateError);
    await expectLater(printer.disconnect(), throwsStateError);
    await expectLater(printer.printLabel(_document), throwsStateError);
  });
}

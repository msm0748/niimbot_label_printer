import 'dart:async';
import 'dart:typed_data';

import 'package:d11h_probe/probe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot_research.dart';

void main() {
  testWidgets('shows scan action and empty-state guidance', (tester) async {
    final controller = ProbeController(_ProbeTestTransport());

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
        ),
      ),
    );

    expect(find.text('Scan for D11H'), findsOneWidget);
    expect(find.text('No devices discovered'), findsOneWidget);
  });

  testWidgets('discovers and connects to a selected printer', (tester) async {
    final transport = _ProbeTestTransport();
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump();

    expect(find.text('D11_H'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    expect(find.text('MTU 185'), findsOneWidget);
    expect(find.textContaining('fff0'), findsWidgets);
  });

  testWidgets('confirms and sends the captured test print', (tester) async {
    final transport = _ProbeTestTransport();
    final controller = ProbeController(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: ProbePage(
          controller: controller,
          requestPermissions: () async => true,
          scanDuration: const Duration(milliseconds: 20),
        ),
      ),
    );

    await tester.tap(find.text('Scan for D11H'));
    await tester.pump();
    transport.emitAdvertisement();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11_H'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Print captured test label'));
    await tester.pumpAndSettle();
    expect(find.text('Send one test label?'), findsOneWidget);

    await tester.tap(find.text('Print one label'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(transport.writeCount, 13);
    expect(find.text('Printer confirmed print completion.'), findsOneWidget);
  });
}

final class _ProbeTestTransport implements BleTransport {
  final _scan = StreamController<BleAdvertisement>.broadcast();
  final _connections = StreamController<BleConnectionUpdate>.broadcast(
    sync: true,
  );
  final _notifications = StreamController<Uint8List>.broadcast(sync: true);
  int writeCount = 0;

  @override
  BleReadiness get currentReadiness => BleReadiness.ready;

  @override
  Stream<BleReadiness> get readiness => const Stream<BleReadiness>.empty();

  void emitAdvertisement() {
    _scan.add(
      BleAdvertisement(
        deviceId: const BleDeviceId('test-device'),
        name: 'D11_H',
        rssi: -42,
        manufacturerData: Uint8List(0),
        serviceUuids: const <String>['fff0'],
      ),
    );
  }

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _scan.stream;

  @override
  Future<void> stopScan() async {}

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    scheduleMicrotask(() {
      _connections.add(
        BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
    });
    return _connections.stream;
  }

  @override
  Future<void> disconnect(BleDeviceId deviceId) async {
    _connections.add(
      BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async {
    return <BleService>[
      BleService(
        serviceUuid: 'fff0',
        characteristics: <BleCharacteristic>[
          BleCharacteristic(
            serviceUuid: 'fff0',
            characteristicUuid: 'fff1',
            properties: const <BleCharacteristicProperty>{
              BleCharacteristicProperty.notify,
              BleCharacteristicProperty.writeWithoutResponse,
            },
          ),
        ],
      ),
    ];
  }

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) => _notifications.stream;

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  }) async {
    writeCount++;
    final command = splitD11hFrames(bytes).first[2];
    final response = switch (command) {
      0x2C => '55 55 00 01 01 00 AA AA',
      0x23 => '55 55 33 01 01 33 AA AA',
      0x21 => '55 55 31 01 01 31 AA AA',
      0x01 => '55 55 02 01 01 02 AA AA',
      0x13 => '55 55 14 02 01 00 17 AA AA',
      0x84 => '55 55 D3 03 01 02 01 D2 AA AA',
      0xA3 => '55 55 B3 08 00 01 64 64 15 16 00 00 B9 AA AA',
      0xE3 => '55 55 E4 01 01 E4 AA AA',
      0xF3 => '55 55 F4 01 01 F4 AA AA',
      0x19 => '55 55 00 01 01 00 AA AA',
      _ => throw StateError('Unexpected command $command'),
    };
    scheduleMicrotask(() => _notifications.add(parseHexBytes(response)));
  }

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu) async => 185;

  @override
  Future<void> dispose() async {
    await _scan.close();
    await _connections.close();
    await _notifications.close();
  }
}

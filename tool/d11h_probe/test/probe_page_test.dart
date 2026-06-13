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
}

final class _ProbeTestTransport implements BleTransport {
  final _scan = StreamController<BleAdvertisement>.broadcast();
  final _connections = StreamController<BleConnectionUpdate>.broadcast(
    sync: true,
  );

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
              BleCharacteristicProperty.write,
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
  ) => const Stream<Uint8List>.empty();

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  }) async {}

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu) async => 185;

  @override
  Future<void> dispose() async {
    await _scan.close();
    await _connections.close();
  }
}

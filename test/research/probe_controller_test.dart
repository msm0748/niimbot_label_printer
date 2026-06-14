import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';
import 'package:niimbot_lib/niimbot_research.dart';

import '../support/fake_ble_transport.dart';

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached before timeout.');
}

void main() {
  const deviceId = BleDeviceId('sensitive-device-identifier');
  final notifyCharacteristic = BleCharacteristic(
    serviceUuid: 'fff0',
    characteristicUuid: 'fff1',
    properties: const <BleCharacteristicProperty>{
      BleCharacteristicProperty.notify,
    },
  );
  final secondNotifyCharacteristic = BleCharacteristic(
    serviceUuid: 'fff0',
    characteristicUuid: 'fff4',
    properties: const <BleCharacteristicProperty>{
      BleCharacteristicProperty.notify,
    },
  );
  final sameUuidOtherServiceCharacteristic = BleCharacteristic(
    serviceUuid: 'aaa0',
    characteristicUuid: 'fff1',
    properties: const <BleCharacteristicProperty>{
      BleCharacteristicProperty.notify,
    },
  );
  final writeCharacteristic = BleCharacteristic(
    serviceUuid: 'fff0',
    characteristicUuid: 'fff2',
    properties: const <BleCharacteristicProperty>{
      BleCharacteristicProperty.write,
    },
  );
  final writeWithoutResponseCharacteristic = BleCharacteristic(
    serviceUuid: 'fff0',
    characteristicUuid: 'fff3',
    properties: const <BleCharacteristicProperty>{
      BleCharacteristicProperty.writeWithoutResponse,
    },
  );
  final capturedPrintCharacteristic = BleCharacteristic(
    serviceUuid: 'fff0',
    characteristicUuid: 'fff5',
    properties: const <BleCharacteristicProperty>{
      BleCharacteristicProperty.writeWithoutResponse,
      BleCharacteristicProperty.notify,
    },
  );
  final service = BleService(
    serviceUuid: 'fff0',
    characteristics: <BleCharacteristic>[
      notifyCharacteristic,
      secondNotifyCharacteristic,
      writeCharacteristic,
      writeWithoutResponseCharacteristic,
      capturedPrintCharacteristic,
    ],
  );

  group('ProbeEvent', () {
    test('formats UTC ISO-8601 structured log lines', () {
      final event = ProbeEvent(
        timestamp: DateTime.parse('2026-06-13T12:34:56+09:00'),
        kind: ProbeEventKind.scan,
        message: 'device name=D11_H rssi=-40',
      );

      expect(
        event.toLogLine(),
        '2026-06-13T03:34:56.000Z scan device name=D11_H rssi=-40',
      );
    });
  });

  group('ProbeController scan', () {
    test('de-duplicates devices by id and keeps the latest result', () async {
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final scanFuture = controller.startScan();
      transport.emitAdvertisement(
        BleAdvertisement(
          deviceId: deviceId,
          name: 'D11_H',
          rssi: -70,
          manufacturerData: Uint8List.fromList(<int>[1, 2, 3]),
          serviceUuids: const <String>[],
        ),
      );
      transport.emitAdvertisement(
        BleAdvertisement(
          deviceId: deviceId,
          name: 'D11_H',
          rssi: -40,
          manufacturerData: Uint8List.fromList(<int>[4, 5, 6]),
          serviceUuids: const <String>[],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.stopScan();
      await scanFuture;

      expect(controller.devices, hasLength(1));
      expect(controller.devices.single.rssi, -40);
      expect(() => controller.devices.clear(), throwsUnsupportedError);
      expect(transport.scanCallCount, 1);
      expect(transport.stopScanCallCount, 1);
    });

    test(
      'shares an active scan and completes when its source is done',
      () async {
        final transport = FakeBleTransport();
        final controller = ProbeController(transport);
        addTearDown(controller.dispose);

        final first = controller.startScan();
        final second = controller.startScan();
        expect(second, same(first));

        await transport.closeScan();
        await Future.wait(<Future<void>>[first, second]);

        expect(transport.scanCallCount, 1);
      },
    );

    test(
      'propagates source errors once and repeated stop remains safe',
      () async {
        final transport = FakeBleTransport();
        final controller = ProbeController(transport);
        addTearDown(controller.dispose);

        final scanFuture = controller.startScan();
        transport.emitScanError(StateError('scan exploded'));

        await expectLater(scanFuture, throwsStateError);
        await Future.wait(<Future<void>>[
          controller.stopScan(),
          controller.stopScan(),
        ]);
      },
    );

    test('cancels a nonterminal source after a scan error', () async {
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final scanFuture = controller.startScan();
      expect(transport.scanListenerCount, 1);

      transport.emitScanError(StateError('nonterminal scan error'));

      await expectLater(scanFuture, throwsStateError);
      expect(transport.scanListenerCount, 0);
      expect(transport.stopScanCallCount, 1);
    });

    test('sanitized scan events never retain advertised names', () async {
      const personalName = 'Alexs Personal Label Printer';
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final scanFuture = controller.startScan();
      transport.emitAdvertisement(
        BleAdvertisement(
          deviceId: deviceId,
          name: personalName,
          rssi: -51,
          manufacturerData: Uint8List(0),
          serviceUuids: const <String>[],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.stopScan();
      await scanFuture;

      final log = controller.exportSanitizedLog();
      expect(log, isNot(contains(personalName)));
      expect(log, contains('device discovered rssi=-51 namePresent=true'));
    });
  });

  group('ProbeController connection', () {
    test('stops scanning, discovers services, and records MTU', () async {
      final transport = FakeBleTransport(
        services: <BleService>[service],
        negotiatedMtu: 185,
      );
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final scanFuture = controller.startScan();
      final connectFuture = controller.connect(deviceId);
      await scanFuture;
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await connectFuture;

      expect(controller.connectedDevice, deviceId);
      expect(controller.services, <BleService>[service]);
      expect(() => controller.services.clear(), throwsUnsupportedError);
      expect(controller.mtu, 185);
      expect(transport.stopScanCallCount, 1);
      expect(transport.discoverServicesCallCount, 1);
      expect(transport.requestMtuCallCount, 1);
      expect(
        controller.events.map((event) => event.kind),
        containsAll(<ProbeEventKind>[
          ProbeEventKind.connection,
          ProbeEventKind.serviceDiscovery,
          ProbeEventKind.mtu,
        ]),
      );
    });

    test('fails without hanging when discovery throws', () async {
      final transport = FakeBleTransport()
        ..discoverServicesError = StateError('discovery failed');
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final connectFuture = controller.connect(deviceId);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );

      await expectLater(connectFuture, throwsStateError);
      expect(controller.connectedDevice, isNull);
      expect(controller.events.last.kind, ProbeEventKind.error);
    });

    test('disconnect during discovery invalidates stale completion', () async {
      final discovery = Completer<List<BleService>>();
      final transport = FakeBleTransport()
        ..discoverServicesCompleter = discovery;
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final connectFuture = controller.connect(deviceId);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.disconnected,
        ),
      );

      await expectLater(connectFuture, throwsStateError);
      discovery.complete(<BleService>[service]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.connectedDevice, isNull);
      expect(controller.services, isEmpty);
      expect(controller.mtu, isNull);
      expect(transport.requestMtuCallCount, 0);
    });

    test('connection source errors complete the attempt', () async {
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final connectFuture = controller.connect(deviceId);
      await Future<void>.delayed(Duration.zero);
      transport.emitConnectionError(deviceId, StateError('link failed'));

      await expectLater(connectFuture, throwsStateError);
      expect(controller.connectedDevice, isNull);
    });

    test(
      'cleanup errors do not replace the original connection failure',
      () async {
        final transport = FakeBleTransport()
          ..discoverServicesError = StateError('original discovery failure')
          ..connectionCancelError = StateError('connection cancel failed');
        final controller = ProbeController(transport);
        final unhandledErrors = <Object>[];

        await runZonedGuarded(() async {
          final connectFuture = controller.connect(deviceId);
          transport.emitConnectionUpdate(
            const BleConnectionUpdate(
              deviceId: deviceId,
              status: BleConnectionStatus.connected,
            ),
          );

          await expectLater(
            connectFuture,
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'original discovery failure',
              ),
            ),
          );
        }, (error, stackTrace) => unhandledErrors.add(error));

        await _waitFor(() => transport.connectionCancelCount == 1);
        expect(transport.connectionCancelCount, 1);
        expect(
          controller.events.where(
            (event) =>
                event.kind == ProbeEventKind.error &&
                event.message.contains('cleanup'),
          ),
          isNotEmpty,
        );
        expect(unhandledErrors, isEmpty);
        await controller.dispose();
      },
    );

    test(
      'times out hanging service discovery within the connect deadline',
      () async {
        final transport = FakeBleTransport()
          ..discoverServicesCompleter = Completer<List<BleService>>();
        final controller = ProbeController(transport);
        addTearDown(controller.dispose);

        final connectFuture = controller.connect(
          deviceId,
          timeout: const Duration(milliseconds: 20),
        );
        transport.emitConnectionUpdate(
          const BleConnectionUpdate(
            deviceId: deviceId,
            status: BleConnectionStatus.connected,
          ),
        );

        await expectLater(
          connectFuture.timeout(const Duration(milliseconds: 200)),
          throwsA(
            isA<BleFailure>()
                .having(
                  (failure) => failure.code,
                  'code',
                  BleFailureCode.connectionFailed,
                )
                .having(
                  (failure) => failure.cause,
                  'cause',
                  isA<TimeoutException>(),
                ),
          ),
        );
        await _waitFor(() => transport.disconnectCallCount == 1);
        expect(transport.disconnectCallCount, 1);
        expect(controller.connectedDevice, isNull);
      },
    );

    test(
      'times out hanging MTU within the remaining connect deadline',
      () async {
        final transport = FakeBleTransport(services: <BleService>[service])
          ..requestMtuCompleter = Completer<int>();
        final controller = ProbeController(transport);
        addTearDown(controller.dispose);

        final connectFuture = controller.connect(
          deviceId,
          timeout: const Duration(milliseconds: 20),
        );
        transport.emitConnectionUpdate(
          const BleConnectionUpdate(
            deviceId: deviceId,
            status: BleConnectionStatus.connected,
          ),
        );

        await expectLater(
          connectFuture.timeout(const Duration(milliseconds: 200)),
          throwsA(
            isA<BleFailure>()
                .having(
                  (failure) => failure.code,
                  'code',
                  BleFailureCode.connectionFailed,
                )
                .having(
                  (failure) => failure.cause,
                  'cause',
                  isA<TimeoutException>(),
                ),
          ),
        );
        await _waitFor(() => transport.disconnectCallCount == 1);
        expect(transport.requestMtuCallCount, 1);
        expect(transport.disconnectCallCount, 1);
        expect(controller.connectedDevice, isNull);
      },
    );

    test('connect deadline completes before hanging failure cleanup', () async {
      final disconnectGate = Completer<void>();
      final transport = FakeBleTransport()
        ..discoverServicesCompleter = Completer<List<BleService>>()
        ..disconnectCompleter = disconnectGate;
      final controller = ProbeController(
        transport,
        cleanupTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        disconnectGate.complete();
        await controller.dispose();
      });

      final watch = Stopwatch()..start();
      final connectFuture = controller.connect(
        deviceId,
        timeout: const Duration(milliseconds: 20),
      );
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );

      await expectLater(
        connectFuture.timeout(const Duration(milliseconds: 100)),
        throwsA(isA<BleFailure>()),
      );
      watch.stop();

      expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));
      expect(controller.connectedDevice, isNull);
      await expectLater(controller.startScan(), throwsStateError);
      await expectLater(controller.connect(deviceId), throwsStateError);
      await expectLater(
        controller.subscribe(notifyCharacteristic),
        throwsStateError,
      );
      await expectLater(
        controller.writeHex(
          writeCharacteristic,
          '55',
          mode: BleWriteMode.withResponse,
        ),
        throwsStateError,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        controller.events.any(
          (event) =>
              event.kind == ProbeEventKind.error &&
              event.message.contains('cleanup timed out'),
        ),
        isTrue,
      );
      await expectLater(controller.startScan(), throwsStateError);
    });

    test('error diagnostics retain safe detail and redact known ids', () async {
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final connectFuture = controller.connect(deviceId);
      transport.emitConnectionError(
        deviceId,
        StateError('link failed for ${deviceId.value}'),
      );
      await expectLater(connectFuture, throwsStateError);

      final message = controller.events
          .lastWhere((event) => event.kind == ProbeEventKind.error)
          .message;
      expect(message, contains('link failed'));
      expect(message, isNot(contains(deviceId.value)));
      expect(message, contains('[redacted-device]'));
    });

    test('BleFailure diagnostics retain safe code and message', () async {
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);

      final connectFuture = controller.connect(deviceId);
      transport.emitConnectionError(
        deviceId,
        const BleFailure(
          code: BleFailureCode.connectionFailed,
          message: 'radio link unavailable',
        ),
      );
      await expectLater(connectFuture, throwsA(isA<BleFailure>()));

      final message = controller.events
          .lastWhere((event) => event.kind == ProbeEventKind.error)
          .message;
      expect(message, contains('code=connectionFailed'));
      expect(message, contains('radio link unavailable'));
    });
  });

  group('ProbeController operations', () {
    late FakeBleTransport transport;
    late ProbeController controller;

    setUp(() async {
      transport = FakeBleTransport(services: <BleService>[service]);
      controller = ProbeController(transport);
      final connected = controller.connect(deviceId);
      await Future<void>.delayed(Duration.zero);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await connected;
    });

    tearDown(() => controller.dispose());

    test('eventStream broadcasts readiness and operation updates', () async {
      final kinds = <ProbeEventKind>[];
      final subscription = controller.eventStream.listen(
        (event) => kinds.add(event.kind),
      );

      transport.emitReadiness(BleReadiness.poweredOff);
      await controller.writeHex(
        writeCharacteristic,
        '55 aa',
        mode: BleWriteMode.withResponse,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        kinds,
        containsAll(<ProbeEventKind>[
          ProbeEventKind.readiness,
          ProbeEventKind.write,
        ]),
      );
      await subscription.cancel();
    });

    test(
      'avoids duplicate subscriptions and logs immutable hex bytes',
      () async {
        await controller.subscribe(notifyCharacteristic);
        await controller.subscribe(notifyCharacteristic);

        final bytes = Uint8List.fromList(<int>[0x55, 0xaa]);
        transport.emitNotification(deviceId, notifyCharacteristic, bytes);
        bytes[0] = 0;
        await Future<void>.delayed(Duration.zero);

        expect(transport.subscribeCallCount, 1);
        expect(
          controller.events.where(
            (event) => event.kind == ProbeEventKind.subscription,
          ),
          hasLength(1),
        );
        expect(controller.events.last.message, contains('55 aa'));
      },
    );

    test('validates notification capability', () async {
      await expectLater(
        controller.subscribe(writeCharacteristic),
        throwsStateError,
      );
      expect(transport.subscribeCallCount, 0);
    });

    test('validates exact write capability and rejects empty bytes', () async {
      await expectLater(
        controller.writeHex(
          writeWithoutResponseCharacteristic,
          '55',
          mode: BleWriteMode.withResponse,
        ),
        throwsStateError,
      );
      await expectLater(
        controller.writeHex(
          writeCharacteristic,
          '55',
          mode: BleWriteMode.withoutResponse,
        ),
        throwsStateError,
      );
      await expectLater(
        controller.writeHex(
          writeCharacteristic,
          '  ',
          mode: BleWriteMode.withResponse,
        ),
        throwsArgumentError,
      );
      await expectLater(
        controller.writeHex(
          writeCharacteristic,
          'zz',
          mode: BleWriteMode.withResponse,
        ),
        throwsFormatException,
      );

      await controller.writeHex(
        writeCharacteristic,
        '55 aa',
        mode: BleWriteMode.withResponse,
      );
      await controller.writeHex(
        writeWithoutResponseCharacteristic,
        '01',
        mode: BleWriteMode.withoutResponse,
      );

      expect(transport.writes, hasLength(2));
    });

    test('replays the captured test print after subscribing', () async {
      transport.writeResponder = (write) {
        final command = splitD11hFrames(write.bytes).first[2];
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
        scheduleMicrotask(
          () => transport.emitNotification(
            deviceId,
            capturedPrintCharacteristic,
            parseHexBytes(response),
          ),
        );
      };

      await controller.printCapturedTestLabel(
        capturedPrintCharacteristic,
        interWriteDelay: Duration.zero,
        statusPollDelay: Duration.zero,
      );

      expect(transport.subscribeCallCount, 1);
      expect(transport.writes, hasLength(13));
      expect(
        transport.writes.map((write) => write.mode),
        everyElement(BleWriteMode.withoutResponse),
      );
      expect(
        transport.writes.map(
          (write) => splitD11hFrames(write.bytes).map((frame) => frame[2]),
        ),
        anyElement(orderedEquals(<int>[0x84, 0x83, 0x85, 0x85, 0x84])),
      );
    });

    test(
      'prints an arbitrary monochrome raster with verified responses',
      () async {
        final raster = MonochromeRaster(
          width: 8,
          height: 2,
          pixels: Uint8List.fromList(<int>[
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            1,
            1,
            1,
            1,
            1,
            1,
            0,
          ]),
        );
        transport.writeResponder = (write) {
          final command = splitD11hFrames(write.bytes).first[2];
          final response = switch (command) {
            0x23 => '55 55 33 01 01 33 AA AA',
            0x21 => '55 55 31 01 01 31 AA AA',
            0x01 => '55 55 02 01 01 02 AA AA',
            0x03 => '55 55 04 01 01 04 AA AA',
            0x13 => '55 55 14 01 01 14 AA AA',
            0x15 => '55 55 16 01 01 16 AA AA',
            0xE3 => '55 55 E4 01 01 E4 AA AA',
            0xA3 => '55 55 B3 04 00 01 64 64 B6 AA AA',
            0xF3 => '55 55 F4 01 01 F4 AA AA',
            0x85 => null,
            _ => throw StateError('Unexpected command $command'),
          };
          if (response != null) {
            scheduleMicrotask(
              () => transport.emitNotification(
                deviceId,
                capturedPrintCharacteristic,
                parseHexBytes(response),
              ),
            );
          }
        };

        await controller.printRaster(
          capturedPrintCharacteristic,
          raster,
          interWriteDelay: Duration.zero,
          statusPollDelay: Duration.zero,
        );

        expect(transport.writes, hasLength(11));
        expect(
          transport.writes
              .map((write) => splitD11hFrames(write.bytes).single[2])
              .where((command) => command == 0x85),
          hasLength(2),
        );
      },
    );

    test('sanitized log excludes device ids and manufacturer bytes', () async {
      await controller.disconnect();
      final scan = controller.startScan();
      transport.emitAdvertisement(
        BleAdvertisement(
          deviceId: deviceId,
          name: 'D11_H',
          rssi: -42,
          manufacturerData: Uint8List.fromList(<int>[0xde, 0xad, 0xbe, 0xef]),
          serviceUuids: const <String>[],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.stopScan();
      await scan;

      final log = controller.exportSanitizedLog();
      expect(log, isNot(contains(deviceId.value)));
      expect(log, isNot(contains('de ad be ef')));
      expect(log.split('\n'), everyElement(contains('T')));
    });

    test('retains only the configured newest events', () async {
      await controller.dispose();
      controller = ProbeController(
        transport = FakeBleTransport(),
        maxEvents: 3,
      );

      transport.emitReadiness(BleReadiness.poweredOff);
      transport.emitReadiness(BleReadiness.ready);
      transport.emitReadiness(BleReadiness.unauthorized);
      transport.emitReadiness(BleReadiness.unsupported);
      await Future<void>.delayed(Duration.zero);

      expect(controller.events, hasLength(3));
      expect(controller.events.map((event) => event.message), <String>[
        'ready',
        'unauthorized',
        'unsupported',
      ]);
    });

    test('bounds notification bytes in retained log events', () async {
      await controller.subscribe(notifyCharacteristic);
      final bytes = Uint8List.fromList(<int>[
        ...List<int>.filled(256, 0),
        ...List<int>.filled(44, 0xab),
      ]);

      transport.emitNotification(deviceId, notifyCharacteristic, bytes);
      await Future<void>.delayed(Duration.zero);

      final message = controller.events
          .lastWhere((event) => event.kind == ProbeEventKind.notification)
          .message;
      expect(message, contains('totalBytes=300'));
      expect(message, contains('truncated=true'));
      expect(message, isNot(contains('ab')));
    });

    test('bounds large write payloads in retained log events', () async {
      final hex = <String>[
        ...List<String>.filled(256, '00'),
        ...List<String>.filled(44, 'ab'),
      ].join(' ');

      await controller.writeHex(
        writeCharacteristic,
        hex,
        mode: BleWriteMode.withResponse,
      );

      final message = controller.events
          .lastWhere((event) => event.kind == ProbeEventKind.write)
          .message;
      expect(message, contains('totalBytes=300'));
      expect(message, contains('truncated=true'));
      expect(message, isNot(contains('ab')));
    });

    test('reconnect can subscribe to the same characteristic again', () async {
      await controller.subscribe(notifyCharacteristic);
      await controller.disconnect();

      final connected = controller.connect(deviceId);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await connected;
      await controller.subscribe(notifyCharacteristic);

      expect(transport.subscribeCallCount, 2);
    });
  });

  group('ProbeController cleanup', () {
    test('disconnect timeout quarantines the controller', () async {
      final transport = FakeBleTransport(services: <BleService>[service])
        ..disconnectCompleter = Completer<void>();
      final controller = ProbeController(
        transport,
        cleanupTimeout: const Duration(milliseconds: 20),
      );
      final connected = controller.connect(deviceId);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await connected;

      await controller.disconnect().timeout(const Duration(milliseconds: 100));

      expect(controller.connectedDevice, isNull);
      expect(
        controller.events.any(
          (event) =>
              event.kind == ProbeEventKind.error &&
              event.message.contains('disconnect cleanup timed out'),
        ),
        isTrue,
      );
      await expectLater(controller.startScan(), throwsStateError);
      await expectLater(controller.connect(deviceId), throwsStateError);

      transport.disconnectCompleter!.complete();
      await controller.dispose();
      expect(transport.disconnectCallCount, 1);
    });

    test('hanging scan cancellation is bounded and quarantines', () async {
      final transport = FakeBleTransport()
        ..scanCancelCompleter = Completer<void>();
      final controller = ProbeController(
        transport,
        cleanupTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        transport.scanCancelCompleter!.complete();
        await controller.dispose();
      });

      final scan = controller.startScan();
      final watch = Stopwatch()..start();

      await expectLater(
        controller.stopScan().timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(scan, throwsA(isA<TimeoutException>()));
      watch.stop();

      expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));
      await expectLater(controller.startScan(), throwsStateError);
      await expectLater(controller.connect(deviceId), throwsStateError);
    });

    test('hanging transport stopScan is bounded and quarantines', () async {
      final transport = FakeBleTransport()
        ..stopScanCompleter = Completer<void>();
      final controller = ProbeController(
        transport,
        cleanupTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        transport.stopScanCompleter!.complete();
        await controller.dispose();
      });

      final scan = controller.startScan();
      final watch = Stopwatch()..start();

      await expectLater(
        controller.stopScan().timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(scan, throwsA(isA<TimeoutException>()));
      watch.stop();

      expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));
      await expectLater(controller.startScan(), throwsStateError);
      await expectLater(controller.connect(deviceId), throwsStateError);
    });

    test(
      'dispose awaits an active explicit disconnect without duplicating it',
      () async {
        final disconnectGate = Completer<void>();
        final transport = FakeBleTransport(services: <BleService>[service])
          ..disconnectCompleter = disconnectGate;
        final controller = ProbeController(transport);
        final connected = controller.connect(deviceId);
        transport.emitConnectionUpdate(
          const BleConnectionUpdate(
            deviceId: deviceId,
            status: BleConnectionStatus.connected,
          ),
        );
        await connected;

        final disconnectFuture = controller.disconnect();
        final disposeFuture = controller.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(transport.disconnectCallCount, 1);
        disconnectGate.complete();
        await Future.wait(<Future<void>>[disconnectFuture, disposeFuture]);
        expect(transport.disconnectCallCount, 1);
      },
    );

    test('disconnect cleanup errors redact the captured device id', () async {
      final transport = FakeBleTransport(services: <BleService>[service])
        ..disconnectError = StateError(
          'disconnect failed for ${deviceId.value}',
        );
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);
      final connected = controller.connect(deviceId);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await connected;

      await expectLater(controller.disconnect(), throwsStateError);

      final message = controller.events
          .lastWhere(
            (event) =>
                event.kind == ProbeEventKind.error &&
                event.message.contains('disconnect'),
          )
          .message;
      expect(message, contains('[redacted-device]'));
      expect(message, isNot(contains(deviceId.value)));
    });

    test(
      'paused event listener drops queued events and resumes with future events',
      () async {
        final transport = FakeBleTransport();
        final controller = ProbeController(transport, maxEvents: 10);
        final received = <ProbeEvent>[];
        final subscription = controller.eventStream.listen(received.add);
        subscription.pause();

        for (var index = 0; index < 2000; index++) {
          transport.emitReadiness(
            index.isEven ? BleReadiness.ready : BleReadiness.poweredOff,
          );
        }
        await Future<void>.delayed(Duration.zero);
        subscription.resume();
        transport.emitReadiness(BleReadiness.unauthorized);
        await Future<void>.delayed(Duration.zero);

        expect(received, hasLength(1));
        expect(received.single.message, 'unauthorized');
        await subscription.cancel();
        await controller.dispose();
      },
    );

    test(
      'rejects subscribe, write, connect, and scan during disconnect',
      () async {
        final disconnectGate = Completer<void>();
        final transport = FakeBleTransport(services: <BleService>[service])
          ..disconnectCompleter = disconnectGate;
        final controller = ProbeController(transport);
        addTearDown(controller.dispose);
        final connected = controller.connect(deviceId);
        transport.emitConnectionUpdate(
          const BleConnectionUpdate(
            deviceId: deviceId,
            status: BleConnectionStatus.connected,
          ),
        );
        await connected;

        final disconnectFuture = controller.disconnect();

        expect(controller.connectedDevice, isNull);
        await expectLater(
          controller.subscribe(notifyCharacteristic),
          throwsStateError,
        );
        await expectLater(
          controller.writeHex(
            writeCharacteristic,
            '55',
            mode: BleWriteMode.withResponse,
          ),
          throwsStateError,
        );
        await expectLater(controller.connect(deviceId), throwsStateError);
        await expectLater(controller.startScan(), throwsStateError);

        disconnectGate.complete();
        await disconnectFuture;
      },
    );

    test('paused event listener does not block dispose', () async {
      final transport = FakeBleTransport();
      final controller = ProbeController(transport);
      final subscription = controller.eventStream.listen((_) {});
      subscription.pause();
      transport.emitReadiness(BleReadiness.poweredOff);

      await controller.dispose().timeout(const Duration(milliseconds: 100));

      expect(transport.disposeCallCount, 1);
      await subscription.cancel();
    });

    test('connection failure attempts every notification cancellation '
        'without unhandled errors', () async {
      final transport = FakeBleTransport(services: <BleService>[service]);
      final controller = ProbeController(transport);
      final unhandledErrors = <Object>[];

      await runZonedGuarded(() async {
        final connected = controller.connect(deviceId);
        transport.emitConnectionUpdate(
          const BleConnectionUpdate(
            deviceId: deviceId,
            status: BleConnectionStatus.connected,
          ),
        );
        await connected;
        await controller.subscribe(notifyCharacteristic);
        await controller.subscribe(secondNotifyCharacteristic);
        final firstKey = (
          deviceId: deviceId,
          serviceUuid: notifyCharacteristic.serviceUuid,
          characteristicUuid: notifyCharacteristic.characteristicUuid,
        );
        transport.notificationCancelErrors[firstKey] = StateError(
          'first notification cancel failed',
        );

        transport.emitConnectionError(
          deviceId,
          StateError('original connection failure'),
        );

        for (var attempt = 0; attempt < 20; attempt++) {
          if (transport.disconnectCallCount == 1) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }, (error, stackTrace) => unhandledErrors.add(error));

      expect(
        transport.notificationCancelAttempts,
        containsPair((
          deviceId: deviceId,
          serviceUuid: notifyCharacteristic.serviceUuid,
          characteristicUuid: notifyCharacteristic.characteristicUuid,
        ), 1),
      );
      expect(
        transport.notificationCancelAttempts,
        containsPair((
          deviceId: deviceId,
          serviceUuid: secondNotifyCharacteristic.serviceUuid,
          characteristicUuid: secondNotifyCharacteristic.characteristicUuid,
        ), 1),
      );
      expect(transport.disconnectCallCount, 1);
      expect(
        controller.events.where(
          (event) =>
              event.kind == ProbeEventKind.error &&
              event.message.contains('cleanup'),
        ),
        isNotEmpty,
      );
      expect(unhandledErrors, isEmpty);
      await controller.dispose();
    });

    test(
      'fake cancellation hooks distinguish matching UUIDs across services',
      () async {
        final transport = FakeBleTransport(
          services: <BleService>[
            service,
            BleService(
              serviceUuid: sameUuidOtherServiceCharacteristic.serviceUuid,
              characteristics: <BleCharacteristic>[
                sameUuidOtherServiceCharacteristic,
              ],
            ),
          ],
        );
        final controller = ProbeController(transport);
        final connected = controller.connect(deviceId);
        transport.emitConnectionUpdate(
          const BleConnectionUpdate(
            deviceId: deviceId,
            status: BleConnectionStatus.connected,
          ),
        );
        await connected;
        await controller.subscribe(notifyCharacteristic);
        await controller.subscribe(sameUuidOtherServiceCharacteristic);
        final firstKey = (
          deviceId: deviceId,
          serviceUuid: notifyCharacteristic.serviceUuid,
          characteristicUuid: notifyCharacteristic.characteristicUuid,
        );
        final otherServiceKey = (
          deviceId: deviceId,
          serviceUuid: sameUuidOtherServiceCharacteristic.serviceUuid,
          characteristicUuid:
              sameUuidOtherServiceCharacteristic.characteristicUuid,
        );
        transport.notificationCancelErrors[firstKey] = StateError(
          'first service cancel failed',
        );

        await expectLater(controller.disconnect(), throwsStateError);

        expect(transport.notificationCancelAttempts[firstKey], 1);
        expect(transport.notificationCancelAttempts[otherServiceKey], 1);
        await controller.dispose();
      },
    );

    test('concurrent disconnect calls share one in-flight future', () async {
      final disconnectGate = Completer<void>();
      final transport = FakeBleTransport()
        ..disconnectCompleter = disconnectGate;
      final controller = ProbeController(transport);
      addTearDown(controller.dispose);
      final connected = controller.connect(deviceId);
      await Future<void>.delayed(Duration.zero);
      transport.emitConnectionUpdate(
        const BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.connected,
        ),
      );
      await connected;

      final first = controller.disconnect();
      final second = controller.disconnect();
      expect(second, same(first));
      disconnectGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(transport.disconnectCallCount, 1);
      expect(controller.connectedDevice, isNull);
    });

    test('concurrent dispose is shared and rejects later operations', () async {
      final disposeGate = Completer<void>();
      final transport = FakeBleTransport()..disposeCompleter = disposeGate;
      final controller = ProbeController(transport);

      final first = controller.dispose();
      final second = controller.dispose();
      expect(second, same(first));
      disposeGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(transport.disposeCallCount, 1);
      await expectLater(controller.startScan(), throwsStateError);
      await expectLater(controller.connect(deviceId), throwsStateError);
      await expectLater(controller.disconnect(), throwsStateError);
      await expectLater(controller.eventStream.isEmpty, completion(isTrue));
    });
  });

  group('ProbeController configuration', () {
    test('requires a positive maxEvents value', () {
      final transport = FakeBleTransport();
      addTearDown(transport.dispose);

      expect(
        () => ProbeController(transport, maxEvents: 0),
        throwsArgumentError,
      );
    });
  });
}

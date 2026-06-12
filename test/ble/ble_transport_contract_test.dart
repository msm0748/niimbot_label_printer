import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';

import '../support/fake_ble_transport.dart';

void main() {
  const deviceId = BleDeviceId('device-1');
  final characteristic = BleCharacteristic(
    serviceUuid: 'service-1',
    characteristicUuid: 'characteristic-1',
    properties: const {
      BleCharacteristicProperty.write,
      BleCharacteristicProperty.notify,
    },
  );
  final service = BleService(
    serviceUuid: 'service-1',
    characteristics: [characteristic],
  );

  late FakeBleTransport transport;

  setUp(() {
    transport = FakeBleTransport();
  });

  tearDown(() async {
    await transport.dispose();
  });

  test('uses ready and 185 as deterministic defaults', () async {
    expect(transport.currentReadiness, BleReadiness.ready);
    expect(await transport.requestMtu(deviceId, 247), 185);
  });

  test('publishes readiness changes and updates current readiness', () async {
    final readiness = expectLater(
      transport.readiness,
      emits(BleReadiness.poweredOff),
    );

    transport.emitReadiness(BleReadiness.poweredOff);

    expect(transport.currentReadiness, BleReadiness.poweredOff);
    await readiness;
  });

  test('delivers connection updates and configured services', () async {
    transport.services = [service];
    final update = BleConnectionUpdate(
      deviceId: deviceId,
      status: BleConnectionStatus.connected,
    );
    final connected = expectLater(transport.connect(deviceId), emits(update));

    transport.emitConnectionUpdate(update);

    await connected;
    expect(await transport.discoverServices(deviceId), [service]);
  });

  test('disconnect emits a disconnected connection update', () async {
    final disconnected = expectLater(
      transport.connect(deviceId),
      emits(
        isA<BleConnectionUpdate>()
            .having((update) => update.deviceId, 'deviceId', deviceId)
            .having(
              (update) => update.status,
              'status',
              BleConnectionStatus.disconnected,
            ),
      ),
    );

    await transport.disconnect(deviceId);

    await disconnected;
  });

  test('connection listener can disconnect after connected update', () async {
    final statuses = <BleConnectionStatus>[];
    final disconnected = Completer<void>();
    final subscription = transport.connect(deviceId).listen((update) {
      statuses.add(update.status);
      if (update.status == BleConnectionStatus.connected) {
        transport
            .disconnect(deviceId)
            .then((_) {}, onError: disconnected.completeError);
      } else if (update.status == BleConnectionStatus.disconnected) {
        disconnected.complete();
      }
    });

    transport.emitConnectionUpdate(
      const BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.connected,
      ),
    );

    await disconnected.future;
    expect(statuses, [
      BleConnectionStatus.connected,
      BleConnectionStatus.disconnected,
    ]);
    await subscription.cancel();
  });

  test('records writes using an immutable defensive byte copy', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    await transport.write(
      deviceId,
      characteristic,
      bytes,
      mode: BleWriteMode.withResponse,
    );
    bytes[0] = 9;

    final write = transport.writes.single;
    expect(write.deviceId, deviceId);
    expect(write.characteristic, same(characteristic));
    expect(write.bytes, [1, 2, 3]);
    expect(write.mode, BleWriteMode.withResponse);
    expect(() => write.bytes[0] = 9, throwsUnsupportedError);
  });

  test('delivers defensive notification byte copies', () async {
    final notification = Uint8List.fromList([4, 5, 6]);
    final received = transport.subscribe(deviceId, characteristic).first;

    transport.emitNotification(deviceId, characteristic, notification);
    notification[0] = 9;

    final bytes = await received;
    expect(bytes, [4, 5, 6]);
    expect(() => bytes[0] = 9, throwsUnsupportedError);
  });

  test('returns an overridden negotiated MTU', () async {
    transport.negotiatedMtu = 128;

    expect(await transport.requestMtu(deviceId, 247), 128);
  });

  test('rejects emissions after disposal', () async {
    await transport.dispose();

    expect(() => transport.emitReadiness(BleReadiness.ready), throwsStateError);
  });

  test(
    'Future.wait([dispose(), dispose()]) completes and rejects emissions',
    () async {
      final firstDispose = transport.dispose();
      final secondDispose = transport.dispose();

      expect(secondDispose, same(firstDispose));
      await Future.wait([firstDispose, secondDispose]);

      expect(
        () => transport.emitReadiness(BleReadiness.ready),
        throwsStateError,
      );
    },
  );
}

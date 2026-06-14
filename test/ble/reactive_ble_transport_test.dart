import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_niimbot/niimbot_research.dart';

void main() {
  const deviceId = BleDeviceId('device-1');
  final characteristic = BleCharacteristic(
    serviceUuid: 'fff0',
    characteristicUuid: 'fff1',
    properties: const {
      BleCharacteristicProperty.write,
      BleCharacteristicProperty.writeWithoutResponse,
      BleCharacteristicProperty.notify,
    },
  );

  late FakeReactiveBleBackend backend;
  late ReactiveBleTransport transport;

  setUp(() {
    backend = FakeReactiveBleBackend();
    transport = ReactiveBleTransport(backendOverride: backend);
  });

  tearDown(() => transport.dispose());

  test('maps current readiness and emits distinct readiness changes', () async {
    backend.status = BleStatus.poweredOff;
    final values = <BleReadiness>[];
    final subscription = transport.readiness.listen(values.add);

    backend.statusController
      ..add(BleStatus.ready)
      ..add(BleStatus.ready)
      ..add(BleStatus.unauthorized);
    await pumpEventQueue();

    expect(transport.currentReadiness, BleReadiness.poweredOff);
    expect(values, [BleReadiness.ready, BleReadiness.unauthorized]);
    await subscription.cancel();
  });

  test(
    'scans with low latency and maps all advertised service UUIDs',
    () async {
      final advertisement = transport.scan().first;
      await pumpEventQueue();

      backend.scanController.add(
        DiscoveredDevice(
          id: 'device-1',
          name: 'NIIMBOT',
          serviceData: {
            Uuid.parse('FFF1'): Uint8List.fromList([1]),
            Uuid.parse('FFF2'): Uint8List.fromList([2]),
          },
          manufacturerData: Uint8List.fromList([3, 4]),
          rssi: -42,
          serviceUuids: [Uuid.parse('FFF0'), Uuid.parse('FFF1')],
        ),
      );

      final result = await advertisement;
      expect(backend.scanServices, isEmpty);
      expect(backend.scanMode, ScanMode.lowLatency);
      expect(result.deviceId, deviceId);
      expect(result.name, 'NIIMBOT');
      expect(result.rssi, -42);
      expect(result.manufacturerData, [3, 4]);
      expect(result.serviceUuids, ['fff0', 'fff1', 'fff2']);
    },
  );

  test('wraps scan timeouts as scan failures', () async {
    await expectLater(
      transport.scan(timeout: const Duration(milliseconds: 1)),
      emitsError(
        isA<BleFailure>().having(
          (failure) => failure.code,
          'code',
          BleFailureCode.scanFailed,
        ),
      ),
    );
  });

  test('connects with prescan and timeout and maps updates', () async {
    final updates = <BleConnectionUpdate>[];
    final subscription = transport
        .connect(deviceId, timeout: const Duration(seconds: 7))
        .listen(updates.add);
    await pumpEventQueue();

    backend.connectionController.add(
      const ConnectionStateUpdate(
        deviceId: 'device-1',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
    await pumpEventQueue();

    expect(backend.connectionId, 'device-1');
    expect(backend.connectionServices, isEmpty);
    expect(backend.prescanDuration, const Duration(seconds: 3));
    expect(backend.connectionTimeout, const Duration(seconds: 7));
    expect(updates.single.deviceId, deviceId);
    expect(updates.single.status, BleConnectionStatus.connected);
    await subscription.cancel();
  });

  test('obtaining a connection stream does not connect before listen', () {
    transport.connect(deviceId, timeout: const Duration(seconds: 7));

    expect(backend.connectionCreateCount, 0);
  });

  test(
    'first listened connection timeout governs backend connection',
    () async {
      transport.connect(deviceId, timeout: const Duration(seconds: 7));

      final subscription = transport
          .connect(deviceId, timeout: const Duration(milliseconds: 25))
          .listen((_) {});
      await pumpEventQueue();

      expect(backend.connectionCreateCount, 1);
      expect(backend.connectionTimeout, const Duration(milliseconds: 25));
      await subscription.cancel();
    },
  );

  test('repeated connect replays the latest connection update', () async {
    final first = transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();
    backend.connectionController.add(
      const ConnectionStateUpdate(
        deviceId: 'device-1',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
    await pumpEventQueue();

    final replayed = await transport
        .connect(deviceId)
        .first
        .timeout(const Duration(milliseconds: 100));

    expect(replayed.status, BleConnectionStatus.connected);
    expect(backend.connectionCreateCount, 1);
    await first.cancel();
  });

  test('each repeated connect honors its own timeout', () async {
    final first = transport
        .connect(deviceId, timeout: const Duration(seconds: 7))
        .listen((_) {});
    await pumpEventQueue();

    final timedOut = await transport
        .connect(deviceId, timeout: const Duration(milliseconds: 10))
        .first
        .timeout(const Duration(milliseconds: 100));

    expect(timedOut.status, BleConnectionStatus.disconnected);
    expect(timedOut.failure?.code, BleFailureCode.connectionFailed);
    expect(backend.connectionTimeout, const Duration(seconds: 7));
    expect(backend.connectionCreateCount, 1);
    await first.cancel();
  });

  test(
    'disconnect cancels backend connection and emits disconnected',
    () async {
      final statuses = <BleConnectionStatus>[];
      final done = Completer<void>();
      transport
          .connect(deviceId)
          .listen(
            (update) => statuses.add(update.status),
            onDone: done.complete,
          );
      await pumpEventQueue();

      await transport.disconnect(deviceId);
      await done.future;

      expect(backend.connectionCancelCount, 1);
      expect(statuses, [BleConnectionStatus.disconnected]);
    },
  );

  test('cancelling domain connection disconnects backend', () async {
    final subscription = transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();

    await subscription.cancel();

    expect(backend.connectionCancelCount, 1);
  });

  test('subscription cancel awaits session removal before reconnect', () async {
    backend.connectionCancelCompleter = Completer<void>();
    final subscription = transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();

    var cancelCompleted = false;
    final cancel = subscription.cancel().then((_) => cancelCompleted = true);
    await pumpEventQueue();

    final completedBeforeBackendCancellation = cancelCompleted;
    backend.connectionCancelCompleter!.complete();
    await cancel;

    expect(completedBeforeBackendCancellation, isFalse);
    backend.connectionCancelCompleter = null;
    final replacement = transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();
    expect(backend.connectionCreateCount, 2);
    await replacement.cancel();
  });

  test('concurrent disconnect calls share the in-flight future', () async {
    backend.connectionCancelCompleter = Completer<void>();
    transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();

    final first = transport.disconnect(deviceId);
    final second = transport.disconnect(deviceId);

    expect(second, same(first));
    backend.connectionCancelCompleter!.complete();
    await first;
    expect(backend.connectionCancelCount, 1);
  });

  test('connection cancellation errors do not wedge session cleanup', () async {
    backend.connectionCancelError = StateError('cancel failed');
    transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();

    await expectLater(
      transport.disconnect(deviceId),
      throwsA(
        isA<BleFailure>().having(
          (failure) => failure.code,
          'code',
          BleFailureCode.connectionFailed,
        ),
      ),
    );

    backend.connectionCancelError = null;
    final replacement = transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();
    expect(backend.connectionCreateCount, 2);
    await replacement.cancel();
  });

  test('discovers services and maps all characteristic properties', () async {
    backend.services = [
      DiscoveredService(
        serviceId: Uuid.parse('FFF0'),
        serviceInstanceId: 'service-instance',
        characteristicIds: [Uuid.parse('FFF1')],
        characteristics: [
          DiscoveredCharacteristic(
            characteristicId: Uuid.parse('FFF1'),
            characteristicInstanceId: 'characteristic-instance',
            serviceId: Uuid.parse('FFF0'),
            isReadable: true,
            isWritableWithResponse: true,
            isWritableWithoutResponse: true,
            isNotifiable: true,
            isIndicatable: true,
          ),
        ],
      ),
    ];

    final services = await transport.discoverServices(deviceId);

    expect(services.single.serviceUuid, 'fff0');
    expect(services.single.characteristics.single.characteristicUuid, 'fff1');
    expect(services.single.characteristics.single.properties, {
      BleCharacteristicProperty.read,
      BleCharacteristicProperty.write,
      BleCharacteristicProperty.writeWithoutResponse,
      BleCharacteristicProperty.notify,
      BleCharacteristicProperty.indicate,
    });
  });

  test('qualifies subscriptions, writes, and MTU requests', () async {
    final notification = transport.subscribe(deviceId, characteristic).first;
    await pumpEventQueue();
    backend.notificationController.add([1, 2, 3]);
    expect(await notification, [1, 2, 3]);

    await transport.write(
      deviceId,
      characteristic,
      Uint8List.fromList([4]),
      mode: BleWriteMode.withResponse,
    );
    await transport.write(
      deviceId,
      characteristic,
      Uint8List.fromList([5]),
      mode: BleWriteMode.withoutResponse,
    );
    expect(await transport.requestMtu(deviceId, 247), 185);

    expect(backend.qualifiedCharacteristics, hasLength(3));
    for (final qualified in backend.qualifiedCharacteristics) {
      expect(qualified.deviceId, 'device-1');
      expect(qualified.serviceId, Uuid.parse('FFF0'));
      expect(qualified.characteristicId, Uuid.parse('FFF1'));
    }
    expect(backend.writes, hasLength(2));
    expect(backend.writes[0].withResponse, isTrue);
    expect(backend.writes[0].value, [4]);
    expect(backend.writes[1].withResponse, isFalse);
    expect(backend.writes[1].value, [5]);
    expect(backend.requestedMtu, (deviceId: 'device-1', mtu: 247));
  });

  test('wraps backend operation errors as domain failures', () async {
    backend.writeError = StateError('write failed');

    await expectLater(
      transport.write(
        deviceId,
        characteristic,
        Uint8List(0),
        mode: BleWriteMode.withResponse,
      ),
      throwsA(
        isA<BleFailure>().having(
          (failure) => failure.code,
          'code',
          BleFailureCode.writeFailed,
        ),
      ),
    );
  });

  test(
    'scan timeout is total duration even while advertisements arrive',
    () async {
      final errors = <Object>[];
      final done = Completer<void>();
      final subscription = transport
          .scan(timeout: const Duration(milliseconds: 30))
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await pumpEventQueue();
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => backend.scanController.add(_advertisement()),
      );

      await done.future.timeout(const Duration(milliseconds: 100));
      timer.cancel();

      expect(errors.single, isA<BleFailure>());
      expect((errors.single as BleFailure).code, BleFailureCode.scanFailed);
      expect(backend.scanCancelCount, 1);
      await subscription.cancel();
    },
  );

  test('stopScan cancels active managed scans and closes streams', () async {
    final done = Completer<void>();
    transport.scan().listen((_) {}, onDone: done.complete);
    await pumpEventQueue();

    await transport.stopScan();
    await done.future.timeout(const Duration(milliseconds: 100));

    expect(backend.scanCancelCount, 1);
  });

  test('managed stream cancellation awaits backend cancellation', () async {
    backend.scanCancelCompleter = Completer<void>();
    final subscription = transport.scan().listen((_) {});
    await pumpEventQueue();

    var cancelCompleted = false;
    final cancel = subscription.cancel().then((_) => cancelCompleted = true);
    await pumpEventQueue();

    final completedBeforeBackendCancellation = cancelCompleted;
    backend.scanCancelCompleter!.complete();
    await cancel;

    expect(completedBeforeBackendCancellation, isFalse);
    expect(backend.scanCancelCount, 1);
  });

  test('managed stream cancellation propagates normalized errors', () async {
    backend.scanCancelError = StateError('scan cancel failed');
    final subscription = transport.scan().listen((_) {});
    await pumpEventQueue();

    await expectLater(
      subscription.cancel(),
      throwsA(
        isA<BleFailure>().having(
          (failure) => failure.code,
          'code',
          BleFailureCode.scanFailed,
        ),
      ),
    );
  });

  test('unlistened scan is not registered with stopScan', () async {
    final scan = transport.scan();

    var stopTimedOut = false;
    try {
      await transport.stopScan().timeout(const Duration(milliseconds: 50));
    } on TimeoutException {
      stopTimedOut = true;
      final drain = scan.drain<void>();
      await transport.stopScan();
      await drain;
    }

    expect(stopTimedOut, isFalse);
    final advertisement = scan.first;
    await pumpEventQueue();
    backend.scanController.add(_advertisement());
    expect(await advertisement, isA<BleAdvertisement>());
  });

  test(
    'disposing unlistened streams creates no backend subscriptions',
    () async {
      final readinessStreams = List.generate(20, (_) => transport.readiness);
      final scanStreams = List.generate(20, (_) => transport.scan());
      final notificationStreams = List.generate(
        20,
        (_) => transport.subscribe(deviceId, characteristic),
      );

      expect(backend.statusListenCount, 0);
      expect(backend.scanCreateCount, 0);
      expect(backend.notificationCreateCount, 0);

      var disposeTimedOut = false;
      try {
        await transport.dispose().timeout(const Duration(milliseconds: 50));
      } on TimeoutException {
        disposeTimedOut = true;
        final drains = [
          ...readinessStreams.map((stream) => stream.drain<void>()),
          ...scanStreams.map((stream) => stream.drain<void>()),
          ...notificationStreams.map((stream) => stream.drain<void>()),
        ];
        await transport.dispose();
        await Future.wait(drains);
      }

      expect(disposeTimedOut, isFalse);
      expect(backend.statusListenCount, 0);
      expect(backend.scanCreateCount, 0);
      expect(backend.notificationCreateCount, 0);
    },
  );

  test('pre-obtained lazy streams cannot start after disposal', () async {
    final readiness = transport.readiness;
    final scan = transport.scan();
    final notification = transport.subscribe(deviceId, characteristic);
    await transport.dispose();

    final errors = <Object>[];
    final subscriptions = [
      readiness.listen((_) {}, onError: errors.add),
      scan.listen((_) {}, onError: errors.add),
      notification.listen((_) {}, onError: errors.add),
    ];
    await pumpEventQueue();

    expect(errors, hasLength(3));
    expect(errors, everyElement(_invalidStateFailure()));
    expect(backend.statusListenCount, 0);
    expect(backend.scanCreateCount, 0);
    expect(backend.notificationCreateCount, 0);
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  });

  test('dispose cancels readiness scan and notification streams', () async {
    final readinessDone = Completer<void>();
    final scanDone = Completer<void>();
    final notificationDone = Completer<void>();
    transport.readiness.listen((_) {}, onDone: readinessDone.complete);
    transport.scan().listen((_) {}, onDone: scanDone.complete);
    transport
        .subscribe(deviceId, characteristic)
        .listen((_) {}, onDone: notificationDone.complete);
    await pumpEventQueue();

    await transport.dispose();
    await Future.wait([
      readinessDone.future,
      scanDone.future,
      notificationDone.future,
    ]).timeout(const Duration(milliseconds: 100));

    expect(backend.statusCancelCount, 1);
    expect(backend.scanCancelCount, 1);
    expect(backend.notificationCancelCount, 1);
  });

  test('dispose cancels active connections and is idempotent', () async {
    transport.connect(deviceId).listen((_) {});
    await pumpEventQueue();

    final first = transport.dispose();
    final second = transport.dispose();
    expect(second, same(first));
    await Future.wait([first, second]);

    expect(backend.connectionCancelCount, 1);
  });

  test(
    'rejects every new operation after disposal with invalidState',
    () async {
      await transport.dispose();

      expect(() => transport.currentReadiness, throwsA(_invalidStateFailure()));
      expect(() => transport.readiness, throwsA(_invalidStateFailure()));
      expect(() => transport.scan(), throwsA(_invalidStateFailure()));
      expect(
        () => transport.connect(deviceId),
        throwsA(_invalidStateFailure()),
      );
      expect(
        () => transport.subscribe(deviceId, characteristic),
        throwsA(_invalidStateFailure()),
      );
      await expectLater(transport.stopScan(), throwsA(_invalidStateFailure()));
      await expectLater(
        transport.disconnect(deviceId),
        throwsA(_invalidStateFailure()),
      );
      await expectLater(
        transport.discoverServices(deviceId),
        throwsA(_invalidStateFailure()),
      );
      await expectLater(
        transport.write(
          deviceId,
          characteristic,
          Uint8List(0),
          mode: BleWriteMode.withResponse,
        ),
        throwsA(_invalidStateFailure()),
      );
      await expectLater(
        transport.requestMtu(deviceId, 247),
        throwsA(_invalidStateFailure()),
      );
    },
  );
}

final class FakeReactiveBleBackend implements ReactiveBleBackend {
  FakeReactiveBleBackend() {
    statusController.onCancel = () {
      statusCancelCount++;
    };
    notificationController.onCancel = () {
      notificationCancelCount++;
    };
  }

  @override
  BleStatus status = BleStatus.unknown;
  final statusController = StreamController<BleStatus>.broadcast();
  final notificationController = StreamController<List<int>>.broadcast();
  StreamController<DiscoveredDevice>? _scanController;
  StreamController<ConnectionStateUpdate>? _connectionController;

  StreamController<DiscoveredDevice> get scanController => _scanController!;

  StreamController<ConnectionStateUpdate> get connectionController =>
      _connectionController!;

  List<Uuid>? scanServices;
  ScanMode? scanMode;
  String? connectionId;
  List<Uuid>? connectionServices;
  Duration? prescanDuration;
  Duration? connectionTimeout;
  int statusCancelCount = 0;
  int statusListenCount = 0;
  int scanCancelCount = 0;
  int scanCreateCount = 0;
  int connectionCancelCount = 0;
  int connectionCreateCount = 0;
  int notificationCancelCount = 0;
  int notificationCreateCount = 0;
  Completer<void>? scanCancelCompleter;
  Object? scanCancelError;
  Completer<void>? connectionCancelCompleter;
  Object? connectionCancelError;
  List<DiscoveredService> services = [];
  final List<QualifiedCharacteristic> qualifiedCharacteristics = [];
  final List<({bool withResponse, List<int> value})> writes = [];
  ({String deviceId, int mtu})? requestedMtu;
  Object? writeError;

  @override
  Stream<BleStatus> get statusStream {
    statusListenCount++;
    return statusController.stream;
  }

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
  }) {
    scanCreateCount++;
    final controller = StreamController<DiscoveredDevice>();
    controller.onCancel = () {
      scanCancelCount++;
      final error = scanCancelError;
      if (error != null) {
        scanCancelError = null;
        return Future<void>.error(error);
      }
      return scanCancelCompleter?.future;
    };
    _scanController = controller;
    scanServices = withServices;
    this.scanMode = scanMode;
    return controller.stream;
  }

  @override
  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    required Duration connectionTimeout,
  }) {
    connectionCreateCount++;
    final controller = StreamController<ConnectionStateUpdate>();
    controller.onCancel = () {
      connectionCancelCount++;
      final error = connectionCancelError;
      if (error != null) {
        connectionCancelError = null;
        return Future<void>.error(error);
      }
      return connectionCancelCompleter?.future;
    };
    _connectionController = controller;
    connectionId = id;
    connectionServices = withServices;
    this.prescanDuration = prescanDuration;
    this.connectionTimeout = connectionTimeout;
    return controller.stream;
  }

  @override
  Future<List<DiscoveredService>> discoverServices(String deviceId) async =>
      services;

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) {
    notificationCreateCount++;
    qualifiedCharacteristics.add(characteristic);
    return notificationController.stream;
  }

  @override
  Future<void> writeCharacteristic(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
    required bool withResponse,
  }) async {
    qualifiedCharacteristics.add(characteristic);
    if (writeError case final error?) {
      throw error;
    }
    writes.add((withResponse: withResponse, value: List.of(value)));
  }

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async {
    requestedMtu = (deviceId: deviceId, mtu: mtu);
    return 185;
  }
}

DiscoveredDevice _advertisement() => DiscoveredDevice(
  id: 'device-1',
  name: 'NIIMBOT',
  serviceData: const {},
  manufacturerData: Uint8List(0),
  rssi: -42,
  serviceUuids: const [],
);

Matcher _invalidStateFailure() => isA<BleFailure>().having(
  (failure) => failure.code,
  'code',
  BleFailureCode.invalidState,
);

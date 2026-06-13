import 'dart:async';
import 'dart:typed_data';

import 'package:niimbot_lib/niimbot.dart';
import 'package:niimbot_lib/src/ble/ble_transport.dart';

final class FakeBleWrite {
  FakeBleWrite({
    required this.deviceId,
    required this.characteristic,
    required Uint8List bytes,
    required this.mode,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final BleDeviceId deviceId;
  final BleCharacteristic characteristic;
  final Uint8List bytes;
  final BleWriteMode mode;
}

typedef FakeBleCharacteristicKey = ({
  BleDeviceId deviceId,
  String serviceUuid,
  String characteristicUuid,
});

final class FakeBleTransport implements BleTransport {
  FakeBleTransport({
    this.currentReadiness = BleReadiness.ready,
    this.services = const [],
    this.negotiatedMtu = 185,
  });

  final StreamController<BleReadiness> _readinessController =
      StreamController.broadcast();
  StreamController<BleAdvertisement>? _scanController;
  final Map<BleDeviceId, StreamController<BleConnectionUpdate>>
  _connectionControllers = {};
  final Map<
    ({BleDeviceId deviceId, String serviceUuid, String characteristicUuid}),
    StreamController<Uint8List>
  >
  _notificationControllers = {};

  @override
  BleReadiness currentReadiness;

  List<BleService> services;
  int negotiatedMtu;
  final List<FakeBleWrite> writes = [];
  Object? discoverServicesError;
  Completer<List<BleService>>? discoverServicesCompleter;
  Completer<int>? requestMtuCompleter;
  Completer<void>? scanCancelCompleter;
  Object? scanCancelError;
  Completer<void>? stopScanCompleter;
  Object? stopScanError;
  Completer<void>? disconnectCompleter;
  Object? disconnectError;
  Completer<void>? disposeCompleter;
  Object? connectionCancelError;
  final Map<FakeBleCharacteristicKey, Object> notificationCancelErrors =
      <FakeBleCharacteristicKey, Object>{};
  final Map<FakeBleCharacteristicKey, int> notificationCancelAttempts =
      <FakeBleCharacteristicKey, int>{};
  int scanListenerCount = 0;
  int connectionCancelCount = 0;
  int scanCallCount = 0;
  int stopScanCallCount = 0;
  int connectCallCount = 0;
  int disconnectCallCount = 0;
  int discoverServicesCallCount = 0;
  int subscribeCallCount = 0;
  int requestMtuCallCount = 0;
  int disposeCallCount = 0;

  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Stream<BleReadiness> get readiness => _readinessController.stream;

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    scanCallCount++;
    final active = _scanController;
    if (active != null && !active.isClosed) {
      return active.stream;
    }

    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () => scanListenerCount++,
      onCancel: () async {
        scanListenerCount--;
        await scanCancelCompleter?.future;
        final error = scanCancelError;
        if (identical(_scanController, controller)) {
          _scanController = null;
        }
        if (error != null) {
          throw error;
        }
      },
    );
    _scanController = controller;
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    stopScanCallCount++;
    await stopScanCompleter?.future;
    final error = stopScanError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    connectCallCount++;
    return _connectionController(deviceId).stream;
  }

  @override
  Future<void> disconnect(BleDeviceId deviceId) async {
    disconnectCallCount++;
    await disconnectCompleter?.future;
    final error = disconnectError;
    if (error != null) {
      throw error;
    }
    _connectionControllers[deviceId]?.add(
      BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async {
    discoverServicesCallCount++;
    final error = discoverServicesError;
    if (error != null) {
      throw error;
    }
    final completer = discoverServicesCompleter;
    if (completer != null) {
      return List.unmodifiable(await completer.future);
    }
    return List.unmodifiable(services);
  }

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) {
    subscribeCallCount++;
    return _notificationController(deviceId, characteristic).stream;
  }

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List value, {
    required BleWriteMode mode,
  }) async {
    _ensureNotDisposed();
    writes.add(
      FakeBleWrite(
        deviceId: deviceId,
        characteristic: characteristic,
        bytes: value,
        mode: mode,
      ),
    );
  }

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int mtu) async {
    requestMtuCallCount++;
    final completer = requestMtuCompleter;
    if (completer != null) {
      return completer.future;
    }
    return negotiatedMtu;
  }

  void emitReadiness(BleReadiness value) {
    _ensureNotDisposed();
    currentReadiness = value;
    _readinessController.add(value);
  }

  void emitAdvertisement(BleAdvertisement advertisement) {
    _ensureNotDisposed();
    _scanController?.add(advertisement);
  }

  void emitScanError(Object error) {
    _ensureNotDisposed();
    _scanController?.addError(error);
  }

  Future<void> closeScan() => _scanController?.close() ?? Future<void>.value();

  void emitConnectionUpdate(BleConnectionUpdate update) {
    _ensureNotDisposed();
    _connectionController(update.deviceId).add(update);
  }

  void emitConnectionError(BleDeviceId deviceId, Object error) {
    _ensureNotDisposed();
    _connectionController(deviceId).addError(error);
  }

  void emitNotification(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List value,
  ) {
    _ensureNotDisposed();
    final bytes = Uint8List.fromList(value).asUnmodifiableView();
    _notificationController(deviceId, characteristic).add(bytes);
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    disposeCallCount++;
    _disposed = true;
    await disposeCompleter?.future;
    final connectionControllers = _connectionControllers.values.toList();
    final notificationControllers = _notificationControllers.values.toList();

    await Future.wait([
      if (!_readinessController.isClosed) _readinessController.close(),
      if (_scanController case final controller?) controller.close(),
      ...connectionControllers.map((controller) => controller.close()),
      ...notificationControllers.map((controller) => controller.close()),
    ]);
  }

  StreamController<BleConnectionUpdate> _connectionController(
    BleDeviceId deviceId,
  ) {
    _ensureNotDisposed();
    return _connectionControllers.putIfAbsent(deviceId, () {
      late final StreamController<BleConnectionUpdate> controller;
      controller = StreamController(
        onCancel: () async {
          connectionCancelCount++;
          if (identical(_connectionControllers[deviceId], controller)) {
            _connectionControllers.remove(deviceId);
          }
          final error = connectionCancelError;
          if (error != null) {
            return Future<void>.error(error);
          }
        },
      );
      return controller;
    });
  }

  StreamController<Uint8List> _notificationController(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) {
    _ensureNotDisposed();
    final key = (
      deviceId: deviceId,
      serviceUuid: characteristic.serviceUuid,
      characteristicUuid: characteristic.characteristicUuid,
    );
    return _notificationControllers.putIfAbsent(key, () {
      late final StreamController<Uint8List> controller;
      controller = StreamController(
        onCancel: () async {
          if (identical(_notificationControllers[key], controller)) {
            _notificationControllers.remove(key);
          }
          notificationCancelAttempts.update(
            key,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          final error = notificationCancelErrors[key];
          if (error != null) {
            return Future<void>.error(error);
          }
        },
      );
      unawaited(
        controller.done.whenComplete(() {
          if (identical(_notificationControllers[key], controller)) {
            _notificationControllers.remove(key);
          }
        }),
      );
      return controller;
    });
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FakeBleTransport has been disposed.');
    }
  }
}

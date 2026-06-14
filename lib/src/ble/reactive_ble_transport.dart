import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_failure.dart';
import 'ble_models.dart';
import 'ble_transport.dart';
import 'reactive_ble_mapper.dart';

abstract interface class ReactiveBleBackend {
  BleStatus get status;

  Stream<BleStatus> get statusStream;

  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
  });

  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    required Duration connectionTimeout,
  });

  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  });

  Future<List<DiscoveredService>> discoverServices(String deviceId);

  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  );

  Future<void> writeCharacteristic(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
    required bool withResponse,
  });

  Future<int> requestMtu({required String deviceId, required int mtu});
}

final class FlutterReactiveBleBackend implements ReactiveBleBackend {
  FlutterReactiveBleBackend(this._backend);

  final FlutterReactiveBle _backend;

  @override
  BleStatus get status => _backend.status;

  @override
  Stream<BleStatus> get statusStream => _backend.statusStream;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
  }) => _backend.scanForDevices(withServices: withServices, scanMode: scanMode);

  @override
  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    required Duration connectionTimeout,
  }) => _backend.connectToAdvertisingDevice(
    id: id,
    withServices: withServices,
    prescanDuration: prescanDuration,
    connectionTimeout: connectionTimeout,
  );

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  }) => _backend.connectToDevice(
    id: id,
    servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover,
    connectionTimeout: connectionTimeout,
  );

  @override
  Future<List<DiscoveredService>> discoverServices(String deviceId) {
    // The 5.5.0 facade still exposes the property-rich legacy model directly.
    // ignore: deprecated_member_use
    return _backend.discoverServices(deviceId);
  }

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) => _backend.subscribeToCharacteristic(characteristic);

  @override
  Future<void> writeCharacteristic(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
    required bool withResponse,
  }) => withResponse
      ? _backend.writeCharacteristicWithResponse(characteristic, value: value)
      : _backend.writeCharacteristicWithoutResponse(
          characteristic,
          value: value,
        );

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) =>
      _backend.requestMtu(deviceId: deviceId, mtu: mtu);
}

final class ReactiveBleTransport implements BleTransport {
  static final Uuid _d11hServiceUuid = Uuid.parse(
    '0000fff0-0000-1000-8000-00805f9b34fb',
  );
  static final Uuid _d11hCharacteristicUuid = Uuid.parse(
    '0000fff1-0000-1000-8000-00805f9b34fb',
  );

  ReactiveBleTransport({
    FlutterReactiveBle? backend,
    ReactiveBleBackend? backendOverride,
  }) : assert(
         backend == null || backendOverride == null,
         'Provide either backend or backendOverride, not both.',
       ),
       _backend =
           backendOverride ??
           FlutterReactiveBleBackend(backend ?? FlutterReactiveBle());

  final ReactiveBleBackend _backend;
  final Map<BleDeviceId, _ConnectionSession> _connections = {};
  final Set<_ManagedResource> _resources = {};
  final Set<_ManagedResource> _scans = {};

  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  BleReadiness get currentReadiness {
    _ensureNotDisposed();
    return mapBleStatus(_backend.status);
  }

  @override
  Stream<BleReadiness> get readiness {
    _ensureNotDisposed();
    return _manage<BleStatus, BleReadiness>(
      source: () => _backend.statusStream,
      mapValue: mapBleStatus,
      distinct: true,
    );
  }

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _ensureNotDisposed();
    late final _ManagedOperation<DiscoveredDevice, BleAdvertisement> operation;
    operation = _ManagedOperation(
      source: () {
        _ensureNotDisposed();
        return _backend.scanForDevices(
          withServices: const <Uuid>[],
          scanMode: ScanMode.lowLatency,
        );
      },
      mapValue: _mapAdvertisement,
      mapError: (error) =>
          _failure(BleFailureCode.scanFailed, 'BLE scan failed.', error),
      totalTimeout: timeout,
      timeoutError: () => _failure(
        BleFailureCode.scanFailed,
        'BLE scan timed out.',
        TimeoutException('BLE scan timed out.', timeout),
      ),
      onStarted: () {
        _resources.add(operation);
        _scans.add(operation);
      },
      onClosed: () {
        _resources.remove(operation);
        _scans.remove(operation);
      },
    );
    return operation.stream;
  }

  @override
  Future<void> stopScan() {
    try {
      _ensureNotDisposed();
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
    return _closeResources(_scans.toList(growable: false));
  }

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    _ensureNotDisposed();
    return Stream.multi((controller) {
      try {
        _ensureNotDisposed();
        final session = _connections.putIfAbsent(
          deviceId,
          () => _ConnectionSession(
            deviceId: deviceId,
            source: () => _backend.connectToDevice(
              id: deviceId.value,
              servicesWithCharacteristicsToDiscover: {
                _d11hServiceUuid: [_d11hCharacteristicUuid],
              },
              connectionTimeout: timeout,
            ),
            onClosed: () => _connections.remove(deviceId),
          ),
        );
        final subscription = session
            .open(timeout)
            .listen(
              controller.addSync,
              onError: controller.addErrorSync,
              onDone: controller.closeSync,
            );
        controller.onCancel = subscription.cancel;
      } catch (error, stackTrace) {
        controller.addErrorSync(error, stackTrace);
        controller.closeSync();
      }
    });
  }

  @override
  Future<void> disconnect(BleDeviceId deviceId) {
    try {
      _ensureNotDisposed();
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
    return _connections[deviceId]?.disconnect(emitDisconnected: true) ??
        Future<void>.value();
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) => _guard(
    BleFailureCode.discoveryFailed,
    'BLE service discovery failed.',
    () async {
      _ensureNotDisposed();
      final services = await _backend.discoverServices(deviceId.value);
      return List.unmodifiable(
        services.map(
          (service) => BleService(
            serviceUuid: normalizeUuid(service.serviceId),
            characteristics: service.characteristics
                .map(
                  (characteristic) => BleCharacteristic(
                    serviceUuid: normalizeUuid(service.serviceId),
                    characteristicUuid: normalizeUuid(
                      characteristic.characteristicId,
                    ),
                    properties: {
                      if (characteristic.isReadable)
                        BleCharacteristicProperty.read,
                      if (characteristic.isWritableWithResponse)
                        BleCharacteristicProperty.write,
                      if (characteristic.isWritableWithoutResponse)
                        BleCharacteristicProperty.writeWithoutResponse,
                      if (characteristic.isNotifiable)
                        BleCharacteristicProperty.notify,
                      if (characteristic.isIndicatable)
                        BleCharacteristicProperty.indicate,
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
    },
  );

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) {
    _ensureNotDisposed();
    return _manage<List<int>, Uint8List>(
      source: () => _backend.subscribeToCharacteristic(
        _qualified(deviceId, characteristic),
      ),
      mapValue: (value) => Uint8List.fromList(value).asUnmodifiableView(),
      mapError: (error) => _failure(
        BleFailureCode.subscriptionFailed,
        'BLE subscription failed.',
        error,
      ),
    );
  }

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List value, {
    required BleWriteMode mode,
  }) => _guard(
    BleFailureCode.writeFailed,
    'BLE characteristic write failed.',
    () async {
      _ensureNotDisposed();
      await _backend.writeCharacteristic(
        _qualified(deviceId, characteristic),
        value: Uint8List.fromList(value),
        withResponse: mode == BleWriteMode.withResponse,
      );
    },
  );

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int mtu) =>
      _guard(BleFailureCode.mtuFailed, 'BLE MTU request failed.', () {
        _ensureNotDisposed();
        return _backend.requestMtu(deviceId: deviceId.value, mtu: mtu);
      });

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    final resources = _resources.toList(growable: false);
    final connections = _connections.values.toList(growable: false);
    await Future.wait<void>([
      ...resources.map((resource) => resource.close()),
      ...connections.map(
        (connection) => connection.disconnect(emitDisconnected: false),
      ),
    ], eagerError: false);
    _resources.clear();
    _scans.clear();
    _connections.clear();
  }

  Stream<TOutput> _manage<TInput, TOutput>({
    required Stream<TInput> Function() source,
    required TOutput Function(TInput) mapValue,
    Object Function(Object)? mapError,
    bool distinct = false,
  }) {
    late final _ManagedOperation<TInput, TOutput> operation;
    operation = _ManagedOperation(
      source: () {
        _ensureNotDisposed();
        return source();
      },
      mapValue: mapValue,
      mapError: mapError,
      distinct: distinct,
      onStarted: () => _resources.add(operation),
      onClosed: () => _resources.remove(operation),
    );
    return operation.stream;
  }

  BleAdvertisement _mapAdvertisement(DiscoveredDevice device) {
    final serviceUuids = <String>{
      ...device.serviceUuids.map(normalizeUuid),
      ...device.serviceData.keys.map(normalizeUuid),
    };
    return BleAdvertisement(
      deviceId: BleDeviceId(device.id),
      name: device.name,
      rssi: device.rssi,
      manufacturerData: device.manufacturerData,
      serviceUuids: serviceUuids.toList(growable: false),
    );
  }

  QualifiedCharacteristic _qualified(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) => QualifiedCharacteristic(
    deviceId: deviceId.value,
    serviceId: Uuid.parse(characteristic.serviceUuid),
    characteristicId: Uuid.parse(characteristic.characteristicUuid),
  );

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const BleFailure(
        code: BleFailureCode.invalidState,
        message: 'ReactiveBleTransport has been disposed.',
      );
    }
  }
}

abstract interface class _ManagedResource {
  Future<void> close();
}

final class _ManagedOperation<TInput, TOutput> implements _ManagedResource {
  _ManagedOperation({
    required this.source,
    required this.mapValue,
    required this.onStarted,
    required this.onClosed,
    this.mapError,
    this.totalTimeout,
    this.timeoutError,
    this.distinct = false,
  }) {
    _controller = StreamController<TOutput>(
      onListen: _start,
      onCancel: _cancelFromListener,
    );
  }

  final Stream<TInput> Function() source;
  final TOutput Function(TInput) mapValue;
  final Object Function(Object)? mapError;
  final Duration? totalTimeout;
  final Object Function()? timeoutError;
  final bool distinct;
  final void Function() onStarted;
  final void Function() onClosed;

  late final StreamController<TOutput> _controller;
  StreamSubscription<TInput>? _subscription;
  Timer? _timer;
  Future<void>? _closeFuture;
  Object? _lastValue;
  bool _hasLastValue = false;
  bool _closingController = false;

  Stream<TOutput> get stream => _controller.stream;

  void _start() {
    if (_closeFuture != null) {
      return;
    }
    final timeout = totalTimeout;
    if (timeout != null) {
      _timer = Timer(timeout, _onTimeout);
    }
    try {
      final stream = source();
      onStarted();
      _subscription = stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  void _onData(TInput value) {
    if (_closeFuture != null || _controller.isClosed) {
      return;
    }
    final mapped = mapValue(value);
    if (distinct && _hasLastValue && mapped == _lastValue) {
      return;
    }
    _hasLastValue = true;
    _lastValue = mapped;
    _controller.add(mapped);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_closeFuture != null || _controller.isClosed) {
      return;
    }
    _controller.addError(mapError?.call(error) ?? error, stackTrace);
    unawaited(close().catchError((_) {}));
  }

  void _onDone() {
    unawaited(close().catchError((_) {}));
  }

  void _onTimeout() {
    if (_closeFuture != null || _controller.isClosed) {
      return;
    }
    _controller.addError(
      timeoutError?.call() ??
          TimeoutException('Managed stream timed out.', totalTimeout),
    );
    unawaited(close().catchError((_) {}));
  }

  @override
  Future<void> close() => _closeFuture ??= _close(closeController: true);

  Future<void> _cancelFromListener() {
    if (_closingController) {
      return Future<void>.value();
    }
    return _closeFuture ??= _close(closeController: false);
  }

  Future<void> _close({required bool closeController}) async {
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    _timer?.cancel();
    try {
      await _subscription?.cancel();
    } catch (error, stackTrace) {
      cancellationError = mapError?.call(error) ?? error;
      cancellationStackTrace = stackTrace;
    } finally {
      if (closeController && !_controller.isClosed) {
        _closingController = true;
        await _controller.close();
      }
      onClosed();
    }
    if (cancellationError != null) {
      Error.throwWithStackTrace(
        cancellationError,
        cancellationStackTrace ?? StackTrace.current,
      );
    }
  }
}

final class _ConnectionSession {
  _ConnectionSession({
    required this.deviceId,
    required this.source,
    required this.onClosed,
  });

  final BleDeviceId deviceId;
  final Stream<ConnectionStateUpdate> Function() source;
  final void Function() onClosed;

  final Set<_ConnectionView> _views = {};
  StreamSubscription<ConnectionStateUpdate>? _subscription;
  BleConnectionUpdate? _latest;
  Future<void>? _closeFuture;
  bool _started = false;

  Stream<BleConnectionUpdate> open(Duration timeout) {
    late final _ConnectionView view;
    view = _ConnectionView(
      deviceId: deviceId,
      timeout: timeout,
      onListen: () => _attach(view),
      onCancel: () => _detach(view),
    );
    return view.stream;
  }

  void _attach(_ConnectionView view) {
    if (_closeFuture != null) {
      view.close();
      return;
    }
    _views.add(view);
    final latest = _latest;
    if (latest != null) {
      view.add(latest);
    }
    if (!_started) {
      _start();
    }
  }

  Future<void> _detach(_ConnectionView view) async {
    _views.remove(view);
    if (_views.isEmpty) {
      await disconnect(emitDisconnected: false);
    }
  }

  void _start() {
    _started = true;
    try {
      _subscription = source().listen(
        _onUpdate,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  void _onUpdate(ConnectionStateUpdate update) {
    if (_closeFuture != null) {
      return;
    }
    final mapped = BleConnectionUpdate(
      deviceId: deviceId,
      status: mapConnectionState(update.connectionState),
      failure: update.failure == null
          ? null
          : BleFailure(
              code: BleFailureCode.connectionFailed,
              message: update.failure!.message,
              cause: update.failure,
            ),
    );
    _latest = mapped;
    for (final view in _views.toList(growable: false)) {
      view.add(mapped);
    }
    if (mapped.status == BleConnectionStatus.disconnected) {
      unawaited(disconnect(emitDisconnected: false).catchError((_) {}));
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_closeFuture != null) {
      return;
    }
    final update = BleConnectionUpdate(
      deviceId: deviceId,
      status: BleConnectionStatus.disconnected,
      failure: _failure(
        BleFailureCode.connectionFailed,
        'BLE connection failed.',
        error,
      ),
    );
    _latest = update;
    for (final view in _views.toList(growable: false)) {
      view.add(update);
    }
    unawaited(disconnect(emitDisconnected: false).catchError((_) {}));
  }

  void _onDone() {
    unawaited(disconnect(emitDisconnected: true).catchError((_) {}));
  }

  Future<void> disconnect({required bool emitDisconnected}) =>
      _closeFuture ??= _disconnect(emitDisconnected: emitDisconnected);

  Future<void> _disconnect({required bool emitDisconnected}) async {
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    try {
      await _subscription?.cancel();
    } catch (error, stackTrace) {
      cancellationError = _failure(
        BleFailureCode.connectionFailed,
        'BLE connection cancellation failed.',
        error,
      );
      cancellationStackTrace = stackTrace;
    } finally {
      if (emitDisconnected &&
          _latest?.status != BleConnectionStatus.disconnected) {
        final update = BleConnectionUpdate(
          deviceId: deviceId,
          status: BleConnectionStatus.disconnected,
          failure: cancellationError is BleFailure ? cancellationError : null,
        );
        _latest = update;
        for (final view in _views.toList(growable: false)) {
          view.add(update);
        }
      }
      final views = _views.toList(growable: false);
      _views.clear();
      await Future.wait(views.map((view) => view.close()));
      onClosed();
    }
    if (cancellationError != null) {
      Error.throwWithStackTrace(
        cancellationError,
        cancellationStackTrace ?? StackTrace.current,
      );
    }
  }
}

final class _ConnectionView {
  _ConnectionView({
    required this.deviceId,
    required this.timeout,
    required void Function() onListen,
    required Future<void> Function() onCancel,
  }) : _onCancel = onCancel {
    _controller = StreamController<BleConnectionUpdate>(
      onListen: () {
        _timer = Timer(timeout, _onTimeout);
        onListen();
      },
      onCancel: _cancel,
    );
  }

  final BleDeviceId deviceId;
  final Duration timeout;
  final Future<void> Function() _onCancel;

  late final StreamController<BleConnectionUpdate> _controller;
  Timer? _timer;
  Future<void>? _closeFuture;
  bool _closingFromSession = false;

  Stream<BleConnectionUpdate> get stream => _controller.stream;

  void add(BleConnectionUpdate update) {
    if (_closeFuture != null || _controller.isClosed) {
      return;
    }
    if (update.status == BleConnectionStatus.connected ||
        update.status == BleConnectionStatus.disconnected) {
      _timer?.cancel();
    }
    _controller.add(update);
  }

  void _onTimeout() {
    if (_closeFuture != null || _controller.isClosed) {
      return;
    }
    _controller.add(
      BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.disconnected,
        failure: _failure(
          BleFailureCode.connectionFailed,
          'BLE connection timed out.',
          TimeoutException('BLE connection timed out.', timeout),
        ),
      ),
    );
    unawaited(_expire());
  }

  Future<void> _expire() async {
    await _onCancel();
    await close();
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_closingFromSession) {
      return;
    }
    await _onCancel();
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _timer?.cancel();
    _closingFromSession = true;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

Future<void> _closeResources(List<_ManagedResource> resources) =>
    Future.wait<void>(
      resources.map((resource) => resource.close()),
      eagerError: false,
    );

Future<T> _guard<T>(
  BleFailureCode code,
  String message,
  Future<T> Function() operation,
) async {
  try {
    return await operation();
  } catch (error) {
    throw _failure(code, message, error);
  }
}

BleFailure _failure(BleFailureCode code, String message, Object error) =>
    error is BleFailure
    ? error
    : BleFailure(code: code, message: message, cause: error);

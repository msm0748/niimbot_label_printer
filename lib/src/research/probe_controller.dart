import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../ble/ble_failure.dart';
import '../ble/ble_models.dart';
import '../ble/ble_transport.dart';
import '../label/monochrome_raster.dart';
import 'captured_test_print.dart';
import 'd11h_raster_encoder.dart';
import 'hex_codec.dart';
import 'probe_event.dart';

enum _ProbeLifecycle {
  idle,
  scanning,
  connecting,
  connected,
  disconnecting,
  faulted,
  disposed,
}

final class _MonotonicDeadline {
  _MonotonicDeadline(this.total) : _stopwatch = Stopwatch()..start();

  final Duration total;
  final Stopwatch _stopwatch;

  Duration get remaining {
    final value = total - _stopwatch.elapsed;
    return value > Duration.zero ? value : Duration.zero;
  }
}

final class _DroppingEventBroadcaster {
  final Set<_DroppingEventListener> _listeners = <_DroppingEventListener>{};
  var _closed = false;

  late final Stream<ProbeEvent> stream = _DroppingEventStream(this);

  StreamSubscription<ProbeEvent> listen(
    void Function(ProbeEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late final _DroppingEventListener listener;
    listener = _DroppingEventListener(
      onListen: () {
        if (_closed) {
          unawaited(listener.close());
        } else {
          _listeners.add(listener);
        }
      },
      onCancel: () => _listeners.remove(listener),
    );
    return listener.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  void add(ProbeEvent event) {
    if (_closed) {
      return;
    }
    for (final listener in _listeners.toList(growable: false)) {
      listener.add(event);
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      unawaited(listener.close());
    }
  }
}

final class _DroppingEventStream extends Stream<ProbeEvent> {
  const _DroppingEventStream(this._broadcaster);

  final _DroppingEventBroadcaster _broadcaster;

  @override
  StreamSubscription<ProbeEvent> listen(
    void Function(ProbeEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _broadcaster.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

final class _DroppingEventListener {
  _DroppingEventListener({
    required void Function() onListen,
    required void Function() onCancel,
  }) : _onCancel = onCancel {
    _controller = StreamController<ProbeEvent>(
      sync: true,
      onListen: onListen,
      onPause: () => _paused = true,
      onResume: () => _paused = false,
      onCancel: onCancel,
    );
  }

  final void Function() _onCancel;
  late final StreamController<ProbeEvent> _controller;
  var _paused = false;
  var _closed = false;

  Stream<ProbeEvent> get stream => _controller.stream;

  void add(ProbeEvent event) {
    if (!_closed && !_paused) {
      _controller.add(event);
    }
  }

  Future<void> close() {
    if (_closed) {
      return Future<void>.value();
    }
    _closed = true;
    _onCancel();
    return _controller.close();
  }
}

final class ProbeController {
  ProbeController(
    this._transport, {
    int maxEvents = 1000,
    Duration cleanupTimeout = const Duration(seconds: 2),
  }) : _maxEvents = _validatePositiveInt(maxEvents, 'maxEvents'),
       _cleanupTimeout = _validatePositiveDuration(
         cleanupTimeout,
         'cleanupTimeout',
       ),
       _readiness = _transport.currentReadiness {
    _readinessSubscription = _transport.readiness.listen(
      (readiness) {
        if (_lifecycle == _ProbeLifecycle.disposed) {
          return;
        }
        _readiness = readiness;
        _record(ProbeEventKind.readiness, readiness.name);
      },
      onError: (Object error) {
        if (_lifecycle != _ProbeLifecycle.disposed) {
          _recordError('readiness failed', error);
        }
      },
    );
  }

  static const int _maxNotificationLogBytes = 256;

  final BleTransport _transport;
  final int _maxEvents;
  final Duration _cleanupTimeout;
  final Map<BleDeviceId, BleAdvertisement> _devices =
      <BleDeviceId, BleAdvertisement>{};
  final List<ProbeEvent> _events = <ProbeEvent>[];
  final _DroppingEventBroadcaster _eventBroadcaster =
      _DroppingEventBroadcaster();
  final StreamController<Uint8List> _protocolNotifications =
      StreamController<Uint8List>.broadcast(sync: true);
  final Map<String, StreamSubscription<Uint8List>> _notificationSubscriptions =
      <String, StreamSubscription<Uint8List>>{};

  late final StreamSubscription<BleReadiness> _readinessSubscription;
  StreamSubscription<BleAdvertisement>? _scanSubscription;
  StreamSubscription<BleConnectionUpdate>? _connectionSubscription;
  Future<void>? _scanFuture;
  Future<void>? _scanStopFuture;
  Completer<void>? _scanCompleter;
  Future<void>? _connectFuture;
  Completer<void>? _connectCompleter;
  Future<void>? _connectionCleanupFuture;
  Timer? _connectionTimer;
  Future<void>? _disconnectFuture;
  Future<void>? _disposeFuture;
  Future<void>? _transportDisposeFuture;
  BleDeviceId? _connectionDevice;
  var _connectionGeneration = 0;
  var _connectionSetupStarted = false;
  var _printingCapturedTestLabel = false;
  var _lifecycle = _ProbeLifecycle.idle;

  BleReadiness _readiness;
  BleDeviceId? _connectedDevice;
  List<BleService> _services = const <BleService>[];
  int? _mtu;

  List<BleAdvertisement> get devices =>
      List<BleAdvertisement>.unmodifiable(_devices.values);
  List<ProbeEvent> get events => List<ProbeEvent>.unmodifiable(_events);
  Stream<ProbeEvent> get eventStream => _eventBroadcaster.stream;
  BleReadiness get readiness => _readiness;
  BleDeviceId? get connectedDevice => _connectedDevice;
  List<BleService> get services => _services;
  int? get mtu => _mtu;

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) {
    if (_lifecycle == _ProbeLifecycle.scanning) {
      return _scanFuture!;
    }
    if (_lifecycle != _ProbeLifecycle.idle) {
      return Future<void>.error(_invalidLifecycle('start a scan'));
    }

    final completer = Completer<void>();
    _lifecycle = _ProbeLifecycle.scanning;
    _scanCompleter = completer;
    _scanFuture = completer.future;

    try {
      _scanSubscription = _transport
          .scan(timeout: timeout)
          .listen(
            (advertisement) {
              if (_scanCompleter != completer ||
                  _lifecycle == _ProbeLifecycle.disposed) {
                return;
              }
              _devices[advertisement.deviceId] = advertisement;
              _record(
                ProbeEventKind.scan,
                'device discovered rssi=${advertisement.rssi} '
                'namePresent=${advertisement.name?.isNotEmpty ?? false}',
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              if (_scanCompleter != completer) {
                return;
              }
              unawaited(
                _terminateScan(
                  error: error,
                  stackTrace: stackTrace,
                  errorPrefix: 'scan failed',
                  cancelSubscription: true,
                  stopTransport: true,
                ),
              );
            },
            onDone: () {
              if (_scanCompleter == completer) {
                unawaited(
                  _terminateScan(
                    cancelSubscription: false,
                    stopTransport: false,
                  ),
                );
              }
            },
          );
    } catch (error, stackTrace) {
      unawaited(
        _terminateScan(
          error: error,
          stackTrace: stackTrace,
          errorPrefix: 'scan failed',
          cancelSubscription: true,
          stopTransport: true,
        ),
      );
    }

    return completer.future;
  }

  Future<void> stopScan() {
    if (_lifecycle == _ProbeLifecycle.disposed) {
      return Future<void>.error(_disposedError());
    }
    if (_lifecycle == _ProbeLifecycle.faulted) {
      return Future<void>.error(_invalidLifecycle('stop a scan'));
    }
    return _stopScanForLifecycle();
  }

  Future<void> _stopScanForLifecycle() =>
      _terminateScan(cancelSubscription: true, stopTransport: true);

  Future<void> _terminateScan({
    Object? error,
    StackTrace? stackTrace,
    String? errorPrefix,
    required bool cancelSubscription,
    required bool stopTransport,
  }) {
    final active = _scanStopFuture;
    if (active != null) {
      return active;
    }
    if (_scanSubscription == null && _scanCompleter == null) {
      return Future<void>.value();
    }

    late final Future<void> operation;
    operation =
        _performScanTermination(
          error: error,
          stackTrace: stackTrace,
          errorPrefix: errorPrefix,
          cancelSubscription: cancelSubscription,
          stopTransport: stopTransport,
        ).whenComplete(() {
          if (identical(_scanStopFuture, operation)) {
            _scanStopFuture = null;
          }
        });
    _scanStopFuture = operation;
    return operation;
  }

  Future<void> _performScanTermination({
    Object? error,
    StackTrace? stackTrace,
    String? errorPrefix,
    required bool cancelSubscription,
    required bool stopTransport,
  }) async {
    Object? cleanupFailure;
    StackTrace? cleanupStackTrace;
    var timedOut = false;
    final subscription = _scanSubscription;

    if (cancelSubscription) {
      try {
        final cancellation = subscription?.cancel() ?? Future<void>.value();
        await cancellation.timeout(_cleanupTimeout);
      } on TimeoutException catch (timeout, timeoutStack) {
        timedOut = true;
        cleanupFailure ??= timeout;
        cleanupStackTrace ??= timeoutStack;
        _record(
          ProbeEventKind.error,
          'scan cleanup timed out after '
          '${_cleanupTimeout.inMilliseconds}ms',
        );
      } catch (cleanupError, cleanupStack) {
        cleanupFailure = cleanupError;
        cleanupStackTrace = cleanupStack;
        _recordError('scan cleanup failed', cleanupError);
      }
    }

    if (stopTransport) {
      try {
        await _transport.stopScan().timeout(_cleanupTimeout);
      } on TimeoutException catch (timeout, timeoutStack) {
        timedOut = true;
        cleanupFailure ??= timeout;
        cleanupStackTrace ??= timeoutStack;
        _record(
          ProbeEventKind.error,
          'scan cleanup timed out after '
          '${_cleanupTimeout.inMilliseconds}ms',
        );
      } catch (cleanupError, cleanupStack) {
        cleanupFailure ??= cleanupError;
        cleanupStackTrace ??= cleanupStack;
        _recordError('scan cleanup failed', cleanupError);
      }
    }

    final completer = _scanCompleter;
    _scanSubscription = null;
    _scanCompleter = null;
    _scanFuture = null;
    if (timedOut) {
      _quarantine();
    } else if (_lifecycle == _ProbeLifecycle.scanning) {
      _lifecycle = _ProbeLifecycle.idle;
    }

    if (error != null) {
      _recordError(errorPrefix ?? 'scan failed', error);
    }

    if (completer == null || completer.isCompleted) {
      return;
    }
    if (error != null) {
      completer.completeError(error, stackTrace);
    } else if (cleanupFailure != null) {
      completer.completeError(cleanupFailure, cleanupStackTrace);
    } else {
      completer.complete();
    }
  }

  Future<void> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_lifecycle == _ProbeLifecycle.connecting &&
        _connectionDevice == deviceId) {
      return _connectFuture!;
    }
    if (_lifecycle != _ProbeLifecycle.idle &&
        _lifecycle != _ProbeLifecycle.scanning) {
      return Future<void>.error(_invalidLifecycle('connect'));
    }

    final completer = Completer<void>();
    final generation = ++_connectionGeneration;
    final deadline = _MonotonicDeadline(timeout);
    _lifecycle = _ProbeLifecycle.connecting;
    _connectionDevice = deviceId;
    _connectionSetupStarted = false;
    _connectCompleter = completer;
    _connectFuture = completer.future;
    _connectionTimer = Timer(timeout, () {
      _startConnectionFailure(
        generation,
        _connectionTimeoutFailure(timeout),
        StackTrace.current,
        prefix: 'connection timed out',
      );
    });

    if (_scanSubscription == null &&
        _scanCompleter == null &&
        _scanStopFuture == null) {
      _listenForConnection(deviceId, deadline, generation);
    } else {
      unawaited(_beginConnection(deviceId, deadline, generation));
    }
    return completer.future;
  }

  Future<void> _beginConnection(
    BleDeviceId deviceId,
    _MonotonicDeadline deadline,
    int generation,
  ) async {
    try {
      await _stopScanForLifecycle();
      if (!_isCurrentConnection(generation, deviceId)) {
        return;
      }
      _listenForConnection(deviceId, deadline, generation);
    } catch (error, stackTrace) {
      _startConnectionFailure(
        generation,
        error,
        stackTrace,
        prefix: 'connection failed',
      );
    }
  }

  void _listenForConnection(
    BleDeviceId deviceId,
    _MonotonicDeadline deadline,
    int generation,
  ) {
    try {
      _connectionSubscription = _transport
          .connect(deviceId, timeout: _remaining(deadline))
          .listen(
            (update) => _handleConnectionUpdate(update, generation, deadline),
            onError: (Object error, StackTrace stackTrace) {
              _startConnectionFailure(
                generation,
                error,
                stackTrace,
                prefix: 'connection failed',
              );
            },
            onDone: () {
              if (_isCurrentConnection(generation, deviceId)) {
                _startConnectionFailure(
                  generation,
                  StateError('Connection ended before explicit disconnect.'),
                  StackTrace.current,
                  prefix: 'connection ended',
                );
              }
            },
          );
    } catch (error, stackTrace) {
      _startConnectionFailure(
        generation,
        error,
        stackTrace,
        prefix: 'connection failed',
      );
    }
  }

  void _handleConnectionUpdate(
    BleConnectionUpdate update,
    int generation,
    _MonotonicDeadline deadline,
  ) {
    if (!_isCurrentConnection(generation, update.deviceId)) {
      return;
    }

    _record(ProbeEventKind.connection, update.status.name);
    switch (update.status) {
      case BleConnectionStatus.connected:
        if (_connectionSetupStarted) {
          return;
        }
        _connectionSetupStarted = true;
        unawaited(
          _completeConnectionSetup(update.deviceId, generation, deadline),
        );
      case BleConnectionStatus.disconnected:
        _startConnectionFailure(
          generation,
          update.failure ??
              StateError('Device disconnected before setup completed.'),
          StackTrace.current,
          prefix: 'connection disconnected',
        );
      case BleConnectionStatus.connecting:
      case BleConnectionStatus.disconnecting:
        return;
    }
  }

  Future<void> _completeConnectionSetup(
    BleDeviceId deviceId,
    int generation,
    _MonotonicDeadline deadline,
  ) async {
    try {
      final discovered = await _transport
          .discoverServices(deviceId)
          .timeout(
            _remaining(deadline),
            onTimeout: () => throw _connectionTimeoutFailure(deadline.total),
          );
      if (!_isCurrentConnection(generation, deviceId)) {
        return;
      }
      _services = List<BleService>.unmodifiable(discovered);
      _record(ProbeEventKind.serviceDiscovery, 'services=${_services.length}');

      final negotiatedMtu = await _transport
          .requestMtu(deviceId, 247)
          .timeout(
            _remaining(deadline),
            onTimeout: () => throw _connectionTimeoutFailure(deadline.total),
          );
      if (!_isCurrentConnection(generation, deviceId)) {
        return;
      }
      _mtu = negotiatedMtu;
      _record(ProbeEventKind.mtu, 'negotiated=$negotiatedMtu');
      _completeConnection(deviceId);
    } catch (error, stackTrace) {
      _startConnectionFailure(
        generation,
        error,
        stackTrace,
        prefix: 'connection setup failed',
      );
    }
  }

  bool _isCurrentConnection(int generation, BleDeviceId deviceId) =>
      _lifecycle == _ProbeLifecycle.connecting &&
      generation == _connectionGeneration &&
      _connectionDevice == deviceId;

  void _completeConnection(BleDeviceId deviceId) {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _connectedDevice = deviceId;
    _lifecycle = _ProbeLifecycle.connected;
    final completer = _connectCompleter;
    _connectCompleter = null;
    _connectFuture = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _startConnectionFailure(
    int generation,
    Object error,
    StackTrace stackTrace, {
    required String prefix,
  }) {
    if (generation != _connectionGeneration ||
        _lifecycle == _ProbeLifecycle.disconnecting ||
        _lifecycle == _ProbeLifecycle.disposed) {
      return;
    }

    _connectionGeneration++;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _recordError(prefix, error);
    final completer = _connectCompleter;
    final deviceId = _connectedDevice ?? _connectionDevice;
    _connectCompleter = null;
    _connectFuture = null;
    _lifecycle = _ProbeLifecycle.disconnecting;
    _clearPublicConnectionState();

    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }

    late final Future<void> cleanup;
    cleanup = _performConnectionFailureCleanup(deviceId).whenComplete(() {
      if (identical(_connectionCleanupFuture, cleanup)) {
        _connectionCleanupFuture = null;
      }
    });
    _connectionCleanupFuture = cleanup;
  }

  Future<void> _performConnectionFailureCleanup(BleDeviceId? deviceId) async {
    final deadline = _MonotonicDeadline(_cleanupTimeout);
    var timedOut = false;

    timedOut |= await _cancelNotificationSubscriptionsBounded(
      deadline,
      'connection cleanup',
    );
    timedOut |= await _runBoundedCleanupAction(
      deadline,
      'connection cleanup',
      () {
        final subscription = _connectionSubscription;
        _connectionSubscription = null;
        return subscription?.cancel() ?? Future<void>.value();
      },
    );
    if (deviceId != null) {
      timedOut |= await _runBoundedCleanupAction(
        deadline,
        'connection cleanup',
        () => _transport.disconnect(deviceId),
      );
    }

    _resetConnectionInternals();
    if (timedOut) {
      _quarantine();
    } else if (_lifecycle == _ProbeLifecycle.disconnecting) {
      _lifecycle = _ProbeLifecycle.idle;
    }
  }

  Future<bool> _cancelNotificationSubscriptionsBounded(
    _MonotonicDeadline deadline,
    String prefix,
  ) async {
    final subscriptions = _notificationSubscriptions.values.toList();
    _notificationSubscriptions.clear();
    final cancellations = <Future<void>>[];
    for (final subscription in subscriptions) {
      try {
        cancellations.add(subscription.cancel());
      } catch (error) {
        _recordError('$prefix failed', error);
      }
    }

    var timedOut = false;
    for (final cancellation in cancellations) {
      timedOut |= await _awaitBoundedCleanup(deadline, prefix, cancellation);
    }
    return timedOut;
  }

  Future<bool> _runBoundedCleanupAction(
    _MonotonicDeadline deadline,
    String prefix,
    Future<void> Function() action,
  ) async {
    try {
      return _awaitBoundedCleanup(deadline, prefix, action());
    } catch (error) {
      _recordError('$prefix failed', error);
      return false;
    }
  }

  Future<bool> _awaitBoundedCleanup(
    _MonotonicDeadline deadline,
    String prefix,
    Future<void> future,
  ) async {
    final remaining = deadline.remaining;
    if (remaining == Duration.zero) {
      _record(
        ProbeEventKind.error,
        '$prefix timed out after ${_cleanupTimeout.inMilliseconds}ms',
      );
      return true;
    }
    try {
      await future.timeout(remaining);
      return false;
    } on TimeoutException {
      _record(
        ProbeEventKind.error,
        '$prefix timed out after ${_cleanupTimeout.inMilliseconds}ms',
      );
      return true;
    } catch (error) {
      _recordError('$prefix failed', error);
      return false;
    }
  }

  Future<void> subscribe(BleCharacteristic characteristic) async {
    _ensureConnected('subscribe');
    final deviceId = _connectedDevice!;
    if (!characteristic.canNotify) {
      throw StateError('Characteristic does not support notifications.');
    }

    final key = _characteristicKey(characteristic);
    if (_notificationSubscriptions.containsKey(key)) {
      return;
    }

    try {
      final subscription = _transport
          .subscribe(deviceId, characteristic)
          .listen(
            (bytes) {
              final immutableBytes = Uint8List.fromList(
                bytes,
              ).asUnmodifiableView();
              _record(
                ProbeEventKind.notification,
                '${characteristic.characteristicUuid} '
                '${_formatPayload(immutableBytes)}',
              );
              _protocolNotifications.add(immutableBytes);
            },
            onError: (Object error) {
              _recordError('subscription failed', error);
            },
            onDone: () {
              _notificationSubscriptions.remove(key);
            },
          );
      _notificationSubscriptions[key] = subscription;
      _record(ProbeEventKind.subscription, characteristic.characteristicUuid);
    } catch (error) {
      _recordError('subscription failed', error);
      rethrow;
    }
  }

  Future<void> writeHex(
    BleCharacteristic characteristic,
    String hex, {
    required BleWriteMode mode,
  }) async {
    _ensureConnected('write');
    final deviceId = _connectedDevice!;
    final supportsMode = switch (mode) {
      BleWriteMode.withResponse => characteristic.properties.contains(
        BleCharacteristicProperty.write,
      ),
      BleWriteMode.withoutResponse => characteristic.properties.contains(
        BleCharacteristicProperty.writeWithoutResponse,
      ),
    };
    if (!supportsMode) {
      throw StateError('Characteristic does not support ${mode.name}.');
    }

    final bytes = parseHexBytes(hex);
    if (bytes.isEmpty) {
      throw ArgumentError.value(hex, 'hex', 'Write bytes must not be empty.');
    }

    try {
      await _transport.write(deviceId, characteristic, bytes, mode: mode);
      _record(
        ProbeEventKind.write,
        '${characteristic.characteristicUuid} ${_formatPayload(bytes)}',
      );
    } catch (error) {
      _recordError('write failed', error);
      rethrow;
    }
  }

  Future<void> printCapturedTestLabel(
    BleCharacteristic characteristic, {
    Duration interWriteDelay = const Duration(milliseconds: 80),
    Duration statusPollDelay = const Duration(milliseconds: 250),
    Duration responseTimeout = const Duration(seconds: 2),
    int maxStatusPolls = 20,
  }) async {
    _ensureConnected('print a captured test label');
    if (_printingCapturedTestLabel) {
      throw StateError('A captured test print is already in progress.');
    }
    if (!characteristic.canNotify ||
        !characteristic.properties.contains(
          BleCharacteristicProperty.writeWithoutResponse,
        )) {
      throw StateError(
        'Captured test printing requires notify and writeWithoutResponse.',
      );
    }

    final writes = capturedTestPrintWrites(sessionId: _newSessionId());
    final largestWrite = writes.fold<int>(
      0,
      (largest, write) => write.length > largest ? write.length : largest,
    );
    final mtu = _mtu;
    if (mtu == null || mtu < largestWrite + 3) {
      throw StateError(
        'Captured test printing requires MTU ${largestWrite + 3} or larger; '
        'negotiated MTU is ${mtu ?? 'unknown'}.',
      );
    }

    _printingCapturedTestLabel = true;
    try {
      await subscribe(characteristic);
      final deviceId = _connectedDevice!;

      const expectedResponses = <int>[
        0x00,
        0x33,
        0x31,
        0x02,
        0x14,
        0xB3,
        0xD3,
        0xB3,
        0xD3,
        0xE4,
      ];
      for (var index = 0; index < writes.length; index++) {
        await _writeAndWaitForCommand(
          deviceId,
          characteristic,
          writes[index],
          expectedResponses[index],
          responseTimeout,
        );
        if (index < writes.length - 1) {
          await Future<void>.delayed(interWriteDelay);
        }
      }

      var completed = false;
      for (var poll = 0; poll < maxStatusPolls; poll++) {
        final status = await _writeAndWaitForCommand(
          deviceId,
          characteristic,
          buildD11hCommand(0xA3, const <int>[0x01]),
          0xB3,
          responseTimeout,
        );
        if (_isCompletedPrintStatus(status)) {
          completed = true;
          break;
        }
        await Future<void>.delayed(statusPollDelay);
      }
      if (!completed) {
        throw TimeoutException(
          'Printer did not report print completion.',
          statusPollDelay * maxStatusPolls,
        );
      }

      await _writeAndWaitForCommand(
        deviceId,
        characteristic,
        buildD11hCommand(0xF3, const <int>[0x01]),
        0xF4,
        responseTimeout,
      );
      await _writeAndWaitForCommand(
        deviceId,
        characteristic,
        buildD11hCommand(0x19, const <int>[0x01, 0x01]),
        0x00,
        responseTimeout,
      );
    } catch (error) {
      _recordError('captured test print failed', error);
      rethrow;
    } finally {
      _printingCapturedTestLabel = false;
    }
  }

  Future<void> printRaster(
    BleCharacteristic characteristic,
    MonochromeRaster raster, {
    int density = 3,
    int labelType = 1,
    int quantity = 1,
    Duration interWriteDelay = const Duration(milliseconds: 10),
    Duration pageOpenDelay = const Duration(milliseconds: 30),
    Duration statusPollDelay = const Duration(milliseconds: 100),
    Duration responseTimeout = const Duration(seconds: 2),
    int maxStatusPolls = 50,
  }) async {
    _ensureConnected('print a raster label');
    if (_printingCapturedTestLabel) {
      throw StateError('A print is already in progress.');
    }
    if (!characteristic.canNotify ||
        !characteristic.properties.contains(
          BleCharacteristicProperty.writeWithoutResponse,
        )) {
      throw StateError(
        'Raster printing requires notify and writeWithoutResponse.',
      );
    }
    if (density < 1 || density > 5) {
      throw RangeError.range(density, 1, 5, 'density');
    }
    if (labelType < 1 || labelType > 3) {
      throw RangeError.range(labelType, 1, 3, 'labelType');
    }
    if (quantity < 1 || quantity > 0xFFFF) {
      throw RangeError.range(quantity, 1, 0xFFFF, 'quantity');
    }

    final rows = encodeD11hRasterRows(raster);
    final largestWrite = rows.fold<int>(
      0,
      (largest, row) => row.length > largest ? row.length : largest,
    );
    final mtu = _mtu;
    if (mtu == null || mtu < largestWrite + 3) {
      throw StateError(
        'Raster printing requires MTU ${largestWrite + 3} or larger; '
        'negotiated MTU is ${mtu ?? 'unknown'}.',
      );
    }

    _printingCapturedTestLabel = true;
    try {
      await subscribe(characteristic);
      final deviceId = _connectedDevice!;
      final setup = <(Uint8List, int)>[
        (buildD11hCommand(0x2C, const <int>[1]), 0x00),
        (buildD11hCommand(0x23, <int>[labelType]), 0x33),
        (buildD11hCommand(0x21, <int>[density]), 0x31),
        (
          buildD11hCommand(0x01, <int>[
            quantity >> 8,
            quantity & 0xFF,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          0x02,
        ),
      ];
      for (final (command, expectedResponse) in setup) {
        await _writeAndWaitForCommand(
          deviceId,
          characteristic,
          command,
          expectedResponse,
          responseTimeout,
        );
      }

      await _writeWithoutResponse(
        deviceId,
        characteristic,
        buildD11hCommand(0xA3, const <int>[1]),
      );
      if (pageOpenDelay > Duration.zero) {
        await Future<void>.delayed(pageOpenDelay);
      }

      await _writeAndWaitForCommand(
        deviceId,
        characteristic,
        buildD11hCommand(0x13, <int>[
          raster.height >> 8,
          raster.height & 0xFF,
          raster.width >> 8,
          raster.width & 0xFF,
          quantity >> 8,
          quantity & 0xFF,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
        0x14,
        responseTimeout,
      );

      for (final row in rows) {
        await _writeWithoutResponse(deviceId, characteristic, row);
        if (interWriteDelay > Duration.zero) {
          await Future<void>.delayed(interWriteDelay);
        }
      }

      await _writeAndWaitForCommand(
        deviceId,
        characteristic,
        buildD11hCommand(0xE3, const <int>[1]),
        0xE4,
        responseTimeout,
      );

      var completed = false;
      for (var poll = 0; poll < maxStatusPolls; poll++) {
        final status = await _writeAndWaitForCommand(
          deviceId,
          characteristic,
          buildD11hCommand(0xA3, const <int>[1]),
          0xB3,
          responseTimeout,
        );
        if (_printedPageCount(status) >= quantity) {
          completed = true;
          break;
        }
        await Future<void>.delayed(statusPollDelay);
      }
      if (!completed) {
        throw TimeoutException(
          'Printer did not report print completion.',
          statusPollDelay * maxStatusPolls,
        );
      }

      await _writeAndWaitForCommand(
        deviceId,
        characteristic,
        buildD11hCommand(0xF3, const <int>[1]),
        0xF4,
        responseTimeout,
      );
    } catch (error) {
      _recordError('raster print failed', error);
      rethrow;
    } finally {
      _printingCapturedTestLabel = false;
    }
  }

  Future<Uint8List> _writeAndWaitForCommand(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes,
    int expectedCommand,
    Duration timeout,
  ) async {
    final response = _protocolNotifications.stream
        .expand(splitD11hFrames)
        .firstWhere((frame) => frame[2] == expectedCommand)
        .timeout(timeout);
    await _transport.write(
      deviceId,
      characteristic,
      bytes,
      mode: BleWriteMode.withoutResponse,
    );
    _record(
      ProbeEventKind.write,
      '${characteristic.characteristicUuid} ${_formatPayload(bytes)}',
    );
    return response;
  }

  Future<void> _writeWithoutResponse(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) async {
    await _transport.write(
      deviceId,
      characteristic,
      bytes,
      mode: BleWriteMode.withoutResponse,
    );
    _record(
      ProbeEventKind.write,
      '${characteristic.characteristicUuid} ${_formatPayload(bytes)}',
    );
  }

  bool _isCompletedPrintStatus(Uint8List frame) =>
      frame.length >= 13 && frame[2] == 0xB3 && frame[5] == 0x01;

  int _printedPageCount(Uint8List frame) {
    if (frame.length < 11 || frame[2] != 0xB3 || frame[3] < 4) {
      throw const FormatException('Invalid D11H print status response.');
    }
    return frame[4] << 8 | frame[5];
  }

  String _newSessionId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  String exportSanitizedLog() =>
      _events.map((event) => event.toLogLine()).join('\n');

  Future<void> disconnect() {
    if (_lifecycle == _ProbeLifecycle.disposed) {
      return Future<void>.error(_disposedError());
    }
    if (_lifecycle == _ProbeLifecycle.faulted) {
      return Future<void>.error(_invalidLifecycle('disconnect'));
    }
    if (_lifecycle == _ProbeLifecycle.disconnecting) {
      return _connectionCleanupFuture ??
          _disconnectFuture ??
          Future<void>.value();
    }
    if (_lifecycle == _ProbeLifecycle.idle) {
      return Future<void>.value();
    }
    return _beginDisconnect();
  }

  Future<void> _beginDisconnect() {
    final active = _disconnectFuture;
    if (active != null) {
      return active;
    }

    final deviceId = _connectedDevice ?? _connectionDevice;
    final redactionIds = _captureKnownDeviceIds();
    _lifecycle = _ProbeLifecycle.disconnecting;
    _clearPublicConnectionState();
    _connectionGeneration++;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _completePendingConnectionWithDisconnect();

    late final Future<void> operation;
    operation = _performDisconnect(deviceId, redactionIds).whenComplete(() {
      if (identical(_disconnectFuture, operation)) {
        _disconnectFuture = null;
      }
    });
    _disconnectFuture = operation;
    return operation;
  }

  Future<void> _performDisconnect(
    BleDeviceId? deviceId,
    Set<String> redactionIds,
  ) async {
    final deadline = _MonotonicDeadline(_cleanupTimeout);
    Object? failure;
    StackTrace? failureStackTrace;
    var timedOut = false;

    Future<void> run(Future<void> Function() action) async {
      final remaining = deadline.remaining;
      try {
        await action().timeout(remaining);
      } on TimeoutException {
        timedOut = true;
        _record(
          ProbeEventKind.error,
          'disconnect cleanup timed out after '
          '${_cleanupTimeout.inMilliseconds}ms',
        );
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
        _recordError(
          'disconnect cleanup failed',
          error,
          redactionIds: redactionIds,
        );
      }
    }

    final subscriptions = _notificationSubscriptions.values.toList();
    _notificationSubscriptions.clear();
    final cancellations = <Future<void>>[];
    for (final subscription in subscriptions) {
      try {
        cancellations.add(subscription.cancel());
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
        _recordError(
          'disconnect cleanup failed',
          error,
          redactionIds: redactionIds,
        );
      }
    }
    for (final cancellation in cancellations) {
      await run(() => cancellation);
    }

    final connectionSubscription = _connectionSubscription;
    _connectionSubscription = null;
    await run(() => connectionSubscription?.cancel() ?? Future<void>.value());
    if (deviceId != null) {
      await run(() => _transport.disconnect(deviceId));
    }

    _resetConnectionInternals();
    if (timedOut) {
      _quarantine();
    } else if (_lifecycle == _ProbeLifecycle.disconnecting) {
      _lifecycle = _ProbeLifecycle.idle;
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStackTrace!);
    }
  }

  void _completePendingConnectionWithDisconnect() {
    final completer = _connectCompleter;
    _connectCompleter = null;
    _connectFuture = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('Connection attempt was disconnected.'),
        StackTrace.current,
      );
    }
  }

  void _clearPublicConnectionState() {
    _connectedDevice = null;
    _services = const <BleService>[];
    _mtu = null;
  }

  void _resetConnectionInternals() {
    _connectionDevice = null;
    _connectionSetupStarted = false;
    _clearPublicConnectionState();
  }

  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) {
      return active;
    }
    final operation = _performDispose();
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _performDispose() async {
    final previousLifecycle = _lifecycle;
    _lifecycle = _ProbeLifecycle.disposed;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _connectionGeneration++;

    Object? failure;
    StackTrace? failureStackTrace;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action().timeout(_cleanupTimeout);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }

    await run(_readinessSubscription.cancel);
    await run(_stopScanForLifecycle);
    final activeCleanup = _connectionCleanupFuture;
    final activeDisconnect = _disconnectFuture;
    if (activeCleanup != null) {
      await run(() => activeCleanup);
    } else if (activeDisconnect != null) {
      await run(() => activeDisconnect);
    } else if (previousLifecycle != _ProbeLifecycle.idle &&
        previousLifecycle != _ProbeLifecycle.faulted) {
      final deviceId = _connectedDevice ?? _connectionDevice;
      final redactionIds = _captureKnownDeviceIds();
      _clearPublicConnectionState();
      await run(() => _performDisconnect(deviceId, redactionIds));
    }
    await run(_disposeTransport);
    await run(_protocolNotifications.close);
    _eventBroadcaster.close();

    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStackTrace!);
    }
  }

  String _characteristicKey(BleCharacteristic characteristic) =>
      '${characteristic.serviceUuid}/${characteristic.characteristicUuid}';

  void _record(ProbeEventKind kind, String message) {
    if (_events.length == _maxEvents) {
      _events.removeAt(0);
    }
    final event = ProbeEvent(
      timestamp: DateTime.now().toUtc(),
      kind: kind,
      message: message,
    );
    _events.add(event);
    _eventBroadcaster.add(event);
  }

  void _recordError(String prefix, Object error, {Set<String>? redactionIds}) {
    _record(
      ProbeEventKind.error,
      '$prefix: ${_safeErrorDetails(error, redactionIds: redactionIds)}',
    );
  }

  String _safeErrorDetails(Object error, {Set<String>? redactionIds}) {
    final details = switch (error) {
      BleFailure failure =>
        'code=${failure.code.name} message=${failure.message}',
      _ => error.toString(),
    };
    return _redactKnownDeviceIds(details, additionalIds: redactionIds);
  }

  String _redactKnownDeviceIds(String value, {Set<String>? additionalIds}) {
    var sanitized = value;
    final ids =
        <String>{
            ..._captureKnownDeviceIds(),
            ...?additionalIds,
          }.where((id) => id.isNotEmpty).toList()
          ..sort((left, right) => right.length.compareTo(left.length));
    for (final id in ids) {
      sanitized = sanitized.replaceAll(id, '[redacted-device]');
    }
    return sanitized;
  }

  Set<String> _captureKnownDeviceIds() => <String>{
    ..._devices.keys.map((id) => id.value),
    if (_connectionDevice case final device?) device.value,
    if (_connectedDevice case final device?) device.value,
  };

  String _formatPayload(Uint8List bytes) {
    final truncated = bytes.length > _maxNotificationLogBytes;
    final preview = truncated
        ? bytes.sublist(0, _maxNotificationLogBytes)
        : bytes;
    return '${formatHexBytes(preview)} '
        'totalBytes=${bytes.length} truncated=$truncated';
  }

  void _ensureConnected(String operation) {
    if (_lifecycle != _ProbeLifecycle.connected || _connectedDevice == null) {
      throw _invalidLifecycle(operation);
    }
  }

  StateError _invalidLifecycle(String operation) => StateError(
    'Cannot $operation while probe lifecycle is ${_lifecycle.name}.',
  );

  StateError _disposedError() =>
      StateError('ProbeController has been disposed.');

  void _quarantine() {
    if (_lifecycle == _ProbeLifecycle.disposed) {
      return;
    }
    _lifecycle = _ProbeLifecycle.faulted;
    unawaited(
      _disposeTransport().catchError((Object error) {
        _recordError('transport quarantine disposal failed', error);
      }),
    );
  }

  Future<void> _disposeTransport() =>
      _transportDisposeFuture ??= _transport.dispose();

  Duration _remaining(_MonotonicDeadline deadline) {
    final remaining = deadline.remaining;
    if (remaining == Duration.zero) {
      throw _connectionTimeoutFailure(deadline.total);
    }
    return remaining;
  }

  BleFailure _connectionTimeoutFailure(Duration timeout) => BleFailure(
    code: BleFailureCode.connectionFailed,
    message: 'BLE probe connection readiness timed out.',
    cause: TimeoutException(
      'BLE probe connection readiness timed out.',
      timeout,
    ),
  );

  static int _validatePositiveInt(int value, String name) {
    if (value <= 0) {
      throw ArgumentError.value(value, name, 'Must be positive.');
    }
    return value;
  }

  static Duration _validatePositiveDuration(Duration value, String name) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, name, 'Must be positive.');
    }
    return value;
  }
}

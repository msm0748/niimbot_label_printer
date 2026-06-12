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

final class FakeBleTransport implements BleTransport {
  FakeBleTransport({
    this.currentReadiness = BleReadiness.ready,
    this.services = const [],
    this.negotiatedMtu = 185,
  });

  final StreamController<BleReadiness> _readinessController =
      StreamController.broadcast();
  final StreamController<BleAdvertisement> _scanController =
      StreamController.broadcast();
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

  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Stream<BleReadiness> get readiness => _readinessController.stream;

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _scanController.stream;

  @override
  Future<void> stopScan() async {}

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) => _connectionController(deviceId).stream;

  @override
  Future<void> disconnect(BleDeviceId deviceId) async {
    _connectionController(deviceId).add(
      BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async =>
      List.unmodifiable(services);

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) => _notificationController(deviceId, characteristic).stream;

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
  Future<int> requestMtu(BleDeviceId deviceId, int mtu) async => negotiatedMtu;

  void emitReadiness(BleReadiness value) {
    _ensureNotDisposed();
    currentReadiness = value;
    _readinessController.add(value);
  }

  void emitAdvertisement(BleAdvertisement advertisement) {
    _ensureNotDisposed();
    _scanController.add(advertisement);
  }

  void emitConnectionUpdate(BleConnectionUpdate update) {
    _ensureNotDisposed();
    _connectionController(update.deviceId).add(update);
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
    _disposed = true;

    await Future.wait([
      _readinessController.close(),
      _scanController.close(),
      ..._connectionControllers.values.map((controller) => controller.close()),
      ..._notificationControllers.values.map(
        (controller) => controller.close(),
      ),
    ]);
  }

  StreamController<BleConnectionUpdate> _connectionController(
    BleDeviceId deviceId,
  ) {
    _ensureNotDisposed();
    return _connectionControllers.putIfAbsent(
      deviceId,
      () => StreamController.broadcast(),
    );
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
    return _notificationControllers.putIfAbsent(
      key,
      () => StreamController.broadcast(),
    );
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FakeBleTransport has been disposed.');
    }
  }
}

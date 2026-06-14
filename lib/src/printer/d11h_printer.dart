import 'dart:async';

import '../ble/ble_models.dart';
import '../ble/ble_transport.dart';
import '../ble/reactive_ble_transport.dart';
import '../label/label_models.dart';
import '../label/text_label_renderer.dart';
import '../research/probe_controller.dart';
import 'd11h_print_characteristic.dart';

final class D11hPrinter {
  D11hPrinter() : this.withTransport(ReactiveBleTransport());

  D11hPrinter.withTransport(BleTransport transport)
    : _controller = ProbeController(transport);

  final ProbeController _controller;

  Future<void> _operationTail = Future<void>.value();
  BleDeviceId? _lastDevice;
  Future<void>? _disposeFuture;
  var _disposeRequested = false;

  bool get isConnected => _controller.connectedDevice != null;

  BleReadiness get bluetoothReadiness => _controller.readiness;

  Future<List<BleAdvertisement>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _enqueue(() async {
    await _waitForBluetoothReady();
    if (_controller.connectedDevice != null) {
      await _controller.disconnect();
    }

    final timer = Timer(timeout, () {
      unawaited(_controller.stopScan());
    });
    try {
      await _controller.startScan(timeout: timeout);
    } finally {
      timer.cancel();
    }
    return _controller.devices;
  });

  Future<void> _waitForBluetoothReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_controller.readiness != BleReadiness.ready) {
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError('Bluetooth를 사용할 수 없습니다.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> connect(BleDeviceId id) => _enqueue(() async {
    _lastDevice = id;
    final connectedDevice = _controller.connectedDevice;
    if (connectedDevice == id) {
      return;
    }
    if (connectedDevice != null) {
      await _controller.disconnect();
    }
    await _controller.connect(id);
  });

  Future<void> disconnect() => _enqueue(_controller.disconnect);

  Future<void> printLabel(LabelDocument document) => _enqueue(() async {
    final deviceId = _lastDevice;
    if (deviceId == null) {
      throw StateError(
        'Cannot print a label before selecting a device with connect().',
      );
    }

    await _ensureReadyForPrint(deviceId);

    final raster = await const TextLabelRenderer().render(document);
    final characteristic = findD11hPrintCharacteristic(_controller.services);
    if (characteristic == null) {
      throw StateError(
        'Connected device does not expose D11H FFF0/FFF1 with '
        'notify and writeWithoutResponse.',
      );
    }
    await _controller.printRaster(characteristic, raster);
  });

  Future<void> _ensureReadyForPrint(BleDeviceId deviceId) async {
    final hasPrintCharacteristic = findD11hPrintCharacteristic(
      _controller.services,
    );
    if (_controller.connectedDevice == deviceId && hasPrintCharacteristic != null) {
      return;
    }
    if (_controller.connectedDevice != null) {
      await _controller.disconnect();
    }
    await _controller.connect(deviceId);
  }

  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) {
      return active;
    }
    _disposeRequested = true;
    final operation = _enqueueDispose(_controller.dispose);
    _disposeFuture = operation;
    return operation;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposeRequested) {
      return Future<T>.error(StateError('D11hPrinter has been disposed.'));
    }
    return _chain(operation);
  }

  Future<void> _enqueueDispose(Future<void> Function() operation) =>
      _chain(operation);

  Future<T> _chain<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

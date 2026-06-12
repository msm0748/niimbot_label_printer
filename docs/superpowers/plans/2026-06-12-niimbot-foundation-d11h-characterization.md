# NIIMBOT Foundation and D11H Characterization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the empty repository into a tested Flutter package and build an Android/iOS D11H probe that records the real BLE services, characteristics, notifications, MTU behavior, and request/response traces needed for the production driver.

**Architecture:** The package defines backend-neutral BLE domain types and a `BleTransport` contract. A `flutter_reactive_ble` adapter implements that contract, while a separate `niimbot_research.dart` entry point exposes a deliberately non-stable probe API to the repository's research app. The stable `niimbot.dart` entry point remains free of raw packet write APIs.

**Tech Stack:** Flutter 3.41.9, Dart 3.11.5, `flutter_reactive_ble` 5.5.0 pinned exactly, `flutter_test`, Android BLE permissions, iOS CoreBluetooth usage descriptions.

---

## Scope Boundary

This is the first of five implementation plans required by the approved design:

1. **This plan:** package foundation, BLE abstraction, cross-platform adapter, and D11H characterization probe.
2. D11H packet codec, response parser, device readiness, and minimal verified bitmap print.
3. Reliable print queue, retries, cancellation, diagnostics, and connection recovery.
4. Label document, monochrome renderer, text, image, barcode, and QR support.
5. Complete public example app, physical-device reliability matrix, and pub.dev release preparation.

The protocol-dependent plans must not begin until this plan records the actual D11H service UUIDs, characteristic properties, and at least one official-app print trace. This avoids baking guesses into the production driver.

## File Map

### Package

- `pubspec.yaml`: package metadata and pinned BLE dependency.
- `lib/niimbot.dart`: stable package entry point; initially exports safe domain types only.
- `lib/niimbot_research.dart`: explicitly experimental probe entry point.
- `lib/src/ble/ble_models.dart`: backend-neutral value objects and enums.
- `lib/src/ble/ble_transport.dart`: testable BLE contract.
- `lib/src/ble/reactive_ble_transport.dart`: `flutter_reactive_ble` adapter.
- `lib/src/ble/ble_failure.dart`: normalized transport failures.
- `lib/src/research/probe_controller.dart`: scan, connect, inspect, subscribe, write, and trace orchestration.
- `lib/src/research/probe_event.dart`: structured research event model.
- `lib/src/research/hex_codec.dart`: strict hex input parser and formatter.

### Tests

- `test/ble/ble_models_test.dart`: value semantics and defensive byte copying.
- `test/ble/reactive_ble_mapper_test.dart`: backend-to-domain mapping.
- `test/research/hex_codec_test.dart`: strict parsing and formatting.
- `test/research/probe_controller_test.dart`: state transitions, cleanup, and trace behavior.
- `test/support/fake_ble_transport.dart`: deterministic fake transport.

### Probe Application

- `tool/d11h_probe/pubspec.yaml`: local app depending on the root package.
- `tool/d11h_probe/lib/main.dart`: app entry point.
- `tool/d11h_probe/lib/probe_page.dart`: scan/connect/service/write/log UI.
- `tool/d11h_probe/android/app/src/main/AndroidManifest.xml`: BLE declarations.
- `tool/d11h_probe/ios/Runner/Info.plist`: Bluetooth usage description.

### Research Records

- `docs/protocol/d11h/characterization.md`: verified observations and unresolved questions.
- `docs/protocol/d11h/captures/README.md`: capture naming and sanitization rules.
- `docs/protocol/d11h/captures/.gitkeep`: preserves the capture directory.

## Source Decisions

- Pin `flutter_reactive_ble: 5.5.0` instead of using a caret range. Its current package documentation covers Android/iOS discovery, status, connection, characteristic access, notifications, and MTU negotiation.
- Keep permissions in the consuming application. The root package reports BLE readiness; the probe app declares and requests the platform permissions.
- Do not expose raw write operations from `lib/niimbot.dart`. They are available only through `lib/niimbot_research.dart`.
- Store textual, sanitized capture summaries in Git. Do not commit phone MAC addresses, iOS peripheral identifiers, label content, or unsanitized binary captures.

### Task 1: Scaffold the Package and Probe App

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/niimbot.dart`
- Create: `test/niimbot_test.dart`
- Create: `tool/d11h_probe/pubspec.yaml`
- Create: `tool/d11h_probe/lib/main.dart`
- Modify: `.gitignore`
- Delete if present from the old app template: `android/`, `ios/`, `lib/main.dart`, `test/widget_test.dart`, `pubspec.lock`

- [ ] **Step 1: Generate a clean package scaffold**

Run from the repository root:

```bash
flutter create --template=package --project-name niimbot_lib .
flutter create --platforms=android,ios --project-name d11h_probe tool/d11h_probe
```

Expected: the root contains a Flutter package and `tool/d11h_probe` contains a runnable Android/iOS app.

- [ ] **Step 2: Replace the root package metadata**

Set `pubspec.yaml` to:

```yaml
name: niimbot_lib
description: A reliable Flutter SDK for NIIMBOT D11H BLE label printing.
version: 0.1.0-dev.1
publish_to: none

environment:
  sdk: ^3.11.5
  flutter: ">=3.41.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_reactive_ble: 5.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

`publish_to: none` remains until the final release plan adds the real repository
metadata and completes the pub.dev checklist.

- [ ] **Step 3: Configure the probe app dependency**

Replace `tool/d11h_probe/pubspec.yaml` with:

```yaml
name: d11h_probe
description: Internal NIIMBOT D11H BLE characterization tool.
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.11.5

dependencies:
  flutter:
    sdk: flutter
  niimbot_lib:
    path: ../..
  permission_handler: 12.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 4: Add the initial stable entry point and smoke test**

Set `lib/niimbot.dart` to:

```dart
library;

export 'src/ble/ble_failure.dart';
export 'src/ble/ble_models.dart';
```

Set `test/niimbot_test.dart` to:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';

void main() {
  test('package exposes BLE readiness states', () {
    expect(BleReadiness.values, contains(BleReadiness.ready));
  });
}
```

Expected initially: analyzer errors because the BLE domain files do not exist yet. This smoke test becomes green in Task 2.

- [ ] **Step 5: Extend ignores for research captures**

Append to `.gitignore`:

```gitignore
# D11H research output
docs/protocol/d11h/captures/*
!docs/protocol/d11h/captures/README.md
!docs/protocol/d11h/captures/.gitkeep
tool/d11h_probe/*.log
```

- [ ] **Step 6: Resolve dependencies**

Run:

```bash
flutter pub get
```

Then run from `tool/d11h_probe`:

```bash
flutter pub get
```

Expected: both commands exit with code 0 and lock `flutter_reactive_ble` to
`5.5.0` and `permission_handler` to `12.0.3`.

- [ ] **Step 7: Commit the scaffold**

```bash
git add .gitignore pubspec.yaml pubspec.lock lib test tool/d11h_probe
git commit -m "build: scaffold NIIMBOT package and D11H probe"
```

### Task 2: Define BLE Domain Types and Failures

**Files:**
- Create: `lib/src/ble/ble_models.dart`
- Create: `lib/src/ble/ble_failure.dart`
- Create: `test/ble/ble_models_test.dart`

- [ ] **Step 1: Write failing value-object tests**

Create `test/ble/ble_models_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';

void main() {
  test('BleDeviceId compares by value', () {
    expect(const BleDeviceId('device-1'), const BleDeviceId('device-1'));
  });

  test('BleAdvertisement defensively copies manufacturer data', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);
    final advertisement = BleAdvertisement(
      deviceId: const BleDeviceId('device-1'),
      name: 'D11_H',
      rssi: -45,
      manufacturerData: source,
      serviceUuids: const <String>[],
    );

    source[0] = 99;

    expect(advertisement.manufacturerData, <int>[1, 2, 3]);
    expect(
      () => advertisement.manufacturerData[0] = 8,
      throwsUnsupportedError,
    );
  });

  test('BleCharacteristic exposes immutable properties', () {
    const characteristic = BleCharacteristic(
      serviceUuid: 'fff0',
      characteristicUuid: 'fff1',
      properties: <BleCharacteristicProperty>{
        BleCharacteristicProperty.write,
        BleCharacteristicProperty.notify,
      },
    );

    expect(characteristic.canWrite, isTrue);
    expect(characteristic.canNotify, isTrue);
    expect(characteristic.canRead, isFalse);
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/ble/ble_models_test.dart
```

Expected: FAIL because `BleDeviceId`, `BleAdvertisement`, and `BleCharacteristic` are undefined.

- [ ] **Step 3: Implement the domain models**

Create `lib/src/ble/ble_models.dart`:

```dart
import 'dart:collection';
import 'dart:typed_data';

enum BleReadiness {
  unknown,
  unsupported,
  unauthorized,
  poweredOff,
  locationServicesDisabled,
  ready,
}

enum BleConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

enum BleCharacteristicProperty {
  read,
  write,
  writeWithoutResponse,
  notify,
  indicate,
}

final class BleDeviceId {
  const BleDeviceId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDeviceId && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class BleAdvertisement {
  BleAdvertisement({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required Uint8List manufacturerData,
    required List<String> serviceUuids,
  })  : manufacturerData =
            Uint8List.fromList(manufacturerData).asUnmodifiableView(),
        serviceUuids = List<String>.unmodifiable(serviceUuids);

  final BleDeviceId deviceId;
  final String name;
  final int rssi;
  final Uint8List manufacturerData;
  final List<String> serviceUuids;
}

final class BleConnectionUpdate {
  const BleConnectionUpdate({
    required this.deviceId,
    required this.status,
    this.failure,
  });

  final BleDeviceId deviceId;
  final BleConnectionStatus status;
  final BleFailure? failure;
}

final class BleCharacteristic {
  const BleCharacteristic({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.properties,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final Set<BleCharacteristicProperty> properties;

  bool get canRead => properties.contains(BleCharacteristicProperty.read);
  bool get canWrite =>
      properties.contains(BleCharacteristicProperty.write) ||
      properties.contains(BleCharacteristicProperty.writeWithoutResponse);
  bool get canNotify =>
      properties.contains(BleCharacteristicProperty.notify) ||
      properties.contains(BleCharacteristicProperty.indicate);
}

final class BleService {
  const BleService({
    required this.serviceUuid,
    required this.characteristics,
  });

  final String serviceUuid;
  final List<BleCharacteristic> characteristics;
}

enum BleWriteMode { withResponse, withoutResponse }
```

Add this import at the top of that file:

```dart
import 'ble_failure.dart';
```

- [ ] **Step 4: Implement normalized failures**

Create `lib/src/ble/ble_failure.dart`:

```dart
enum BleFailureCode {
  unsupported,
  unauthorized,
  poweredOff,
  scanFailed,
  connectionFailed,
  discoveryFailed,
  subscriptionFailed,
  writeFailed,
  mtuFailed,
  invalidState,
  unknown,
}

final class BleFailure implements Exception {
  const BleFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final BleFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'BleFailure($code, $message)';
}
```

- [ ] **Step 5: Run tests and analysis**

Run:

```bash
dart format lib/src/ble test/ble
flutter test test/ble/ble_models_test.dart
flutter analyze
```

Expected: all tests pass and analysis reports no issues.

- [ ] **Step 6: Commit domain types**

```bash
git add lib/niimbot.dart lib/src/ble test/ble test/niimbot_test.dart
git commit -m "feat: define backend-neutral BLE domain types"
```

### Task 3: Add the BLE Transport Contract and Deterministic Fake

**Files:**
- Create: `lib/src/ble/ble_transport.dart`
- Create: `test/support/fake_ble_transport.dart`
- Create: `test/ble/ble_transport_contract_test.dart`

- [ ] **Step 1: Write the transport contract test**

Create `test/ble/ble_transport_contract_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/src/ble/ble_models.dart';

import '../support/fake_ble_transport.dart';

void main() {
  test('fake transport records writes and exposes notifications', () async {
    final transport = FakeBleTransport();
    const deviceId = BleDeviceId('device-1');
    const characteristic = BleCharacteristic(
      serviceUuid: 'fff0',
      characteristicUuid: 'fff1',
      properties: <BleCharacteristicProperty>{
        BleCharacteristicProperty.write,
        BleCharacteristicProperty.notify,
      },
    );

    final notifications = <List<int>>[];
    final subscription = transport
        .subscribe(deviceId, characteristic)
        .listen((bytes) => notifications.add(bytes));

    await transport.write(
      deviceId,
      characteristic,
      Uint8List.fromList(<int>[0x01, 0x02]),
      mode: BleWriteMode.withResponse,
    );
    transport.emitNotification(<int>[0x03, 0x04]);
    await Future<void>.delayed(Duration.zero);

    expect(transport.writes.single.bytes, <int>[0x01, 0x02]);
    expect(notifications.single, <int>[0x03, 0x04]);

    await subscription.cancel();
    await transport.dispose();
  });
}
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
flutter test test/ble/ble_transport_contract_test.dart
```

Expected: FAIL because `FakeBleTransport` and `BleTransport` do not exist.

- [ ] **Step 3: Define the transport contract**

Create `lib/src/ble/ble_transport.dart`:

```dart
import 'dart:typed_data';

import 'ble_models.dart';

abstract interface class BleTransport {
  BleReadiness get currentReadiness;

  Stream<BleReadiness> get readiness;

  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> stopScan();

  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> disconnect(BleDeviceId deviceId);

  Future<List<BleService>> discoverServices(BleDeviceId deviceId);

  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  );

  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  });

  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu);

  Future<void> dispose();
}
```

- [ ] **Step 4: Implement the fake transport**

Create `test/support/fake_ble_transport.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:niimbot_lib/src/ble/ble_models.dart';
import 'package:niimbot_lib/src/ble/ble_transport.dart';

final class RecordedWrite {
  RecordedWrite({
    required this.deviceId,
    required this.characteristic,
    required Uint8List bytes,
    required this.mode,
  }) : bytes = Uint8List.fromList(bytes);

  final BleDeviceId deviceId;
  final BleCharacteristic characteristic;
  final Uint8List bytes;
  final BleWriteMode mode;
}

final class FakeBleTransport implements BleTransport {
  final _readinessController = StreamController<BleReadiness>.broadcast();
  final _scanController = StreamController<BleAdvertisement>.broadcast();
  final _connectionController =
      StreamController<BleConnectionUpdate>.broadcast();
  final _notificationController = StreamController<Uint8List>.broadcast();

  @override
  BleReadiness currentReadiness = BleReadiness.ready;

  List<BleService> services = const <BleService>[];
  int negotiatedMtu = 185;
  final List<RecordedWrite> writes = <RecordedWrite>[];

  @override
  Stream<BleReadiness> get readiness => _readinessController.stream;

  void emitReadiness(BleReadiness value) {
    currentReadiness = value;
    _readinessController.add(value);
  }

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _scanController.stream;

  void emitAdvertisement(BleAdvertisement value) => _scanController.add(value);

  @override
  Future<void> stopScan() async {}

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _connectionController.stream;

  void emitConnection(BleConnectionUpdate value) =>
      _connectionController.add(value);

  @override
  Future<void> disconnect(BleDeviceId deviceId) async {
    emitConnection(
      BleConnectionUpdate(
        deviceId: deviceId,
        status: BleConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async =>
      services;

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) =>
      _notificationController.stream;

  void emitNotification(List<int> bytes) =>
      _notificationController.add(Uint8List.fromList(bytes));

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  }) async {
    writes.add(
      RecordedWrite(
        deviceId: deviceId,
        characteristic: characteristic,
        bytes: bytes,
        mode: mode,
      ),
    );
  }

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu) async =>
      negotiatedMtu;

  @override
  Future<void> dispose() async {
    await _readinessController.close();
    await _scanController.close();
    await _connectionController.close();
    await _notificationController.close();
  }
}
```

- [ ] **Step 5: Run the contract test**

Run:

```bash
dart format lib/src/ble/ble_transport.dart test/support test/ble
flutter test test/ble/ble_transport_contract_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the transport contract**

```bash
git add lib/src/ble/ble_transport.dart test/support test/ble
git commit -m "feat: add testable BLE transport contract"
```

### Task 4: Implement and Test the Reactive BLE Adapter

**Files:**
- Create: `lib/src/ble/reactive_ble_mapper.dart`
- Create: `lib/src/ble/reactive_ble_transport.dart`
- Create: `test/ble/reactive_ble_mapper_test.dart`
- Modify: `lib/niimbot_research.dart`

- [ ] **Step 1: Write mapping tests before touching the plugin**

Create `test/ble/reactive_ble_mapper_test.dart`:

```dart
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/src/ble/ble_models.dart';
import 'package:niimbot_lib/src/ble/reactive_ble_mapper.dart';

void main() {
  test('maps BLE readiness without leaking backend enum', () {
    expect(
      mapBleStatus(BleStatus.ready),
      BleReadiness.ready,
    );
    expect(
      mapBleStatus(BleStatus.unauthorized),
      BleReadiness.unauthorized,
    );
    expect(
      mapBleStatus(BleStatus.poweredOff),
      BleReadiness.poweredOff,
    );
  });

  test('normalizes UUIDs to lowercase canonical strings', () {
    expect(normalizeUuid(Uuid.parse('FFF0')), contains('fff0'));
  });
}
```

- [ ] **Step 2: Run the mapping test and verify failure**

Run:

```bash
flutter test test/ble/reactive_ble_mapper_test.dart
```

Expected: FAIL because the mapper does not exist.

- [ ] **Step 3: Implement pure mapping functions**

Create `lib/src/ble/reactive_ble_mapper.dart`:

```dart
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_models.dart';

BleReadiness mapBleStatus(BleStatus status) => switch (status) {
      BleStatus.ready => BleReadiness.ready,
      BleStatus.unsupported => BleReadiness.unsupported,
      BleStatus.unauthorized => BleReadiness.unauthorized,
      BleStatus.poweredOff => BleReadiness.poweredOff,
      BleStatus.locationServicesDisabled =>
        BleReadiness.locationServicesDisabled,
      BleStatus.unknown => BleReadiness.unknown,
    };

BleConnectionStatus mapConnectionState(DeviceConnectionState state) =>
    switch (state) {
      DeviceConnectionState.connecting => BleConnectionStatus.connecting,
      DeviceConnectionState.connected => BleConnectionStatus.connected,
      DeviceConnectionState.disconnecting =>
        BleConnectionStatus.disconnecting,
      DeviceConnectionState.disconnected => BleConnectionStatus.disconnected,
    };

String normalizeUuid(Uuid uuid) => uuid.toString().toLowerCase();
```

- [ ] **Step 4: Implement the adapter**

Create `lib/src/ble/reactive_ble_transport.dart` with a single
`ReactiveBleTransport` class that:

```dart
final class ReactiveBleTransport implements BleTransport {
  ReactiveBleTransport({FlutterReactiveBle? backend})
      : _backend = backend ?? FlutterReactiveBle();

  final FlutterReactiveBle _backend;

  @override
  BleReadiness get currentReadiness => mapBleStatus(_backend.status);

  @override
  Stream<BleReadiness> get readiness =>
      _backend.statusStream.map(mapBleStatus).distinct();

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final stream = _backend.scanForDevices(
      withServices: const <Uuid>[],
      scanMode: ScanMode.lowLatency,
    );
    return stream
        .map(
          (device) => BleAdvertisement(
            deviceId: BleDeviceId(device.id),
            name: device.name,
            rssi: device.rssi,
            manufacturerData: device.manufacturerData,
            serviceUuids: device.serviceData.keys
                .map(normalizeUuid)
                .toList(growable: false),
          ),
        )
        .timeout(timeout);
  }

  @override
  Future<void> stopScan() async {
    // flutter_reactive_ble stops scanning when the scan subscription is
    // cancelled. ProbeController owns and cancels that subscription.
  }

  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _backend
        .connectToAdvertisingDevice(
          id: deviceId.value,
          withServices: const <Uuid>[],
          prescanDuration: const Duration(seconds: 3),
          connectionTimeout: timeout,
        )
        .map(
          (update) => BleConnectionUpdate(
            deviceId: deviceId,
            status: mapConnectionState(update.connectionState),
          ),
        );
  }

  @override
  Future<void> disconnect(BleDeviceId deviceId) async {
    // Cancelling the stream returned by connect() disconnects this backend.
    // ProbeController owns that subscription and cancels it during teardown.
  }

  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async {
    final services = await _backend.discoverServices(deviceId.value);
    return services
        .map(
          (service) => BleService(
            serviceUuid: normalizeUuid(service.id),
            characteristics: service.characteristics
                .map(
                  (characteristic) => BleCharacteristic(
                    serviceUuid: normalizeUuid(service.id),
                    characteristicUuid: normalizeUuid(characteristic.id),
                    properties: <BleCharacteristicProperty>{
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
        )
        .toList(growable: false);
  }

  QualifiedCharacteristic _qualified(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) =>
      QualifiedCharacteristic(
        deviceId: deviceId.value,
        serviceId: Uuid.parse(characteristic.serviceUuid),
        characteristicId: Uuid.parse(characteristic.characteristicUuid),
      );

  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) =>
      _backend
          .subscribeToCharacteristic(_qualified(deviceId, characteristic))
          .map(Uint8List.fromList);

  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  }) async {
    final qualified = _qualified(deviceId, characteristic);
    switch (mode) {
      case BleWriteMode.withResponse:
        await _backend.writeCharacteristicWithResponse(
          qualified,
          value: bytes,
        );
      case BleWriteMode.withoutResponse:
        await _backend.writeCharacteristicWithoutResponse(
          qualified,
          value: bytes,
        );
    }
  }

  @override
  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu) =>
      _backend.requestMtu(deviceId: deviceId.value, mtu: requestedMtu);

  @override
  Future<void> dispose() async {}
}
```

Add these imports:

```dart
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_models.dart';
import 'ble_transport.dart';
import 'reactive_ble_mapper.dart';
```

- [ ] **Step 5: Add the experimental research entry point**

Create `lib/niimbot_research.dart`:

```dart
library;

export 'src/ble/ble_failure.dart';
export 'src/ble/ble_models.dart';
export 'src/ble/ble_transport.dart';
export 'src/ble/reactive_ble_transport.dart';
export 'src/research/hex_codec.dart';
export 'src/research/probe_controller.dart';
export 'src/research/probe_event.dart';
```

- [ ] **Step 6: Run focused tests and analysis**

Run:

```bash
dart format lib/src/ble lib/niimbot_research.dart test/ble
flutter test test/ble
flutter analyze
```

Expected: all BLE tests pass and analysis reports no issues.

- [ ] **Step 7: Commit the adapter**

```bash
git add lib/niimbot_research.dart lib/src/ble test/ble pubspec.lock
git commit -m "feat: adapt flutter_reactive_ble behind transport contract"
```

### Task 5: Implement Strict Hex Encoding

**Files:**
- Create: `lib/src/research/hex_codec.dart`
- Create: `test/research/hex_codec_test.dart`

- [ ] **Step 1: Write failing codec tests**

Create `test/research/hex_codec_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot_research.dart';

void main() {
  test('parses whitespace-separated hexadecimal bytes', () {
    expect(parseHexBytes('55 01 aa'), <int>[0x55, 0x01, 0xaa]);
  });

  test('parses compact hexadecimal bytes', () {
    expect(parseHexBytes('5501AA'), <int>[0x55, 0x01, 0xaa]);
  });

  test('rejects odd-length input', () {
    expect(() => parseHexBytes('550'), throwsFormatException);
  });

  test('rejects non-hexadecimal input', () {
    expect(() => parseHexBytes('55 ZZ'), throwsFormatException);
  });

  test('formats bytes as lowercase spaced hex', () {
    expect(formatHexBytes(<int>[0x05, 0xab]), '05 ab');
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/research/hex_codec_test.dart
```

Expected: FAIL because the codec functions do not exist.

- [ ] **Step 3: Implement the codec**

Create `lib/src/research/hex_codec.dart`:

```dart
import 'dart:typed_data';

Uint8List parseHexBytes(String input) {
  final normalized = input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (normalized.isEmpty) {
    return Uint8List(0);
  }
  if (normalized.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
    throw const FormatException('Expected an even number of hexadecimal digits.');
  }

  return Uint8List.fromList(
    <int>[
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ],
  );
}

String formatHexBytes(Iterable<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join(' ');
```

- [ ] **Step 4: Run tests and commit**

Run:

```bash
dart format lib/src/research/hex_codec.dart test/research/hex_codec_test.dart
flutter test test/research/hex_codec_test.dart
```

Expected: PASS.

```bash
git add lib/src/research/hex_codec.dart test/research/hex_codec_test.dart
git commit -m "feat: add strict hexadecimal probe codec"
```

### Task 6: Build the Probe Controller with Cleanup Guarantees

**Files:**
- Create: `lib/src/research/probe_event.dart`
- Create: `lib/src/research/probe_controller.dart`
- Create: `test/research/probe_controller_test.dart`

- [ ] **Step 1: Write the controller state test**

Create `test/research/probe_controller_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot_research.dart';

import '../support/fake_ble_transport.dart';

void main() {
  test('scan de-duplicates devices and keeps strongest/latest result', () async {
    final transport = FakeBleTransport();
    final controller = ProbeController(transport);
    const id = BleDeviceId('device-1');

    final scanFuture = controller.startScan();
    transport.emitAdvertisement(
      BleAdvertisement(
        deviceId: id,
        name: 'D11_H',
        rssi: -70,
        manufacturerData: Uint8List(0),
        serviceUuids: const <String>[],
      ),
    );
    transport.emitAdvertisement(
      BleAdvertisement(
        deviceId: id,
        name: 'D11_H',
        rssi: -40,
        manufacturerData: Uint8List(0),
        serviceUuids: const <String>[],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.stopScan();
    await scanFuture;

    expect(controller.devices, hasLength(1));
    expect(controller.devices.single.rssi, -40);

    await controller.dispose();
  });

  test('connect discovers services and records negotiated MTU', () async {
    final transport = FakeBleTransport()
      ..services = const <BleService>[
        BleService(serviceUuid: 'fff0', characteristics: <BleCharacteristic>[]),
      ]
      ..negotiatedMtu = 185;
    final controller = ProbeController(transport);
    const id = BleDeviceId('device-1');

    final connectFuture = controller.connect(id);
    transport.emitConnection(
      const BleConnectionUpdate(
        deviceId: id,
        status: BleConnectionStatus.connected,
      ),
    );
    await connectFuture;

    expect(controller.connectedDevice, id);
    expect(controller.services.single.serviceUuid, 'fff0');
    expect(controller.mtu, 185);

    await controller.dispose();
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/research/probe_controller_test.dart
```

Expected: FAIL because `ProbeController` is undefined.

- [ ] **Step 3: Define structured probe events**

Create `lib/src/research/probe_event.dart`:

```dart
enum ProbeEventKind {
  readiness,
  scan,
  connection,
  serviceDiscovery,
  mtu,
  subscription,
  write,
  notification,
  error,
}

final class ProbeEvent {
  const ProbeEvent({
    required this.timestamp,
    required this.kind,
    required this.message,
  });

  final DateTime timestamp;
  final ProbeEventKind kind;
  final String message;

  String toLogLine() =>
      '${timestamp.toUtc().toIso8601String()} ${kind.name} $message';
}
```

- [ ] **Step 4: Implement the controller**

Create `lib/src/research/probe_controller.dart` with:

```dart
import 'dart:async';
import 'dart:typed_data';

import '../ble/ble_models.dart';
import '../ble/ble_transport.dart';
import 'hex_codec.dart';
import 'probe_event.dart';

final class ProbeController {
  ProbeController(this._transport);

  final BleTransport _transport;
  final Map<BleDeviceId, BleAdvertisement> _devices =
      <BleDeviceId, BleAdvertisement>{};
  final List<ProbeEvent> _events = <ProbeEvent>[];
  final List<StreamSubscription<Uint8List>> _notificationSubscriptions =
      <StreamSubscription<Uint8List>>[];

  StreamSubscription<BleAdvertisement>? _scanSubscription;
  StreamSubscription<BleConnectionUpdate>? _connectionSubscription;
  Completer<void>? _scanCompleter;
  Completer<void>? _connectCompleter;

  BleDeviceId? connectedDevice;
  List<BleService> services = const <BleService>[];
  int? mtu;

  List<BleAdvertisement> get devices =>
      List<BleAdvertisement>.unmodifiable(_devices.values);
  List<ProbeEvent> get events => List<ProbeEvent>.unmodifiable(_events);
  BleReadiness get readiness => _transport.currentReadiness;

  void _record(ProbeEventKind kind, String message) {
    _events.add(
      ProbeEvent(timestamp: DateTime.now(), kind: kind, message: message),
    );
  }

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_scanSubscription != null) {
      throw StateError('A scan is already active.');
    }

    _scanCompleter = Completer<void>();
    _scanSubscription = _transport.scan(timeout: timeout).listen(
      (advertisement) {
        _devices[advertisement.deviceId] = advertisement;
        _record(
          ProbeEventKind.scan,
          'device name=${advertisement.name} rssi=${advertisement.rssi}',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _record(ProbeEventKind.error, 'scan failed: $error');
        _scanCompleter?.completeError(error, stackTrace);
      },
      onDone: () {
        if (!(_scanCompleter?.isCompleted ?? true)) {
          _scanCompleter?.complete();
        }
      },
    );
    return _scanCompleter!.future;
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _transport.stopScan();
    if (!(_scanCompleter?.isCompleted ?? true)) {
      _scanCompleter?.complete();
    }
  }

  Future<void> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    _connectCompleter = Completer<void>();
    _connectionSubscription =
        _transport.connect(deviceId, timeout: timeout).listen(
      (update) async {
        _record(ProbeEventKind.connection, update.status.name);
        if (update.status == BleConnectionStatus.connected) {
          connectedDevice = deviceId;
          services = await _transport.discoverServices(deviceId);
          _record(
            ProbeEventKind.serviceDiscovery,
            'services=${services.length}',
          );
          mtu = await _transport.requestMtu(deviceId, 247);
          _record(ProbeEventKind.mtu, 'negotiated=$mtu');
          if (!(_connectCompleter?.isCompleted ?? true)) {
            _connectCompleter?.complete();
          }
        }
        if (update.status == BleConnectionStatus.disconnected) {
          connectedDevice = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _record(ProbeEventKind.error, 'connection failed: $error');
        _connectCompleter?.completeError(error, stackTrace);
      },
    );
    return _connectCompleter!.future;
  }

  Future<void> subscribe(BleCharacteristic characteristic) async {
    final deviceId = connectedDevice;
    if (deviceId == null) {
      throw StateError('No connected device.');
    }
    final subscription = _transport.subscribe(deviceId, characteristic).listen(
      (bytes) => _record(
        ProbeEventKind.notification,
        '${characteristic.characteristicUuid} ${formatHexBytes(bytes)}',
      ),
      onError: (Object error) =>
          _record(ProbeEventKind.error, 'subscription failed: $error'),
    );
    _notificationSubscriptions.add(subscription);
    _record(
      ProbeEventKind.subscription,
      characteristic.characteristicUuid,
    );
  }

  Future<void> writeHex(
    BleCharacteristic characteristic,
    String hex, {
    required BleWriteMode mode,
  }) async {
    final deviceId = connectedDevice;
    if (deviceId == null) {
      throw StateError('No connected device.');
    }
    final bytes = parseHexBytes(hex);
    await _transport.write(
      deviceId,
      characteristic,
      bytes,
      mode: mode,
    );
    _record(
      ProbeEventKind.write,
      '${characteristic.characteristicUuid} ${formatHexBytes(bytes)}',
    );
  }

  String exportSanitizedLog() =>
      _events.map((event) => event.toLogLine()).join('\n');

  Future<void> disconnect() async {
    for (final subscription in _notificationSubscriptions) {
      await subscription.cancel();
    }
    _notificationSubscriptions.clear();
    final deviceId = connectedDevice;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    if (deviceId != null) {
      await _transport.disconnect(deviceId);
    }
    connectedDevice = null;
    services = const <BleService>[];
    mtu = null;
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    await _transport.dispose();
  }
}
```

- [ ] **Step 5: Run controller tests and the full suite**

Run:

```bash
dart format lib/src/research test/research
flutter test test/research
flutter test
flutter analyze
```

Expected: all tests pass and analysis reports no issues.

- [ ] **Step 6: Commit the controller**

```bash
git add lib/src/research test/research lib/niimbot_research.dart
git commit -m "feat: add D11H BLE probe controller"
```

### Task 7: Add Platform Permissions and the Probe UI

**Files:**
- Modify: `tool/d11h_probe/android/app/src/main/AndroidManifest.xml`
- Modify: `tool/d11h_probe/ios/Runner/Info.plist`
- Modify: `tool/d11h_probe/lib/main.dart`
- Create: `tool/d11h_probe/lib/probe_page.dart`
- Create: `tool/d11h_probe/test/probe_page_test.dart`

- [ ] **Step 1: Add Android BLE declarations**

Add these elements directly under `<manifest>`:

```xml
<uses-feature
    android:name="android.hardware.bluetooth_le"
    android:required="true" />
<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission
    android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
<uses-permission
    android:name="android.permission.ACCESS_COARSE_LOCATION"
    android:maxSdkVersion="30" />
```

- [ ] **Step 2: Add the iOS Bluetooth usage description**

Add inside the root `<dict>` in `tool/d11h_probe/ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is required to inspect and test the NIIMBOT D11H printer.</string>
```

- [ ] **Step 3: Write the initial widget test**

Create `tool/d11h_probe/test/probe_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot_research.dart';

import 'package:d11h_probe/probe_page.dart';

void main() {
  testWidgets('shows scan action and empty-state guidance', (tester) async {
    final controller = ProbeController(_IdleTransport());

    await tester.pumpWidget(
      MaterialApp(home: ProbePage(controller: controller)),
    );

    expect(find.text('Scan for D11H'), findsOneWidget);
    expect(find.text('No devices discovered'), findsOneWidget);
  });
}

final class _IdleTransport implements BleTransport {
  @override
  BleReadiness get currentReadiness => BleReadiness.ready;
  @override
  Stream<BleReadiness> get readiness => const Stream<BleReadiness>.empty();
  @override
  Stream<BleAdvertisement> scan({Duration timeout = const Duration(seconds: 10)}) =>
      const Stream<BleAdvertisement>.empty();
  @override
  Future<void> stopScan() async {}
  @override
  Stream<BleConnectionUpdate> connect(
    BleDeviceId deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      const Stream<BleConnectionUpdate>.empty();
  @override
  Future<void> disconnect(BleDeviceId deviceId) async {}
  @override
  Future<List<BleService>> discoverServices(BleDeviceId deviceId) async =>
      const <BleService>[];
  @override
  Stream<Uint8List> subscribe(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
  ) =>
      const Stream<Uint8List>.empty();
  @override
  Future<void> write(
    BleDeviceId deviceId,
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required BleWriteMode mode,
  }) async {}
  @override
  Future<int> requestMtu(BleDeviceId deviceId, int requestedMtu) async => 23;
  @override
  Future<void> dispose() async {}
}
```

Add `import 'dart:typed_data';` as the first import.

- [ ] **Step 4: Run the widget test and verify failure**

Run from `tool/d11h_probe`:

```bash
flutter test test/probe_page_test.dart
```

Expected: FAIL because `ProbePage` does not exist.

- [ ] **Step 5: Implement the app entry point**

Set `tool/d11h_probe/lib/main.dart` to:

```dart
import 'package:flutter/material.dart';
import 'package:niimbot_lib/niimbot_research.dart';

import 'probe_page.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'D11H Probe',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: ProbePage(
        controller: ProbeController(ReactiveBleTransport()),
      ),
    ),
  );
}
```

- [ ] **Step 6: Implement the probe screen**

Create `tool/d11h_probe/lib/probe_page.dart` as a focused stateful screen with:

```dart
class ProbePage extends StatefulWidget {
  const ProbePage({super.key, required this.controller});

  final ProbeController controller;

  @override
  State<ProbePage> createState() => _ProbePageState();
}
```

The state must:

- request `Permission.bluetoothScan` and `Permission.bluetoothConnect` on
  Android and `Permission.bluetooth` on iOS before scanning;
- call `controller.startScan()` and stop after ten seconds;
- render discovered devices sorted by RSSI, showing name and sanitized ID suffix;
- connect only when the user taps a device;
- show negotiated MTU and every discovered service/characteristic property;
- provide `Subscribe` only for notify/indicate characteristics;
- provide a hex text field and explicit with-response/without-response selector
  only for writable characteristics;
- require a confirmation dialog before every raw write;
- render `controller.events` as selectable text;
- copy `controller.exportSanitizedLog()` to the clipboard;
- call `controller.dispose()` from `dispose`.

Use this sanitization helper rather than displaying a full identifier:

```dart
String displayDeviceId(BleDeviceId id) {
  final value = id.value;
  return value.length <= 6 ? value : '...${value.substring(value.length - 6)}';
}
```

Do not add automatic writes, command presets, background behavior, or guessed
D11H UUIDs in this task.

- [ ] **Step 7: Run app tests and platform configuration builds**

Run from the repository root:

```bash
dart format tool/d11h_probe/lib tool/d11h_probe/test
flutter analyze
```

Then run from `tool/d11h_probe`:

```bash
flutter test
flutter build apk --config-only
flutter build ios --no-codesign --config-only
```

Expected: widget tests pass, Android and iOS configuration builds exit with code
0, and analysis reports no issues.

- [ ] **Step 8: Commit the probe application**

```bash
git add tool/d11h_probe
git commit -m "feat: add Android and iOS D11H probe app"
```

### Task 8: Record the D11H Characterization Procedure

**Files:**
- Create: `docs/protocol/d11h/characterization.md`
- Create: `docs/protocol/d11h/captures/README.md`
- Create: `docs/protocol/d11h/captures/.gitkeep`

- [ ] **Step 1: Create the characterization record**

Create `docs/protocol/d11h/characterization.md`:

```markdown
# D11H BLE Characterization

## Test Inventory

Record one row for every run:

| Date | Phone | OS | D11H identifier suffix | Firmware | Label media | Result |
|---|---|---|---|---|---|---|

## Advertising

Record the observed device-name patterns, advertised service UUIDs,
manufacturer-data length, and whether identifiers remain stable across restarts.
Do not record full persistent device identifiers.

## GATT Layout

| Service UUID | Characteristic UUID | Read | Write | Write without response | Notify | Indicate |
|---|---|---:|---:|---:|---:|---:|

Every row must be observed on both Android and iOS before it is marked verified.

## MTU

| Platform | Requested | Negotiated | Stable payload size |
|---|---:|---:|---:|

## Official-App Trace

For each operation, record ordered writes and notifications with timestamps:

1. Connect and idle initialization.
2. Printer/status query.
3. One minimal all-white label.
4. One minimal label containing a single black horizontal line.
5. Disconnect.

## Hypotheses

A hypothesis is not a verified command. Record the evidence that would confirm
or reject it before using it in production code.

## Verified Facts

Move a fact here only after it is reproduced at least three times on Android and
three times on iOS with the physical D11H.
```

- [ ] **Step 2: Document capture handling**

Create `docs/protocol/d11h/captures/README.md`:

```markdown
# D11H Capture Handling

Use filenames in this form:

`YYYY-MM-DD-platform-operation-runNN.sanitized.txt`

Committed files may contain timestamps, UUIDs, packet bytes, RSSI, MTU, phone
model, OS version, and printer firmware. Remove full Android MAC addresses,
iOS peripheral identifiers, personal label content, account data, and unrelated
nearby BLE devices.

Raw packet captures remain outside Git. Commit only the minimum sanitized trace
needed to reproduce parser and codec tests.
```

Create the empty file `docs/protocol/d11h/captures/.gitkeep`.

- [ ] **Step 3: Perform Android physical-device characterization**

Run from `tool/d11h_probe` on a physical Android device:

```bash
flutter run
```

Record advertising, GATT layout, negotiated MTU, subscriptions, and connection
events in `characterization.md`. Export and sanitize the probe log.

Expected: the D11H is discovered, connects, services are listed, and the app
can subscribe to every characteristic that advertises notify or indicate.

- [ ] **Step 4: Perform iOS physical-device characterization**

Run from `tool/d11h_probe` on a physical iPhone:

```bash
flutter run
```

Record the same observations and compare them with Android.

Expected: service and characteristic UUIDs match after canonical normalization;
platform identifiers and negotiated MTU may differ.

- [ ] **Step 5: Capture official-app behavior**

Using an authorized BLE capture method and the owned D11H:

1. Capture official-app connect and idle initialization.
2. Print the minimal all-white label.
3. Print the single-black-line label.
4. Capture disconnect.
5. Create sanitized ordered write/notification summaries.
6. Repeat each operation three times on Android and three times on iOS.

Do not transmit guessed packet bytes from the probe. Raw writes are allowed only
after a byte sequence is observed in the official-app trace and the target
characteristic property confirms the selected write mode.

- [ ] **Step 6: Verify the package before committing evidence**

Run from the repository root:

```bash
flutter test
flutter analyze
```

Then run from `tool/d11h_probe`:

```bash
flutter test
flutter build apk --config-only
flutter build ios --no-codesign --config-only
```

Expected: all tests and analysis pass; both platform configuration builds exit
with code 0.

- [ ] **Step 7: Commit sanitized protocol evidence**

```bash
git add docs/protocol/d11h
git commit -m "docs: record verified D11H BLE characterization"
```

## Completion Gate

This plan is complete only when:

- Root package tests and probe-app tests pass.
- Root analysis passes.
- Android and iOS configuration builds succeed.
- The physical D11H is discovered and connected from both Android and iPhone.
- The same GATT service/characteristic layout is recorded for both platforms.
- Negotiated MTU and stable write payload observations are recorded.
- At least one sanitized official-app trace contains initialization, minimal
  print transfer, completion response, and disconnect.
- No guessed D11H command is presented as verified.

## Next Plan Inputs

The next implementation plan must use the committed characterization record to
replace these unknowns with evidence:

- exact D11H service UUID;
- write and notify characteristic UUIDs;
- packet header, length, command, checksum, and trailer fields;
- fragmentation and reassembly rules;
- initialization and printer-ready sequence;
- minimal raster line encoding;
- print-complete and printer-error responses.

Those values must be copied into immutable test fixtures before production
driver code is written.

# D11H Media Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a research-only D11H media probe that sends observed information/status commands and renders raw responses in the iOS probe app.

**Architecture:** Add a small immutable research model for raw D11H response frames, then add `ProbeController.queryMediaProbe()` on top of the existing subscribe/write/wait protocol path. The probe app calls this method from a `Detect media` action and shows raw payload hex without claiming verified label size/type.

**Tech Stack:** Dart, Flutter, `flutter_test`, existing BLE transport abstractions, existing D11H frame helpers.

---

## File Structure

- Create `lib/src/research/d11h_media_probe.dart`: raw protocol frame and media probe result models.
- Modify `lib/niimbot_research.dart`: export the new research-only model.
- Modify `lib/src/research/probe_controller.dart`: add `queryMediaProbe()` and frame-to-model conversion.
- Modify `test/research/probe_controller_test.dart`: controller TDD coverage for command order, optional status, and validation.
- Modify `tool/d11h_probe/lib/probe_page.dart`: add button, progress state, result rendering, and error message.
- Modify `tool/d11h_probe/test/probe_page_test.dart`: widget coverage for media probe UI.
- Modify `docs/protocol/d11h/characterization.md`: record the new media-probe experiment procedure.

---

### Task 1: Research Model

**Files:**
- Create: `lib/src/research/d11h_media_probe.dart`
- Modify: `lib/niimbot_research.dart`
- Test: `test/research/d11h_media_probe_test.dart`

- [ ] **Step 1: Write the failing model test**

```dart
import 'dart:typed_data';

import 'package:flutter_niimbot/niimbot_research.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('D11hProtocolFrame exposes immutable payload and lowercase hex', () {
    final payload = Uint8List.fromList(<int>[0x01, 0xA0, 0xFF]);
    final frame = D11hProtocolFrame(command: 0x1B, payload: payload);

    payload[0] = 0x99;

    expect(frame.command, 0x1B);
    expect(frame.payload, <int>[0x01, 0xA0, 0xFF]);
    expect(frame.payloadHex, '01 a0 ff');
    expect(() => frame.payload[0] = 0x00, throwsUnsupportedError);
  });

  test('D11hMediaProbeResult stores information and optional status frames', () {
    final createdAt = DateTime.utc(2026, 6, 16, 12);
    final information = D11hProtocolFrame(
      command: 0x1B,
      payload: Uint8List.fromList(<int>[0x10]),
    );
    final status = D11hProtocolFrame(
      command: 0xB3,
      payload: Uint8List.fromList(<int>[0x00, 0x01]),
    );

    final result = D11hMediaProbeResult(
      createdAt: createdAt,
      informationResponse: information,
      statusResponse: status,
    );

    expect(result.createdAt, createdAt);
    expect(result.informationResponse, same(information));
    expect(result.statusResponse, same(status));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/research/d11h_media_probe_test.dart`

Expected: FAIL because `D11hProtocolFrame` is not defined.

- [ ] **Step 3: Write minimal model implementation**

Create `lib/src/research/d11h_media_probe.dart`:

```dart
import 'dart:typed_data';

import 'hex_codec.dart';

final class D11hProtocolFrame {
  D11hProtocolFrame({required this.command, required Uint8List payload})
    : payload = Uint8List.fromList(payload).asUnmodifiableView();

  final int command;
  final Uint8List payload;

  String get payloadHex => formatHexBytes(payload);
}

final class D11hMediaProbeResult {
  const D11hMediaProbeResult({
    required this.createdAt,
    required this.informationResponse,
    required this.statusResponse,
  });

  final DateTime createdAt;
  final D11hProtocolFrame informationResponse;
  final D11hProtocolFrame? statusResponse;
}
```

Add to `lib/niimbot_research.dart`:

```dart
export 'src/research/d11h_media_probe.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/research/d11h_media_probe_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/research/d11h_media_probe.dart lib/niimbot_research.dart test/research/d11h_media_probe_test.dart
git commit -m "feat: add D11H media probe models"
```

---

### Task 2: Controller Media Probe

**Files:**
- Modify: `lib/src/research/probe_controller.dart`
- Test: `test/research/probe_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Add tests near existing print protocol tests:

```dart
test('queries media probe information and idle status responses', () async {
  transport.writeResponder = (write) {
    final command = splitD11hFrames(write.bytes).single[2];
    final response = switch (command) {
      0x1A => '55 55 1B 03 01 02 03 18 AA AA',
      0xA3 => '55 55 B3 04 00 01 64 64 B6 AA AA',
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

  final result = await controller.queryMediaProbe(capturedPrintCharacteristic);

  expect(transport.subscribeCallCount, 1);
  expect(
    transport.writes
        .map((write) => splitD11hFrames(write.bytes).single[2])
        .toList(),
    <int>[0x1A, 0xA3],
  );
  expect(result.informationResponse.command, 0x1B);
  expect(result.informationResponse.payloadHex, '01 02 03');
  expect(result.statusResponse?.command, 0xB3);
  expect(result.statusResponse?.payloadHex, '00 01 64 64');
});

test('can query media probe without idle status', () async {
  transport.writeResponder = (write) {
    scheduleMicrotask(
      () => transport.emitNotification(
        deviceId,
        capturedPrintCharacteristic,
        parseHexBytes('55 55 1B 01 09 13 AA AA'),
      ),
    );
  };

  final result = await controller.queryMediaProbe(
    capturedPrintCharacteristic,
    includeStatus: false,
  );

  expect(
    transport.writes
        .map((write) => splitD11hFrames(write.bytes).single[2])
        .toList(),
    <int>[0x1A],
  );
  expect(result.statusResponse, isNull);
});

test('media probe validates notify and writeWithoutResponse capability', () {
  expect(
    controller.queryMediaProbe(writeCharacteristic),
    throwsA(isA<StateError>()),
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/research/probe_controller_test.dart`

Expected: FAIL because `queryMediaProbe` is not defined.

- [ ] **Step 3: Implement minimal controller method**

Add import:

```dart
import 'd11h_media_probe.dart';
```

Add method before `printCapturedTestLabel`:

```dart
Future<D11hMediaProbeResult> queryMediaProbe(
  BleCharacteristic characteristic, {
  bool includeStatus = true,
  Duration responseTimeout = const Duration(seconds: 2),
}) async {
  _ensureConnected('query media probe');
  if (!characteristic.canNotify ||
      !characteristic.properties.contains(
        BleCharacteristicProperty.writeWithoutResponse,
      )) {
    throw StateError(
      'Media probing requires notify and writeWithoutResponse.',
    );
  }

  try {
    await subscribe(characteristic);
    final deviceId = _connectedDevice!;
    final information = await _writeAndWaitForCommand(
      deviceId,
      characteristic,
      buildD11hCommand(0x1A, const <int>[]),
      0x1B,
      responseTimeout,
    );
    final status = includeStatus
        ? await _writeAndWaitForCommand(
            deviceId,
            characteristic,
            buildD11hCommand(0xA3, const <int>[]),
            0xB3,
            responseTimeout,
          )
        : null;

    return D11hMediaProbeResult(
      createdAt: DateTime.now().toUtc(),
      informationResponse: _protocolFrameFromRaw(information),
      statusResponse: status == null ? null : _protocolFrameFromRaw(status),
    );
  } catch (error) {
    _recordError('media probe failed', error);
    rethrow;
  }
}
```

Add helper near `_printedPageCount`:

```dart
D11hProtocolFrame _protocolFrameFromRaw(Uint8List frame) {
  if (frame.length < 7 ||
      frame[0] != 0x55 ||
      frame[1] != 0x55 ||
      frame[frame.length - 2] != 0xAA ||
      frame[frame.length - 1] != 0xAA) {
    throw const FormatException('Invalid D11H protocol frame.');
  }
  final payloadLength = frame[3];
  final payloadStart = 4;
  final payloadEnd = payloadStart + payloadLength;
  if (payloadEnd + 3 != frame.length) {
    throw const FormatException('Invalid D11H payload length.');
  }
  return D11hProtocolFrame(
    command: frame[2],
    payload: Uint8List.fromList(frame.sublist(payloadStart, payloadEnd)),
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/research/probe_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/research/probe_controller.dart test/research/probe_controller_test.dart
git commit -m "feat: query D11H media probe responses"
```

---

### Task 3: Probe App UI

**Files:**
- Modify: `tool/d11h_probe/lib/probe_page.dart`
- Test: `tool/d11h_probe/test/probe_page_test.dart`

- [ ] **Step 1: Write failing widget test**

Add a fake controller test that connects the page, taps `Detect media`, and expects raw hex:

```dart
testWidgets('detects media and renders raw probe responses', (tester) async {
  final controller = FakeProbeController();
  controller.connected = true;
  controller.services = <BleService>[
    BleService(
      serviceUuid: 'fff0',
      characteristics: <BleCharacteristic>[
        BleCharacteristic(
          serviceUuid: 'fff0',
          characteristicUuid: 'fff1',
          properties: const <BleCharacteristicProperty>[
            BleCharacteristicProperty.notify,
            BleCharacteristicProperty.writeWithoutResponse,
          ],
        ),
      ],
    ),
  ];
  controller.mediaProbeResult = D11hMediaProbeResult(
    createdAt: DateTime.utc(2026, 6, 16),
    informationResponse: D11hProtocolFrame(
      command: 0x1B,
      payload: Uint8List.fromList(<int>[0x01, 0x02]),
    ),
    statusResponse: D11hProtocolFrame(
      command: 0xB3,
      payload: Uint8List.fromList(<int>[0x00, 0x01, 0x64, 0x64]),
    ),
  );

  await pumpProbePage(tester, controller);

  await tester.tap(find.text('Detect media'));
  await tester.pumpAndSettle();

  expect(controller.mediaProbeCallCount, 1);
  expect(find.textContaining('Information 0x1B: 01 02'), findsOneWidget);
  expect(find.textContaining('Status 0xB3: 00 01 64 64'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test tool/d11h_probe/test/probe_page_test.dart`

Expected: FAIL because `Detect media` does not exist.

- [ ] **Step 3: Implement UI state and action**

In `_ProbePageState`, add:

```dart
D11hMediaProbeResult? _mediaProbeResult;
var _detectingMedia = false;
```

Add `_detectMedia()`:

```dart
Future<void> _detectMedia() async {
  final characteristic = findD11hPrintCharacteristic(
    widget.controller.services,
  );
  if (characteristic == null) {
    _showMessage('No D11H print characteristic available.');
    return;
  }
  setState(() => _detectingMedia = true);
  try {
    final result = await widget.controller.queryMediaProbe(characteristic);
    setState(() => _mediaProbeResult = result);
    _showMessage('Media probe completed.');
  } catch (error) {
    _showMessage('Media probe failed: $error');
  } finally {
    if (mounted) {
      setState(() => _detectingMedia = false);
    }
  }
}
```

Add a button near existing print controls:

```dart
FilledButton.icon(
  onPressed: connected && !_detectingMedia ? _detectMedia : null,
  icon: _detectingMedia
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.sensors_outlined),
  label: const Text('Detect media'),
),
```

Render result:

```dart
if (_mediaProbeResult case final result?) ...<Widget>[
  const SizedBox(height: 12),
  Text('Media probe', style: Theme.of(context).textTheme.titleMedium),
  SelectableText(
    'Information 0x${result.informationResponse.command.toRadixString(16).toUpperCase()}: '
    '${result.informationResponse.payloadHex}'
    '${result.statusResponse == null ? '' : '\nStatus 0x${result.statusResponse!.command.toRadixString(16).toUpperCase()}: ${result.statusResponse!.payloadHex}'}',
  ),
],
```

- [ ] **Step 4: Run widget test to verify it passes**

Run: `flutter test tool/d11h_probe/test/probe_page_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tool/d11h_probe/lib/probe_page.dart tool/d11h_probe/test/probe_page_test.dart
git commit -m "feat: add D11H media probe UI"
```

---

### Task 4: Protocol Documentation

**Files:**
- Modify: `docs/protocol/d11h/characterization.md`

- [ ] **Step 1: Document the experiment procedure**

Add a `Media detection probe` subsection under `Hypotheses`:

```markdown
### Media detection probe

The research app includes a D11H media probe that sends `1A` and optionally
one idle `A3` query on the print characteristic. This is not verified as RFID
or media-SKU detection.

Initial iOS procedure:

1. Run the probe three times with the current label roll loaded.
2. Open or remove the label path if physically safe, then run it three times.
3. Reinsert the same label roll and run it three times.
4. Compare sanitized `1B` and `B3` payloads across states.

Do not promote any byte to a named media field until repeated runs confirm it.
Do not claim media SKU detection until at least two different media rolls are
tested.
```

- [ ] **Step 2: Review docs diff**

Run: `git diff -- docs/protocol/d11h/characterization.md`

Expected: Diff contains only the media detection probe subsection.

- [ ] **Step 3: Commit**

```bash
git add docs/protocol/d11h/characterization.md
git commit -m "docs: add D11H media probe procedure"
```

---

### Task 5: Final Verification

**Files:**
- All changed files.

- [ ] **Step 1: Run focused research tests**

Run:

```bash
flutter test test/research/d11h_media_probe_test.dart test/research/probe_controller_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run probe app widget tests**

Run:

```bash
flutter test tool/d11h_probe/test/probe_page_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run formatting**

Run:

```bash
dart format lib/niimbot_research.dart lib/src/research/d11h_media_probe.dart lib/src/research/probe_controller.dart test/research/d11h_media_probe_test.dart test/research/probe_controller_test.dart tool/d11h_probe/lib/probe_page.dart tool/d11h_probe/test/probe_page_test.dart
```

Expected: Files formatted with no parse errors.

- [ ] **Step 4: Run full tests if focused tests pass**

Run:

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 5: Confirm git status**

Run: `git status --short`

Expected: clean working tree after commits.

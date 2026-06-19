# D11H Media Info and Remaining Estimate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in D11H media info API that interprets media probe responses and calculates remaining-label counts and percentages from user-provided roll profiles.

**Architecture:** Keep existing scan/connect/print behavior unchanged. Add focused public media models and a pure parser/estimator layer, then call it from `D11hPrinter.readMediaInfo(...)` and expose the same interpretation in the probe app for manual testing.

**Tech Stack:** Dart, Flutter, existing BLE transport abstractions, existing `ProbeController.queryMediaProbe(...)`, `flutter_test`.

---

## File Structure

- Create `lib/src/printer/d11h_media_info.dart`: stable public models and pure parser/remaining-estimate logic.
- Modify `lib/niimbot.dart`: export media info models.
- Modify `lib/src/printer/d11h_printer.dart`: add `readMediaInfo({D11hMediaRollProfile? profile, bool includeStatus = true})`.
- Modify `test/printer/d11h_media_info_test.dart`: pure parser and estimate tests.
- Modify `test/printer/d11h_printer_test.dart`: facade-level media info tests.
- Modify `tool/d11h_probe/lib/probe_page.dart`: add profile inputs and interpreted media info display.
- Modify `tool/d11h_probe/test/probe_page_test.dart`: widget coverage for remaining label and percent display.
- Modify `README.md`: document opt-in media info usage without changing print examples.
- Modify `docs/protocol/d11h/characterization.md`: record observed counter and remaining-estimate model.

---

### Task 1: Public Media Info Models and Parser

**Files:**
- Create: `lib/src/printer/d11h_media_info.dart`
- Modify: `lib/niimbot.dart`
- Test: `test/printer/d11h_media_info_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/printer/d11h_media_info_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_niimbot/niimbot.dart';
import 'package:flutter_niimbot/niimbot_research.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses not loaded media response', () {
    final info = D11hMediaInfo.fromProbeResult(
      D11hMediaProbeResult(
        createdAt: DateTime.utc(2026, 6, 19),
        informationResponse: D11hProtocolFrame(
          command: 0x1B,
          payload: Uint8List.fromList(<int>[0x00]),
        ),
        statusResponse: D11hProtocolFrame(
          command: 0xB3,
          payload: Uint8List.fromList(<int>[0, 0, 0, 0, 0x15, 0x17, 2, 0]),
        ),
      ),
    );

    expect(info.state, D11hMediaState.notLoaded);
    expect(info.candidateSerial, isNull);
    expect(info.candidateCode, isNull);
    expect(info.usageCounter, isNull);
    expect(info.remainingEstimate, isNull);
  });

  test('parses 12x22 loaded response and remaining percentage', () {
    final payload = parseHexBytes(
      '88 1d 35 d3 07 97 00 00 '
      '0d 36 39 37 32 38 34 32 37 34 37 35 34 39 '
      '10 50 43 30 47 34 32 38 33 33 30 30 30 35 34 36 34 '
      '01 38 00 01 01',
    );

    final info = D11hMediaInfo.fromProbeResult(
      D11hMediaProbeResult(
        createdAt: DateTime.utc(2026, 6, 19),
        informationResponse: D11hProtocolFrame(command: 0x1B, payload: payload),
        statusResponse: null,
      ),
      profile: D11hMediaRollProfile(
        totalLabels: 260,
        baselineCounter: 256,
        name: '12x22',
      ),
    );

    expect(info.state, D11hMediaState.loaded);
    expect(info.candidateSerial, '6972842747549');
    expect(info.candidateCode, 'PC0G428330005464');
    expect(info.usageCounter, 257);
    expect(info.remainingEstimate?.usedLabels, 1);
    expect(info.remainingEstimate?.remainingLabels, 259);
    expect(info.remainingEstimate?.remainingPercent, closeTo(99.615, 0.001));
    expect(info.remainingEstimate?.isOutOfRange, isFalse);
  });

  test('parses 12x30 loaded response with caller profile', () {
    final payload = parseHexBytes(
      '88 1d 2c 87 98 1a 10 80 '
      '09 30 39 31 32 32 35 31 37 39 '
      '10 50 4a 30 49 33 31 31 37 31 31 30 30 30 35 35 31 '
      '00 ea 00 09 01',
    );

    final info = D11hMediaInfo.fromProbeResult(
      D11hMediaProbeResult(
        createdAt: DateTime.utc(2026, 6, 19),
        informationResponse: D11hProtocolFrame(command: 0x1B, payload: payload),
        statusResponse: null,
      ),
      profile: D11hMediaRollProfile(
        totalLabels: 195,
        baselineCounter: 259,
        name: '12x30',
      ),
    );

    expect(info.candidateSerial, '091225179');
    expect(info.candidateCode, 'PJ0I311711000551');
    expect(info.usageCounter, 265);
    expect(info.remainingEstimate?.remainingLabels, 189);
    expect(info.remainingEstimate?.remainingPercent, closeTo(96.923, 0.001));
  });

  test('remaining estimate clamps impossible profile data', () {
    final estimate = D11hRemainingEstimate.fromCounter(
      currentCounter: 300,
      profile: D11hMediaRollProfile(totalLabels: 10, baselineCounter: 100),
    );

    expect(estimate.usedLabels, 10);
    expect(estimate.remainingLabels, 0);
    expect(estimate.remainingPercent, 0);
    expect(estimate.isOutOfRange, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/printer/d11h_media_info_test.dart`

Expected: FAIL because `D11hMediaInfo`, `D11hMediaState`, `D11hMediaRollProfile`, and `D11hRemainingEstimate` are not defined.

- [ ] **Step 3: Implement minimal models and parser**

Create `lib/src/printer/d11h_media_info.dart`:

```dart
import '../research/d11h_media_probe.dart';

enum D11hMediaState { loaded, notLoaded, unknown }

final class D11hMediaRollProfile {
  D11hMediaRollProfile._({
    required this.totalLabels,
    required this.baselineCounter,
    this.name,
  });

  factory D11hMediaRollProfile({
    required int totalLabels,
    required int baselineCounter,
    String? name,
  }) {
    if (totalLabels <= 0) {
      throw ArgumentError.value(totalLabels, 'totalLabels', 'Must be positive.');
    }
    if (baselineCounter < 0) {
      throw ArgumentError.value(
        baselineCounter,
        'baselineCounter',
        'Must be non-negative.',
      );
    }
    return D11hMediaRollProfile._(
      totalLabels: totalLabels,
      baselineCounter: baselineCounter,
      name: name,
    );
  }

  final int totalLabels;
  final int baselineCounter;
  final String? name;
}

final class D11hRemainingEstimate {
  const D11hRemainingEstimate._({
    required this.totalLabels,
    required this.usedLabels,
    required this.remainingLabels,
    required this.remainingRatio,
    required this.remainingPercent,
    required this.isOutOfRange,
  });

  factory D11hRemainingEstimate.fromCounter({
    required int currentCounter,
    required D11hMediaRollProfile profile,
  }) {
    final rawUsed = currentCounter - profile.baselineCounter;
    final isOutOfRange = rawUsed < 0 || rawUsed > profile.totalLabels;
    final used = rawUsed.clamp(0, profile.totalLabels);
    final remaining = profile.totalLabels - used;
    final ratio = remaining / profile.totalLabels;
    return D11hRemainingEstimate._(
      totalLabels: profile.totalLabels,
      usedLabels: used,
      remainingLabels: remaining,
      remainingRatio: ratio,
      remainingPercent: ratio * 100,
      isOutOfRange: isOutOfRange,
    );
  }

  final int totalLabels;
  final int usedLabels;
  final int remainingLabels;
  final double remainingRatio;
  final double remainingPercent;
  final bool isOutOfRange;
}

final class D11hMediaInfo {
  const D11hMediaInfo._({
    required this.state,
    required this.createdAt,
    required this.candidateSerial,
    required this.candidateCode,
    required this.usageCounter,
    required this.remainingEstimate,
    required this.informationResponse,
    required this.statusResponse,
  });

  factory D11hMediaInfo.fromProbeResult(
    D11hMediaProbeResult result, {
    D11hMediaRollProfile? profile,
  }) {
    final payload = result.informationResponse.payload;
    if (payload.length == 1 && payload.single == 0) {
      return D11hMediaInfo._(
        state: D11hMediaState.notLoaded,
        createdAt: result.createdAt,
        candidateSerial: null,
        candidateCode: null,
        usageCounter: null,
        remainingEstimate: null,
        informationResponse: result.informationResponse,
        statusResponse: result.statusResponse,
      );
    }

    if (payload.length < 2) {
      return D11hMediaInfo._(
        state: D11hMediaState.unknown,
        createdAt: result.createdAt,
        candidateSerial: null,
        candidateCode: null,
        usageCounter: null,
        remainingEstimate: null,
        informationResponse: result.informationResponse,
        statusResponse: result.statusResponse,
      );
    }

    final strings = _candidateAsciiStrings(payload);
    final counter = payload[payload.length - 2] | (payload.last << 8);
    return D11hMediaInfo._(
      state: D11hMediaState.loaded,
      createdAt: result.createdAt,
      candidateSerial: strings.isNotEmpty ? strings[0] : null,
      candidateCode: strings.length > 1 ? strings[1] : null,
      usageCounter: counter,
      remainingEstimate: profile == null
          ? null
          : D11hRemainingEstimate.fromCounter(
              currentCounter: counter,
              profile: profile,
            ),
      informationResponse: result.informationResponse,
      statusResponse: result.statusResponse,
    );
  }

  final D11hMediaState state;
  final DateTime createdAt;
  final String? candidateSerial;
  final String? candidateCode;
  final int? usageCounter;
  final D11hRemainingEstimate? remainingEstimate;
  final D11hProtocolFrame informationResponse;
  final D11hProtocolFrame? statusResponse;
}

List<String> _candidateAsciiStrings(List<int> payload) {
  final values = <String>[];
  for (var index = 0; index < payload.length; index++) {
    final length = payload[index];
    final start = index + 1;
    final end = start + length;
    if (length < 4 || end > payload.length) {
      continue;
    }
    final bytes = payload.sublist(start, end);
    final printable = bytes.every(
      (byte) => byte >= 0x20 && byte <= 0x7E,
    );
    if (printable) {
      values.add(String.fromCharCodes(bytes));
      index = end - 1;
    }
  }
  return values;
}
```

Add to `lib/niimbot.dart`:

```dart
export 'src/printer/d11h_media_info.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/printer/d11h_media_info_test.dart`

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run:

```bash
dart format lib/src/printer/d11h_media_info.dart lib/niimbot.dart test/printer/d11h_media_info_test.dart
git add lib/src/printer/d11h_media_info.dart lib/niimbot.dart test/printer/d11h_media_info_test.dart
git commit -m "feat: add D11H media info models"
```

---

### Task 2: Printer Facade API

**Files:**
- Modify: `lib/src/printer/d11h_printer.dart`
- Test: `test/printer/d11h_printer_test.dart`

- [ ] **Step 1: Write failing facade tests**

Add helper near `_respondToPrintWrites`:

```dart
void _respondToMediaProbeWrites(FakeBleTransport transport) {
  transport.writeResponder = (write) {
    final command = write.bytes[2];
    final response = switch (command) {
      0x1A => buildD11hCommand(
          0x1B,
          const <int>[
            0x88, 0x1d, 0x35, 0xd3, 0x07, 0x97, 0x00, 0x00,
            0x0d, 0x36, 0x39, 0x37, 0x32, 0x38, 0x34, 0x32, 0x37, 0x34, 0x37, 0x35, 0x34, 0x39,
            0x10, 0x50, 0x43, 0x30, 0x47, 0x34, 0x32, 0x38, 0x33, 0x33, 0x30, 0x30, 0x30, 0x35, 0x34, 0x36, 0x34,
            0x01, 0x38, 0x00, 0x01, 0x01,
          ],
        ),
      0xA3 => buildD11hCommand(0xB3, const <int>[0, 1, 0x64, 0x64, 0x15, 0x16, 0, 0]),
      _ => null,
    };
    if (response != null) {
      transport.emitNotification(write.deviceId, write.characteristic, response);
    }
  };
}
```

Add tests:

```dart
test('readMediaInfo returns interpreted media without reconnecting', () async {
  final transport = FakeBleTransport(services: <BleService>[_printService]);
  final printer = D11hPrinter.withTransport(transport);
  addTearDown(printer.dispose);
  _respondToMediaProbeWrites(transport);

  await _completeConnection(printer.connect(_deviceId), transport);
  final connectCount = transport.connectCallCount;

  final info = await printer.readMediaInfo(
    profile: D11hMediaRollProfile(
      totalLabels: 260,
      baselineCounter: 256,
      name: '12x22',
    ),
  );

  expect(transport.connectCallCount, connectCount);
  expect(info.state, D11hMediaState.loaded);
  expect(info.candidateCode, 'PC0G428330005464');
  expect(info.remainingEstimate?.remainingLabels, 259);
  expect(
    transport.writes.map((write) => write.bytes[2]).toList(),
    <int>[0x1A, 0xA3],
  );
});

test('readMediaInfo rejects use before connecting', () async {
  final printer = D11hPrinter.withTransport(FakeBleTransport());
  addTearDown(printer.dispose);

  await expectLater(printer.readMediaInfo(), throwsStateError);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/printer/d11h_printer_test.dart`

Expected: FAIL because `readMediaInfo` is not defined.

- [ ] **Step 3: Implement facade method**

In `lib/src/printer/d11h_printer.dart`, import media info:

```dart
import 'd11h_media_info.dart';
```

Add method before `printLabel`:

```dart
Future<D11hMediaInfo> readMediaInfo({
  D11hMediaRollProfile? profile,
  bool includeStatus = true,
}) => _enqueue(() async {
  if (_controller.connectedDevice == null) {
    throw StateError(
      'Cannot read media information before connecting with connect().',
    );
  }

  final characteristic = findD11hPrintCharacteristic(_controller.services);
  if (characteristic == null) {
    throw StateError(
      'Connected device does not expose D11H FFF0/FFF1 with '
      'notify and writeWithoutResponse.',
    );
  }

  final result = await _controller.queryMediaProbe(
    characteristic,
    includeStatus: includeStatus,
  );
  return D11hMediaInfo.fromProbeResult(result, profile: profile);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/printer/d11h_printer_test.dart`

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run:

```bash
dart format lib/src/printer/d11h_printer.dart test/printer/d11h_printer_test.dart
git add lib/src/printer/d11h_printer.dart test/printer/d11h_printer_test.dart
git commit -m "feat: expose D11H media info facade"
```

---

### Task 3: Probe App Remaining Estimate UI

**Files:**
- Modify: `tool/d11h_probe/lib/probe_page.dart`
- Test: `tool/d11h_probe/test/probe_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add to `tool/d11h_probe/test/probe_page_test.dart`:

```dart
testWidgets('detects media with profile and renders remaining percent', (tester) async {
  final transport = _ProbeTestTransport();
  final controller = ProbeController(transport);

  await tester.pumpWidget(
    MaterialApp(
      home: ProbePage(
        controller: controller,
        requestPermissions: () async => true,
        scanDuration: const Duration(milliseconds: 20),
        rasterInterWriteDelay: Duration.zero,
      ),
    ),
  );

  await tester.tap(find.text('Scan for D11H'));
  await tester.pump();
  transport.emitAdvertisement();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 25));
  await tester.pumpAndSettle();
  await tester.tap(find.text('D11_H'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('media-total-input')), '260');
  await tester.enterText(find.byKey(const Key('media-baseline-input')), '256');
  tester.testTextInput.hide();
  await tester.pumpAndSettle();

  await tester.tap(find.text('Detect media'));
  await tester.pumpAndSettle();

  expect(find.textContaining('State: loaded'), findsOneWidget);
  expect(find.textContaining('Counter: 257'), findsOneWidget);
  expect(find.textContaining('Remaining: 259 / 260 (99.6%)'), findsOneWidget);
});

testWidgets('uses latest media counter as baseline', (tester) async {
  final transport = _ProbeTestTransport();
  final controller = ProbeController(transport);

  await tester.pumpWidget(
    MaterialApp(
      home: ProbePage(
        controller: controller,
        requestPermissions: () async => true,
        scanDuration: const Duration(milliseconds: 20),
        rasterInterWriteDelay: Duration.zero,
      ),
    ),
  );

  await tester.tap(find.text('Scan for D11H'));
  await tester.pump();
  transport.emitAdvertisement();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 25));
  await tester.pumpAndSettle();
  await tester.tap(find.text('D11_H'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Detect media'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Use counter as baseline'));
  await tester.pumpAndSettle();

  expect(
    tester.widget<TextField>(find.byKey(const Key('media-baseline-input')))
        .controller
        ?.text,
    '257',
  );
});
```

Update `_ProbeTestTransport.write` media probe response for `0x1A` to end with `01 01`:

```dart
0x1A => '55 55 1B 2D 88 1D 35 D3 07 97 00 00 0D 36 39 37 32 38 34 32 37 34 37 35 34 39 10 50 43 30 47 34 32 38 33 33 30 30 30 35 34 36 34 01 38 00 01 01 D0 AA AA',
```

- [ ] **Step 2: Run test to verify it fails**

Run from `tool/d11h_probe`: `flutter test test/probe_page_test.dart`

Expected: FAIL because `media-total-input`, `media-baseline-input`, `Use counter as baseline`, and interpreted remaining text are not present.

- [ ] **Step 3: Implement probe app profile inputs and formatting**

In `_ProbePageState`, add controllers:

```dart
final _mediaTotalLabels = TextEditingController();
final _mediaBaselineCounter = TextEditingController();
```

Dispose them:

```dart
_mediaTotalLabels.dispose();
_mediaBaselineCounter.dispose();
```

Add profile helper:

```dart
D11hMediaRollProfile? _mediaProfile() {
  final totalText = _mediaTotalLabels.text.trim();
  final baselineText = _mediaBaselineCounter.text.trim();
  if (totalText.isEmpty || baselineText.isEmpty) {
    return null;
  }
  final total = int.tryParse(totalText);
  final baseline = int.tryParse(baselineText);
  if (total == null || total <= 0 || baseline == null || baseline < 0) {
    return null;
  }
  return D11hMediaRollProfile(
    totalLabels: total,
    baselineCounter: baseline,
  );
}
```

Update `_detectMedia`:

```dart
final result = await widget.controller.queryMediaProbe(characteristic);
setState(() => _mediaProbeResult = result);
```

Add latest-counter baseline helper:

```dart
void _useLatestCounterAsBaseline() {
  final result = _mediaProbeResult;
  if (result == null) {
    _showMessage('Run Detect media first.');
    return;
  }
  final info = D11hMediaInfo.fromProbeResult(result);
  final counter = info.usageCounter;
  if (counter == null) {
    _showMessage('No media counter available.');
    return;
  }
  setState(() => _mediaBaselineCounter.text = '$counter');
}
```

Use local formatting call:

```dart
_formatMediaProbeResult(result, profile: _mediaProfile())
```

Add UI inputs before `Detect media` result:

```dart
TextField(
  key: const Key('media-total-input'),
  controller: _mediaTotalLabels,
  keyboardType: TextInputType.number,
  decoration: const InputDecoration(labelText: 'Total labels'),
),
TextField(
  key: const Key('media-baseline-input'),
  controller: _mediaBaselineCounter,
  keyboardType: TextInputType.number,
  decoration: const InputDecoration(labelText: 'Baseline counter'),
),
OutlinedButton(
  onPressed: _mediaProbeResult == null ? null : _useLatestCounterAsBaseline,
  child: const Text('Use counter as baseline'),
),
```

Update formatter:

```dart
String _formatMediaProbeResult(
  D11hMediaProbeResult result, {
  D11hMediaRollProfile? profile,
}) {
  final info = D11hMediaInfo.fromProbeResult(result, profile: profile);
  final lines = <String>[
    'State: ${info.state.name}',
    if (info.candidateSerial != null) 'Serial candidate: ${info.candidateSerial}',
    if (info.candidateCode != null) 'Code candidate: ${info.candidateCode}',
    if (info.usageCounter != null) 'Counter: ${info.usageCounter}',
    if (info.remainingEstimate case final estimate?)
      'Remaining: ${estimate.remainingLabels} / ${estimate.totalLabels} '
          '(${estimate.remainingPercent.toStringAsFixed(1)}%)'
    else
      'Remaining: unknown',
    'Raw information 0x${_formatCommand(result.informationResponse.command)}: '
        '${result.informationResponse.payloadHex}',
  ];
  final status = result.statusResponse;
  if (status != null) {
    lines.add('Raw status 0x${_formatCommand(status.command)}: ${status.payloadHex}');
  }
  return lines.join('\n');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run from `tool/d11h_probe`: `flutter test test/probe_page_test.dart`

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run:

```bash
dart format tool/d11h_probe/lib/probe_page.dart tool/d11h_probe/test/probe_page_test.dart
git add tool/d11h_probe/lib/probe_page.dart tool/d11h_probe/test/probe_page_test.dart
git commit -m "feat: show D11H media remaining estimate in probe"
```

---

### Task 4: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/protocol/d11h/characterization.md`

- [ ] **Step 1: Document public usage in README**

Add a `Media information` section after printing behavior:

```markdown
### Media information

Media information is opt-in and does not run automatically before printing.
Applications provide their own roll profile when they want remaining-label
estimates:

```dart
final info = await printer.readMediaInfo(
  profile: D11hMediaRollProfile(
    totalLabels: 260,
    baselineCounter: 256,
    name: '12x22 roll',
  ),
);

print(info.state);
print(info.usageCounter);
print(info.remainingEstimate?.remainingLabels);
print(info.remainingEstimate?.remainingPercent);
```

Without a profile, the library reports loaded/not-loaded state, candidate
identifiers, raw frames, and the observed counter, but remaining labels are
unknown.
```

- [ ] **Step 2: Document observed counter model**

Append to `docs/protocol/d11h/characterization.md` under `Media detection probe`:

```markdown
Observed iOS D11H media-counter behavior:

- The final two information payload bytes are little-endian.
- They increase by one per printed label.
- A 12x22 roll with a 260-label user-provided total was observed at baseline
  `00 01` (256).
- A 12x30 roll with a 195-label user-provided total was observed with a
  first-seen baseline of `03 01` (259).

Remaining estimates require application-provided total labels and baseline
counter values. The payload has not shown a direct total-label field.
```

- [ ] **Step 3: Review docs diff**

Run: `git diff -- README.md docs/protocol/d11h/characterization.md`

Expected: Diff contains only media info usage and observed counter notes.

- [ ] **Step 4: Commit**

Run:

```bash
git add README.md docs/protocol/d11h/characterization.md
git commit -m "docs: document D11H media remaining estimates"
```

---

### Task 5: Final Verification

**Files:**
- All changed files.

- [ ] **Step 1: Run focused root tests**

Run:

```bash
flutter test test/printer/d11h_media_info_test.dart test/printer/d11h_printer_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run probe app widget tests**

Run from `tool/d11h_probe`:

```bash
flutter test test/probe_page_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run full root test suite**

Run from repo root:

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 4: Run full probe app test suite**

Run from `tool/d11h_probe`:

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 5: Confirm git status**

Run:

```bash
git status --short
```

Expected: clean working tree after commits.

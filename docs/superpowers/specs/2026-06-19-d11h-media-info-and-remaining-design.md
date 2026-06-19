# D11H Media Info and Remaining Estimate Design

## Goal

Add an opt-in media information API for NIIMBOT D11H that reads the existing
media probe response, interprets loaded/not-loaded state, extracts candidate
roll identifiers, and estimates remaining labels as a percentage when the
application supplies roll metadata.

The existing scan, connect, render, and print APIs must continue to behave as
they do today. Media estimation is a separate feature that applications call
explicitly.

## Current Context

The library currently has:

- Stable D11H printing APIs through `D11hPrinter`.
- Research-only `ProbeController.queryMediaProbe()` that sends `1A` and
  optionally `A3`.
- Raw research models for D11H protocol frames.
- A probe app button that displays raw media probe responses.

Field observations on iOS D11H show:

- `Information 0x1B: 00` when no label roll is loaded.
- A longer `Information 0x1B` payload when a label roll is loaded.
- Two ASCII-like strings in the loaded information payload.
- The final two information payload bytes increase by one per printed label.
- Known user-provided totals:
  - 12x22 media: 260 labels.
  - 12x30 media: 195 labels.

The total label count is not directly visible in observed payload bytes. The
application must provide total count and baseline counter values when it wants
remaining-label estimates.

## Scope

In scope:

- Add stable public models for D11H media information.
- Add an explicit `D11hPrinter.readMediaInfo(...)` API.
- Parse loaded/not-loaded state from the media probe result.
- Extract candidate ASCII strings from the loaded information payload.
- Extract the final two-byte little-endian usage counter.
- Estimate remaining labels and remaining percent when a profile is supplied.
- Display interpreted values in the probe app so the user can test directly.
- Keep raw response data available for diagnostics.

Out of scope:

- Automatically detecting total labels without application input.
- Persisting roll baselines or remaining counts on disk.
- Modifying print behavior to automatically read media before or after print.
- Claiming official SKU mappings for observed candidate strings.
- Supporting non-D11H models.

## Public API

Add these stable models under the public `niimbot.dart` entry point.

### `D11hMediaState`

Values:

- `loaded`
- `notLoaded`
- `unknown`

### `D11hMediaRollProfile`

Application-provided metadata for estimating remaining labels.

Fields:

- `totalLabels`: positive integer.
- `counterAtBaseline`: non-negative opaque RFID counter value captured when the
  application chooses the tracking baseline.
- `remainingLabelsAtBaseline`: remaining label count at that same baseline,
  from `0` through `totalLabels`.
- `name`: optional display name such as `12x22` or `12x30`.

The library does not ship default total-label presets in this first pass.
Applications can construct profiles from their own product data or from a
first-seen baseline. For a new roll, `remainingLabelsAtBaseline` usually equals
`totalLabels`; for a used roll, it is the user's approximate remaining count.

### `D11hRemainingEstimate`

Fields:

- `totalLabels`: profile total.
- `usedLabels`: clamped integer.
- `remainingLabels`: clamped integer.
- `remainingRatio`: double from `0.0` to `1.0`.
- `remainingPercent`: double from `0.0` to `100.0`.
- `isOutOfRange`: true when the counter is below baseline or the resulting
  remaining count falls outside `0...totalLabels` before clamping.

Calculation:

```text
rawUsedSinceBaseline = currentCounter - counterAtBaseline
rawRemaining = remainingLabelsAtBaseline - rawUsedSinceBaseline
remainingLabels = clamp(rawRemaining, 0, totalLabels)
usedLabels = totalLabels - remainingLabels
remainingRatio = remainingLabels / totalLabels
remainingPercent = remainingRatio * 100
```

Clamping keeps the API safe when a caller supplies a stale or wrong baseline.
`isOutOfRange` lets applications surface that the estimate is suspicious.

### `D11hMediaInfo`

Fields:

- `state`: loaded, notLoaded, or unknown.
- `createdAt`: timestamp from the probe run.
- `candidateSerial`: first printable ASCII string found in the information
  payload, if present.
- `candidateCode`: second printable ASCII string found in the information
  payload, if present.
- `usageCounter`: final two-byte little-endian information counter, if present.
- `remainingEstimate`: present only when `usageCounter` and a valid
  `D11hMediaRollProfile` are both available.
- `informationResponse`: raw D11H frame.
- `statusResponse`: optional raw D11H frame.

## Printer API

Add:

```dart
Future<D11hMediaInfo> readMediaInfo({
  D11hMediaRollProfile? profile,
  bool includeStatus = true,
});
```

Behavior:

1. Requires an active connection, like `printRenderedLabel`.
2. Finds the D11H print characteristic using existing discovery logic.
3. Calls the existing `ProbeController.queryMediaProbe(...)`.
4. Converts the raw result into `D11hMediaInfo`.
5. Does not disconnect, reconnect, print, or mutate caller-provided profiles.

Errors:

- Not connected.
- Missing suitable print characteristic.
- BLE write/notification timeout from the existing probe path.

## Parsing Rules

Information payload:

- Exactly one byte `00` means `notLoaded`.
- Loaded payloads are interpreted conservatively.
- Printable ASCII runs with a length byte immediately before them are candidate
  identifiers.
- The first candidate run becomes `candidateSerial`.
- The second candidate run becomes `candidateCode`.
- The final two bytes become `usageCounter` using little-endian decoding.
- If the payload is too short or malformed, state is `unknown` and raw bytes are
  still exposed.

The parser must not hard-code observed candidate strings as official media SKU
values.

## Probe App

Update `tool/d11h_probe` so `Detect media` displays interpreted fields above
the raw payload:

```text
State: loaded
Serial candidate: 6972842747549
Code candidate: PC0G428330005464
Counter: 257
Remaining: 259 / 260 (99.6%)
Raw information: ...
Raw status: ...
```

To let the user test directly, add simple profile controls in the probe app:

- Total labels numeric input.
- Counter-at-baseline numeric input.
- Remaining-labels-at-baseline numeric input.
- A clear affordance to copy the latest counter into the baseline field.
- A save action that persists the profile by detected roll identity so the
  estimate survives app restarts.

The probe app should not imply that candidate strings are official SKU codes.

## Testing

Unit tests:

- Not-loaded payload returns `state == notLoaded`.
- Loaded 12x22 sample extracts serial, code, and counter.
- Loaded 12x30 sample extracts serial, code, and counter.
- Remaining estimate calculates labels and percent from a supplied profile.
- Remaining estimate clamps impossible values and marks `isOutOfRange`.
- `D11hPrinter.readMediaInfo()` preserves existing connection behavior and
  returns interpreted information.

Probe app widget tests:

- Shows state, counter, remaining labels, and percent when profile inputs are
  provided.
- Shows `unknown` remaining when no complete profile is provided.
- Can set the current counter as baseline for direct manual testing.
- Does not infer a full roll just because the user copied the current counter.
- Restores a saved profile for the same detected roll identity after the probe
  page is recreated.

Manual iOS testing:

1. Connect to D11H.
2. Confirm the automatic media read shows state, candidate identifiers, and
   counter.
3. Enter total label count for the loaded roll.
4. Enter remaining labels at the baseline, or use total labels for a new roll.
5. Set the current counter as baseline if starting a new tracking session.
6. Save the tracking profile.
7. Print one label.
8. Run `Detect media` again.
9. Confirm remaining labels decreases by one and percent updates.
10. Restart the probe app and reconnect; confirm the same roll loads the saved
    profile instead of showing 100%.

## Compatibility

This feature is additive:

- No existing public method signature changes.
- Existing printing behavior stays unchanged.
- Existing raw research API remains available.
- Applications that do not call `readMediaInfo()` are unaffected.

# D11H Media Detection Design

## Goal

Add an iOS-first research workflow for discovering whether a NIIMBOT D11H
exposes loaded-label media information over BLE. The immediate target is not
RFID UID access. The target is consumable/media detection: whether a label is
loaded, whether the printer reports stable media fields, and whether those
fields can later be mapped to label size or type.

## Current Context

The package currently supports D11H scanning, connection, text-label rendering,
and printing. The stable `D11hPrinter` facade intentionally exposes only
verified printing behavior.

The research app already supports:

- BLE device scanning and connection.
- Service and characteristic inspection.
- Notification subscription.
- Raw hexadecimal writes.
- Sanitized event-log export.

The protocol notes list `SEND 1A` / `RECV 1B` as a suspected device or printer
information query, and repeated `SEND A3` / `RECV B3` as suspected
status/progress queries. Neither command has been verified as media detection.

## Scope

This feature adds a research-only media probe path. It must help collect
repeatable evidence before any stable public API is added.

In scope:

- Add a one-tap media detection probe to `tool/d11h_probe`.
- Send a small, explicit set of already-observed D11H protocol commands.
- Capture raw responses and show them in the probe UI.
- Log sanitized write and notification events through the existing log path.
- Record the experiment procedure and current interpretation limits.
- Keep all results labeled as unverified until repeated testing confirms them.

Out of scope:

- Reading RFID or NFC UID values directly.
- Claiming label size, type, or remaining quantity from an unverified field.
- Adding stable `D11hPrinter` media APIs in the first implementation.
- Supporting non-D11H printers.
- Adding Android verification in this first pass.

## User Test Environment

Initial verification will use:

- NIIMBOT D11H hardware.
- iOS probe app.
- One available label media roll.

Because only one label media type is available, the first pass can verify
stability and state changes, but cannot prove that a field distinguishes
different media SKUs.

## Proposed Workflow

The probe app exposes a `Detect media` action when connected to a D11H print
characteristic that supports notifications and `writeWithoutResponse`.

When tapped, the probe:

1. Subscribes to the print characteristic.
2. Sends the D11H `0x1A` information query frame.
3. Waits for the expected `0x1B` response.
4. Optionally sends one idle `0xA3` status query and waits for `0xB3`.
5. Displays a compact result containing response commands and raw payload hex.
6. Leaves detailed writes and notifications in the sanitized event log.

The UI copy should avoid definitive claims. It should use terms such as
`Media probe`, `raw information response`, and `raw status response`.

## Data Model

Create a research-only result model, exported from `niimbot_research.dart`:

- `D11hMediaProbeResult`
  - `informationResponse`: parsed D11H frame for the `0x1B` response.
  - `statusResponse`: optional parsed D11H frame for the `0xB3` response.
  - `createdAt`: timestamp for the probe run.

- `D11hProtocolFrame`
  - `command`: integer command byte.
  - `payload`: immutable bytes.
  - `payloadHex`: formatted lowercase hex string.

The model should preserve raw bytes and avoid naming fields whose meaning is not
verified.

## Controller Changes

Add `ProbeController.queryMediaProbe(...)`.

Responsibilities:

- Require an active BLE connection.
- Require notify plus `writeWithoutResponse` on the selected characteristic.
- Subscribe before writing.
- Build D11H frames with the existing `buildD11hCommand` helper.
- Use the existing response-waiting path where practical.
- Return `D11hMediaProbeResult`.
- Record errors through the existing probe error logging path.

The method should default to querying both information and status, but allow the
status query to be disabled if it proves noisy during testing.

## UI Changes

In `tool/d11h_probe`, add a `Detect media` button near the existing print and
raw-write research controls.

The button should:

- Be enabled only when a suitable print characteristic is discoverable.
- Run the media probe on the warm connection.
- Show a progress state while running.
- Display the latest result in a small text section.
- Leave the copyable sanitized log as the authoritative detailed record.

## Experiment Procedure

The initial iOS procedure:

1. Connect to the D11H with one label roll loaded.
2. Run `Detect media` three times without changing printer state.
3. Remove or open the label path if physically safe, then run it three times.
4. Reinsert the same label roll and run it three times.
5. Copy the sanitized log and compare payloads across states.

Stable bytes across repeated runs are candidates for device or media fields.
Bytes that change only when label state changes are candidates for loaded-media
or status fields. No field should be promoted to a named public API until it is
confirmed by repeated runs and, for media type, at least two different label
media SKUs.

## Error Handling

The probe should surface:

- Not connected.
- No suitable D11H print characteristic.
- Notification timeout.
- Unexpected response command.
- BLE write failure.

Errors should be visible in the UI and recorded in the sanitized event log.

## Testing

Unit tests should cover:

- D11H frame parsing for single and concatenated responses.
- `queryMediaProbe` sends `0x1A` and expects `0x1B`.
- Optional status query sends `0xA3` and expects `0xB3`.
- Capability validation rejects characteristics without notify or
  `writeWithoutResponse`.
- Probe UI calls the controller and renders raw response hex.

Manual iOS testing on real D11H hardware is required before documenting any
observed media fields.

## Public API Position

This first pass remains research-only. A stable API such as
`D11hPrinter.readMediaInfo()` should be designed later, after the project can
name fields with confidence. Until then, applications should not rely on media
detection behavior for production workflows.

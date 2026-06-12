# NIIMBOT D11H Flutter Library Design

## 1. Purpose

Build a pub.dev-ready Flutter library for reliable Bluetooth Low Energy (BLE)
communication and label printing with the NIIMBOT D11H printer.

The first stable release will support Android and iOS simultaneously. D11H is
the only printer model in scope, but model-specific behavior will be isolated so
additional NIIMBOT drivers can be added later without changing the public API.

The package itself will be UI-independent. A complete `example` application
will provide device discovery, connection, label editing, preview, printing,
diagnostics, and failure testing from a screen.

## 2. Goals

- Discover, connect to, disconnect from, and reconnect to a D11H on Android and
  iOS.
- Print labels containing text, images, barcodes, and QR codes.
- Support both element-based label composition and printing a completed bitmap.
- Detect transport, protocol, printer-state, and rendering failures without
  reporting an unverified print as successful.
- Support queued jobs, multiple copies, progress, cancellation, timeouts, and
  bounded retries.
- Provide useful typed errors and opt-in diagnostic logging.
- Reach at least a 99% success rate over 100 repeated prints of a validated test
  label on each supported platform and test configuration.
- Publish with API documentation, a complete example app, a changelog, tests,
  and an appropriate open-source license.

## 3. Non-Goals

- Supporting NIIMBOT models other than D11H in the first stable release.
- Shipping label-editing widgets as part of the package's public API.
- Depending on or copying source code from `niim_blue_flutter`.
- Claiming that wireless or mechanical printing can never fail.
- Exposing unverified D11H commands as stable public functionality.
- Automatically resuming a partially transmitted label after disconnection.

## 4. Research and Compatibility Policy

The D11H protocol will be implemented independently using:

1. Publicly available protocol descriptions and technical information.
2. BLE packet captures from legitimate use of the official application with a
   D11H owned by the developer.
3. Repeatable experiments against the physical printer.

Public information and observed behavior may be used to understand the wire
protocol. Third-party package source will not be copied. Findings must be
recorded as protocol notes and validated with tests before becoming stable API.

The package will initially use a maintained cross-platform Flutter BLE backend.
That dependency will sit behind an internal transport interface. Kotlin or
Swift extensions will be introduced only for platform behavior that cannot be
implemented reliably through the selected backend.

## 5. Architecture

The library uses a layered driver architecture:

```text
Application
    |
Public API (NiimbotClient)
    |
Connection Manager + Print Job Queue
    |
Device Driver (D11hDriver)
    |
Transport Contract (BleTransport)
    |
Flutter BLE backend / targeted native fallback
```

### 5.1 Public API

`NiimbotClient` is the main entry point. It provides:

- Bluetooth readiness and permission status
- D11H discovery
- Connect and disconnect operations
- Connection and printer-state streams
- Device information and supported capabilities
- Print submission, progress, cancellation, and result reporting
- Diagnostic configuration

The public API exposes domain models rather than BLE services,
characteristics, or raw packets. An explicitly advanced diagnostics surface may
expose sanitized protocol events, but raw packet transmission is not part of
the stable API.

### 5.2 BLE Transport

`BleTransport` owns platform-independent transport operations:

- Adapter state observation
- Permission-related readiness checks
- Scanning and discovery results
- Connection establishment and teardown
- Service and characteristic discovery
- Notification subscription
- MTU-aware writes and incoming byte delivery

The transport does not know how D11H packets are encoded. It can be replaced by
a fake implementation in tests or by another BLE backend without changing the
driver and public API.

Permission prompts remain application-controlled. The library reports required
permissions and actionable failures; the example app demonstrates the complete
Android and iOS permission flow.

### 5.3 Connection Manager

The connection manager owns this state machine:

```text
disconnected -> scanning -> connecting -> discovering -> ready -> printing
                     ^             |                         |
                     |             v                         v
                     +--------- reconnecting <----------- disconnected
```

Only valid transitions are emitted. A disconnect requested by the application
does not trigger automatic reconnection. Unexpected disconnects may trigger a
configurable reconnect policy that defaults to three attempts with exponential
backoff. Exhausting the policy returns the client to `disconnected`. Printing
cannot begin until the connection is fully discovered, notifications are
subscribed, and the D11H driver has completed its readiness checks.

### 5.4 D11H Driver

`D11hDriver` owns all model-specific behavior:

- Service and characteristic identification
- Packet framing, checksums, sequencing, and parsing
- Device initialization and status queries
- Print setup, raster transfer, print completion, and cleanup commands
- Translation of D11H responses into domain events and typed failures
- Capability reporting based on verified firmware behavior

It communicates only through `BleTransport` and contains no Flutter UI or
platform permission code.

### 5.5 Label Model and Renderer

`LabelDocument` describes a label using physical dimensions, orientation, and
positioned elements:

- Text with font, size, alignment, wrapping, and rotation
- Images with fitting, cropping, thresholding, and rotation
- One-dimensional barcodes with human-readable text options
- QR codes with configurable error correction

Coordinates and sizes use millimeters in the public API and are converted to
printer dots using the verified D11H resolution. Out-of-bounds elements are
rejected by default or clipped when explicitly enabled in render options.

`LabelRenderer` converts a document to a deterministic monochrome raster. A
separate bitmap API accepts a completed image, normalizes its dimensions and
pixel format, and then uses the same print pipeline. Rendering is performed
before the printer enters the active transfer stage so rendering failures
cannot leave a half-started job.

### 5.6 Print Job Queue

The queue serializes all printer commands and allows only one active print job.
Each job includes:

- Rendered raster or bitmap input
- Print density and other verified settings
- Copy count
- Command timeout and retry policy
- Progress and cancellation state

The queue validates readiness, renders the label, starts the D11H session,
transfers MTU-sized packets in order, verifies required responses, waits for a
verified completion response, and restores the printer to an idle state.

## 6. Print Data Flow

```text
LabelDocument or bitmap
    -> validate dimensions and options
    -> render/normalize monochrome raster
    -> create immutable print job
    -> check connection and printer readiness
    -> initialize D11H print session
    -> split and transmit ordered packets
    -> correlate and validate responses
    -> verify printer completion
    -> emit PrintResult
```

`PrintResult.success` is emitted only after the protocol's verified completion
condition is observed. Successfully writing all BLE bytes is not sufficient.

## 7. Error Handling and Recovery

Errors use a typed `NiimbotException` hierarchy with machine-readable codes and
human-readable context. Categories include:

- Bluetooth unavailable or permission denied
- Device not found, connection timeout, or unexpected disconnect
- Service, characteristic, notification, or MTU negotiation failure
- Command timeout, invalid packet, checksum failure, or unexpected response
- Unsupported firmware behavior or label configuration
- Printer conditions such as no paper, open cover, low battery, or overheating,
  where those conditions are verified to be observable on D11H
- Rendering, barcode, QR, and image conversion failures
- Job cancellation

Retries are command-specific and bounded. Idempotent status queries may be
retried. Commands that could duplicate printed output are not automatically
replayed unless experiments prove replay is safe.

If the connection drops during printing, the active label fails and the queue
is paused. The library will not silently continue from an uncertain byte
offset. After reconnection and readiness verification, later queued work may
continue according to the caller's queue policy; the failed job requires an
explicit retry.

Cancellation stops unsent work, attempts verified D11H cleanup when connected,
and reports whether cancellation occurred before or after transfer began.

## 8. Diagnostics

Logging levels are:

- `off`
- `error`
- `info`
- `debug`
- `packet`

Packet logging is opt-in and documented as potentially sensitive and verbose.
Logs include timestamps, job and command correlation identifiers, state
transitions, retry decisions, and sanitized packet metadata. The default logger
must not expose user label content or persistent device identifiers.

## 9. Example Application

The `example` app is a testing and integration reference, not part of the
package's public UI API. It will include:

- Platform permission and Bluetooth readiness guidance
- D11H scan results, device selection, connection, and disconnect controls
- Live connection and printer status
- Label size, orientation, density, and copy settings
- Canvas-based placement of text, image, barcode, and QR elements
- Direct bitmap selection and printing
- Monochrome print preview
- Print progress, cancellation, and result history
- Diagnostic log viewer and export
- Repeat-print and failure-recovery test controls

The example must use only the same public APIs available to package consumers.

## 10. Testing Strategy

### 10.1 Automated Tests

- Packet framing, checksum, sequencing, and parser unit tests
- Captured-response fixtures for valid, malformed, partial, combined, delayed,
  and out-of-order data
- Renderer golden tests for text, images, barcodes, QR codes, rotation,
  thresholding, wrapping, and clipping
- Fake transport tests for connection state transitions, timeouts, packet loss,
  retries, disconnects, reconnection, cancellation, and queue ordering
- Public API tests that ensure transport details do not leak into consumers
- Automated example-app tests for permission-state presentation, editor
  operations, preview generation, and public API integration using fakes

### 10.2 Physical Device Tests

Testing uses a real D11H with both Android and iPhone:

- Initial connect, disconnect, manual reconnect, and automatic reconnect
- 100 repeated prints of the standard test label per recorded configuration
- Multiple copies and multiple queued jobs
- Large and boundary-sized raster transfers
- Disconnect and Bluetooth-disable scenarios during each print phase
- Cancellation before transfer, during transfer, and while awaiting completion
- Low battery and observable printer fault conditions
- Printed output inspection for clipping, orientation, density, image quality,
  text legibility, and barcode/QR readability

Each run records phone model, OS version, D11H firmware information when
available, BLE backend version, package version, label media, test case, and
result.

### 10.3 Release Gate

A release candidate is stable only when:

- Static analysis and all automated tests pass.
- Android and iOS complete the physical-device test matrix.
- The standard repeated-print test succeeds at least 99 times out of 100 on
  each recorded platform configuration.
- No failed or uncertain print is reported as successful.
- Every stable status and command is backed by captured evidence and a
  reproducible test.
- The example app can complete discovery through verified print completion
  using only public package APIs.

## 11. Package and Repository Shape

The current Flutter application template will be converted into a Flutter
package with an embedded example application:

```text
lib/
  niimbot.dart
  src/
    api/
    connection/
    diagnostics/
    model/
    printing/
    protocol/d11h/
    rendering/
    transport/
example/
  lib/
  android/
  ios/
test/
  fixtures/
  golden/
  support/
docs/
  protocol/
  testing/
```

Internal implementation remains under `lib/src`. Only intentionally supported
types are exported from `lib/niimbot.dart`.

## 12. Delivery Scope

Development should proceed in independently verifiable stages:

1. Convert the template into a package and establish public/internal boundaries.
2. Implement and test the BLE transport contract and connection state machine.
3. Record and document the D11H protocol needed for discovery, readiness, and a
   minimal monochrome bitmap print.
4. Implement the D11H driver and reliable print queue.
5. Add the label model and deterministic renderer.
6. Add text, image, barcode, and QR composition.
7. Build the complete example application.
8. Run the physical-device matrix, fix reliability issues, and prepare pub.dev
   documentation and release artifacts.

No stage may treat unverified packet transmission as successful printing.

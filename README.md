# flutter_niimbot

An unofficial Flutter package for building label-printing experiences with
NIIMBOT Bluetooth printers.

> **Current device support:** NIIMBOT D11H only.
>
> Support for other NIIMBOT models is not available yet.

This package is under active development. The label model, renderer, and D11H
application facade are available through the stable public entry point.

## Features

- Define label dimensions in millimeters
- Render text to a monochrome raster at 203 DPI
- Use normal or 90-degree rotated label orientation
- Configure text alignment, position, wrapping, size, and weight
- Work with typed BLE device, connection, service, and failure models
- Scan, connect, and print through the D11H application facade
- Warm-connection printing on iOS (no pre-print GATT refresh)
- Probe-aligned print characteristic discovery for real devices

## Supported printers

| Manufacturer | Model | Status |
| --- | --- | --- |
| NIIMBOT | D11H | Supported |

No other NIIMBOT printer model is currently supported or tested.

## Installation

Add `flutter_niimbot` to your app:

```yaml
dependencies:
  flutter_niimbot: ^0.1.0-dev.9
```

Then fetch the dependency:

```console
flutter pub get
```

## Usage

Import the stable public entry point:

```dart
import 'package:flutter_niimbot/niimbot.dart';
```

Create and render a text label:

```dart
final document = LabelDocument(
  size: LabelSize.d11h12x22,
  orientation: LabelOrientation.rotated90,
  elements: [
    LabelText(
      text: '상품명\n닉네임',
      xMm: 0,
      yMm: 1,
      widthMm: 22,
      heightMm: 10,
      fontSizePt: 15,
      alignment: LabelTextAlignment.start,
      horizontalPosition: LabelHorizontalPosition.center,
      wrap: true,
      bold: true,
    ),
  ],
);

final raster = await const TextLabelRenderer().render(document);
```

Print through the high-level facade:

```dart
final printer = D11hPrinter();

try {
  final devices = await printer.scan();
  if (devices.isEmpty) {
    throw StateError('No BLE printers found.');
  }

  await printer.connect(devices.first.deviceId);
  await printer.printLabel(document);
  // Or render first, then print on the warm connection:
  // await printer.printRenderedLabel(raster);
} finally {
  await printer.dispose();
}
```

### Printing behavior

- `connect()` discovers services, negotiates MTU, subscribes to the print
  characteristic, and settles briefly before the link is used.
- `printLabel()` and `printRenderedLabel()` print on the **current** BLE
  connection. They do not disconnect and reconnect before each label.
- `printRenderedLabel()` matches the working `tool/d11h_probe` path: render
  first, then call `printRaster` with a 30 ms inter-write delay.
- All printer operations are serialized through an internal queue.
- `scan()` disconnects an active printer before discovery and ends with an
  explicit `stopScan()` so iOS scan results are not lost to timeout cleanup.

### Media information

Media information is opt-in. The library does not read media automatically
before printing, and it does not include built-in total-label counts.
Applications provide their own roll profile when they want remaining-label
estimates:

```dart
final info = await printer.readMediaInfo(
  profile: D11hMediaRollProfile(
    totalLabels: 260,
    counterAtBaseline: 256,
    remainingLabelsAtBaseline: 260,
    name: '12x22 roll',
  ),
);

print(info.state);
print(info.usageCounter);
print(info.remainingEstimate?.remainingLabels);
print(info.remainingEstimate?.remainingPercent);
```

`counterAtBaseline` is the opaque RFID counter observed at the moment tracking
starts. It is not the label count. `remainingLabelsAtBaseline` is the label
count you want the estimate to start from. For a new 195-label 12x30 roll, use
`remainingLabelsAtBaseline: 195`; for a used 260-label roll with about 60
labels left, use `remainingLabelsAtBaseline: 60`.

To auto-detect media after connecting, call `readMediaInfo()` immediately after
`connect()` in the app layer. The probe app does this so iOS testing shows the
loaded roll, counter, and remaining percentage as soon as the printer connects.

Without a profile, the library reports loaded/not-loaded state, candidate
identifiers, raw frames, and the observed counter, but remaining labels are
unknown.

### Print characteristic discovery

`findD11hPrintCharacteristic()` prefers FFF0/FFF1, then falls back to any
characteristic that supports notify and `writeWithoutResponse`, matching the
probe app's discovery logic on iOS.

## Bluetooth setup

Applications using BLE functionality must configure the Android and iOS
Bluetooth permissions required by `flutter_reactive_ble`. Permission prompts
remain the responsibility of the application.

On iOS, avoid requesting Bluetooth permission through `permission_handler`
before scanning; let Core Bluetooth handle the system prompt.

The repository includes an internal D11H probe application under
`tool/d11h_probe` for protocol research and diagnostics.

## API status

Use `package:flutter_niimbot/niimbot.dart` for the public API.

`D11hPrinter`, D11H characteristic discovery, label models, rendering, and BLE
transport types are exported by the stable entry point.

`package:flutter_niimbot/niimbot_research.dart` exposes low-level probe and
protocol research APIs. These APIs may change without notice and are not
covered by semantic-versioning guarantees.

## Limitations

- Only NIIMBOT D11H has been characterized and tested.
- Text labels are supported; image, barcode, and QR-code elements are not yet
  part of the public renderer.
- A successful BLE write alone does not guarantee that a physical label was
  printed.

## Disclaimer

This is an independent, unofficial project. It is not affiliated with,
endorsed by, or sponsored by NIIMBOT.

## License

See [LICENSE](LICENSE).

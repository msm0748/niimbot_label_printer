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
- Scan, connect, reconnect, and print through the D11H application facade

## Supported printers

| Manufacturer | Model | Status |
| --- | --- | --- |
| NIIMBOT | D11H | Supported |

No other NIIMBOT printer model is currently supported or tested.

## Installation

Add `flutter_niimbot` to your app:

```yaml
dependencies:
  flutter_niimbot: ^0.1.0-dev.2
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
  size: LabelSize.d11h12x30,
  elements: [
    LabelText(
      text: 'Hello, NIIMBOT!',
      xMm: 1,
      yMm: 1,
      widthMm: 28,
      heightMm: 10,
      fontSizePt: 14,
      alignment: LabelTextAlignment.center,
      horizontalPosition: LabelHorizontalPosition.center,
      bold: true,
    ),
  ],
);

final raster = await const TextLabelRenderer().render(document);

print('${raster.width} x ${raster.height}');
```

Print the document through the high-level facade:

```dart
final printer = D11hPrinter();

try {
  final devices = await printer.scan();
  if (devices.isEmpty) {
    throw StateError('No BLE printers found.');
  }

  await printer.connect(devices.first.deviceId);
  await printer.printLabel(document);
  await printer.disconnect();
} finally {
  await printer.dispose();
}
```

`printLabel()` serializes concurrent requests, reconnects to the last selected
device when needed, renders the document, discovers the D11H FFF0/FFF1
characteristic, and runs the raster print protocol.

## Bluetooth setup

Applications using BLE functionality must configure the Android and iOS
Bluetooth permissions required by `flutter_reactive_ble`. Permission prompts
remain the responsibility of the application.

The repository also includes an internal D11H probe application under
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

# flutter_niimbot

An unofficial Flutter package for building label-printing experiences with
NIIMBOT Bluetooth printers.

> **Current device support:** NIIMBOT D11H only.
>
> Support for other NIIMBOT models is not available yet.

This package is under active development. The label model and renderer are
available through the public API, while the D11H printing workflow is still
experimental.

## Features

- Define label dimensions in millimeters
- Render text to a monochrome raster at 203 DPI
- Use normal or 90-degree rotated label orientation
- Configure text alignment, position, wrapping, size, and weight
- Work with typed BLE device, connection, service, and failure models
- Experiment with D11H BLE printing through the included probe application

## Supported printers

| Manufacturer | Model | Status |
| --- | --- | --- |
| NIIMBOT | D11H | Experimental |

No other NIIMBOT printer model is currently supported or tested.

## Installation

Add `flutter_niimbot` to your app:

```yaml
dependencies:
  flutter_niimbot: ^0.1.0-dev.1
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

The resulting `MonochromeRaster` contains one-bit pixel data suitable for the
D11H raster-printing pipeline.

## Bluetooth setup

Applications using BLE functionality must configure the Android and iOS
Bluetooth permissions required by `flutter_reactive_ble`. Permission prompts
remain the responsibility of the application.

The repository includes an internal D11H probe application under
`tool/d11h_probe`. It demonstrates scanning, connecting, rendering, and
experimental printing with a physical D11H.

## API status

Use `package:flutter_niimbot/niimbot.dart` for the public API.

`package:flutter_niimbot/niimbot_research.dart` exposes experimental transport
and D11H research APIs. These APIs may change without notice and are not
covered by semantic-versioning guarantees.

## Limitations

- Only NIIMBOT D11H has been characterized and tested.
- Printing APIs are experimental and may change.
- Text labels are supported; image, barcode, and QR-code elements are not yet
  part of the public renderer.
- A successful BLE write alone does not guarantee that a physical label was
  printed.

## Disclaimer

This is an independent, unofficial project. It is not affiliated with,
endorsed by, or sponsored by NIIMBOT.

## License

See [LICENSE](LICENSE).

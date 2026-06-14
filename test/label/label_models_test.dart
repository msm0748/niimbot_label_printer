import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_niimbot/niimbot.dart';

void main() {
  test('D11H presets expose 12x22 and 12x30 millimeter media', () {
    expect(LabelSize.d11h12x22.widthMm, 22);
    expect(LabelSize.d11h12x22.heightMm, 12);
    expect(LabelSize.d11h12x30.widthMm, 30);
    expect(LabelSize.d11h12x30.heightMm, 12);
  });

  test('document converts physical size to 203 DPI dot dimensions', () {
    final normal = LabelDocument(
      size: LabelSize.d11h12x22,
      elements: const <LabelElement>[],
    );
    final rotated = LabelDocument(
      size: LabelSize.d11h12x22,
      orientation: LabelOrientation.rotated90,
      elements: const <LabelElement>[],
    );

    expect(normal.widthDots, 176);
    expect(normal.heightDots, 96);
    expect(rotated.widthDots, 96);
    expect(rotated.heightDots, 176);
  });

  test('text elements retain layout choices', () {
    final text = LabelText(
      text: 'Hello',
      xMm: 1,
      yMm: 1,
      widthMm: 20,
      heightMm: 10,
      fontSizePt: 18,
      alignment: LabelTextAlignment.center,
      wrap: true,
      bold: true,
    );

    expect(text.text, 'Hello');
    expect(text.alignment, LabelTextAlignment.center);
    expect(text.horizontalPosition, LabelHorizontalPosition.center);
    expect(text.wrap, isTrue);
    expect(text.bold, isTrue);

    final right = LabelText(
      text: 'Right',
      xMm: 1,
      yMm: 1,
      widthMm: 20,
      heightMm: 10,
      horizontalPosition: LabelHorizontalPosition.right,
    );

    expect(right.horizontalPosition, LabelHorizontalPosition.right);
  });

  test('rejects invalid label and text dimensions', () {
    expect(() => LabelSize(widthMm: 0, heightMm: 12), throwsArgumentError);
    expect(
      () => LabelText(text: 'x', xMm: 0, yMm: 0, widthMm: -1, heightMm: 1),
      throwsArgumentError,
    );
  });

  test('monochrome raster defensively copies pixels', () {
    final source = Uint8List.fromList(<int>[0, 1, 1, 0]);
    final raster = MonochromeRaster(width: 2, height: 2, pixels: source);
    source[0] = 1;

    expect(raster.pixels, <int>[0, 1, 1, 0]);
    expect(() => raster.pixels[0] = 1, throwsUnsupportedError);
    expect(raster.isBlack(1, 0), isTrue);
  });
}

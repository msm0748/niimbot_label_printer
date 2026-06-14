import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_models.dart';
import 'monochrome_raster.dart';

final class TextLabelRenderer {
  const TextLabelRenderer({this.blackThreshold = 128});

  static const double _dotsPerPoint = 203 / 72;

  final int blackThreshold;

  Future<MonochromeRaster> render(LabelDocument document) async {
    final normalWidth =
        (document.size.widthMm * LabelDocument.dotsPerMillimeter).round();
    final normalHeight =
        (document.size.heightMm * LabelDocument.dotsPerMillimeter).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, normalWidth.toDouble(), normalHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    for (final element in document.elements) {
      if (element case final LabelText text) {
        _paintText(canvas, text);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(normalWidth, normalHeight);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw StateError('Flutter could not read rendered label pixels.');
    }

    final normalPixels = _toMonochrome(bytes, normalWidth, normalHeight);
    if (document.orientation == LabelOrientation.normal) {
      return MonochromeRaster(
        width: normalWidth,
        height: normalHeight,
        pixels: normalPixels,
      );
    }
    return _rotateClockwise(normalPixels, normalWidth, normalHeight);
  }

  void _paintText(ui.Canvas canvas, LabelText text) {
    final left = text.xMm * LabelDocument.dotsPerMillimeter;
    final top = text.yMm * LabelDocument.dotsPerMillimeter;
    final width = text.widthMm * LabelDocument.dotsPerMillimeter;
    final height = text.heightMm * LabelDocument.dotsPerMillimeter;
    final bounds = ui.Rect.fromLTWH(left, top, width, height);
    final painter = TextPainter(
      text: TextSpan(
        text: text.text,
        style: TextStyle(
          color: const ui.Color(0xFF000000),
          fontSize: text.fontSizePt * _dotsPerPoint,
          fontWeight: text.bold ? FontWeight.bold : FontWeight.normal,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: switch (text.alignment) {
        LabelTextAlignment.start => TextAlign.start,
        LabelTextAlignment.center => TextAlign.center,
        LabelTextAlignment.end => TextAlign.end,
      },
      maxLines: text.wrap ? null : 1,
      ellipsis: text.wrap ? null : '...',
    )..layout(maxWidth: width);

    canvas.save();
    canvas.clipRect(bounds);
    final y = top + math.max(0, (height - painter.height) / 2);
    painter.paint(canvas, ui.Offset(left, y));
    canvas.restore();
    painter.dispose();
  }

  Uint8List _toMonochrome(ByteData bytes, int width, int height) {
    final rgba = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final pixels = Uint8List(width * height);
    for (var index = 0; index < pixels.length; index++) {
      final offset = index * 4;
      final luminance =
          (rgba[offset] * 299 +
              rgba[offset + 1] * 587 +
              rgba[offset + 2] * 114) ~/
          1000;
      pixels[index] = rgba[offset + 3] > 0 && luminance < blackThreshold
          ? 1
          : 0;
    }
    return pixels;
  }

  MonochromeRaster _rotateClockwise(Uint8List source, int width, int height) {
    final rotated = Uint8List(source.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final rotatedX = height - 1 - y;
        final rotatedY = x;
        rotated[rotatedY * height + rotatedX] = source[y * width + x];
      }
    }
    return MonochromeRaster(width: height, height: width, pixels: rotated);
  }
}

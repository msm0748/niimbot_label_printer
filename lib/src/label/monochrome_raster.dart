import 'dart:typed_data';

final class MonochromeRaster {
  MonochromeRaster({
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : pixels = Uint8List.fromList(pixels).asUnmodifiableView() {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'Must be positive.');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'Must be positive.');
    }
    if (pixels.length != width * height) {
      throw ArgumentError.value(
        pixels.length,
        'pixels',
        'Must contain exactly width * height pixels.',
      );
    }
    if (pixels.any((pixel) => pixel != 0 && pixel != 1)) {
      throw ArgumentError.value(
        pixels,
        'pixels',
        'Pixels must contain only zero or one.',
      );
    }
  }

  final int width;
  final int height;
  final Uint8List pixels;

  bool isBlack(int x, int y) {
    if (x < 0 || x >= width) {
      throw RangeError.range(x, 0, width - 1, 'x');
    }
    if (y < 0 || y >= height) {
      throw RangeError.range(y, 0, height - 1, 'y');
    }
    return pixels[y * width + x] == 1;
  }
}

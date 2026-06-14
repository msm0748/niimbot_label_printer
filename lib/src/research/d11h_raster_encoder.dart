import 'dart:typed_data';

import '../label/monochrome_raster.dart';
import 'captured_test_print.dart';

List<Uint8List> encodeD11hRasterRows(MonochromeRaster raster) {
  if (raster.width > 1992) {
    throw ArgumentError.value(
      raster.width,
      'raster.width',
      'D11H row payloads support at most 1992 dots.',
    );
  }
  if (raster.height > 0x10000) {
    throw ArgumentError.value(
      raster.height,
      'raster.height',
      'D11H row indexes support at most 65536 rows.',
    );
  }

  final rowByteCount = (raster.width + 7) ~/ 8;
  return List<Uint8List>.unmodifiable(<Uint8List>[
    for (var y = 0; y < raster.height; y++)
      buildD11hCommand(0x85, <int>[
        y >> 8,
        y & 0xFF,
        0,
        0,
        0,
        1,
        ..._packRow(raster, y, rowByteCount),
      ]),
  ]);
}

Uint8List _packRow(MonochromeRaster raster, int y, int rowByteCount) {
  final bytes = Uint8List(rowByteCount);
  for (var x = 0; x < raster.width; x++) {
    if (raster.isBlack(x, y)) {
      bytes[x ~/ 8] |= 0x80 >> (x % 8);
    }
  }
  return bytes;
}

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
  final rows = <Uint8List>[];
  var y = 0;
  while (y < raster.height) {
    final packed = _packRow(raster, y, rowByteCount);
    var runLength = 1;
    while (y + runLength < raster.height && runLength < 200) {
      final next = _packRow(raster, y + runLength, rowByteCount);
      if (!_rowsEqual(packed, next)) {
        break;
      }
      runLength++;
    }

    final blackPixelCount = _blackPixelCount(packed);
    rows.add(
      blackPixelCount == 0
          ? buildD11hCommand(0x84, <int>[y >> 8, y & 0xFF, runLength])
          : buildD11hCommand(0x85, <int>[
              y >> 8,
              y & 0xFF,
              0,
              blackPixelCount & 0xFF,
              blackPixelCount >> 8,
              runLength,
              ...packed,
            ]),
    );
    y += runLength;
  }
  return List<Uint8List>.unmodifiable(rows);
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

bool _rowsEqual(Uint8List first, Uint8List second) {
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

int _blackPixelCount(Uint8List bytes) {
  var count = 0;
  for (final byte in bytes) {
    var value = byte;
    while (value != 0) {
      count += value & 1;
      value >>= 1;
    }
  }
  return count;
}

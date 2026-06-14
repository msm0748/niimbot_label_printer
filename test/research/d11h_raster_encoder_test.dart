import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot.dart';
import 'package:niimbot_lib/niimbot_research.dart';

void main() {
  test('encodes bitmap rows with black-pixel counts', () {
    final raster = MonochromeRaster(
      width: 10,
      height: 2,
      pixels: Uint8List.fromList(<int>[
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        1,
        1,
        0,
        0,
        1,
      ]),
    );

    final rows = encodeD11hRasterRows(raster);

    expect(rows, hasLength(2));
    expect(
      splitD11hFrames(rows[0]).single,
      buildD11hCommand(0x85, <int>[0, 0, 0, 4, 0, 1, 0xA1, 0x80]),
    );
    expect(
      splitD11hFrames(rows[1]).single,
      buildD11hCommand(0x85, <int>[0, 1, 0, 6, 0, 1, 0x5E, 0x40]),
    );
  });

  test('run-length encodes identical blank and bitmap rows', () {
    final raster = MonochromeRaster(
      width: 8,
      height: 5,
      pixels: Uint8List.fromList(<int>[
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
      ]),
    );

    final rows = encodeD11hRasterRows(raster);

    expect(rows, hasLength(2));
    expect(
      splitD11hFrames(rows[0]).single,
      buildD11hCommand(0x84, <int>[0, 0, 2]),
    );
    expect(
      splitD11hFrames(rows[1]).single,
      buildD11hCommand(0x85, <int>[0, 2, 0, 2, 0, 3, 0x81]),
    );
  });

  test('encodes 240-dot rows within one-byte frame length', () {
    final raster = MonochromeRaster(
      width: 240,
      height: 1,
      pixels: Uint8List(240),
    );

    final row = encodeD11hRasterRows(raster).single;

    expect(row, buildD11hCommand(0x84, <int>[0, 0, 1]));
  });
}

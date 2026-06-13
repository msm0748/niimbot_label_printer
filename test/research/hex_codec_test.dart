import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimbot_lib/niimbot_research.dart';

void main() {
  group('parseHexBytes', () {
    test('parses whitespace-separated hexadecimal bytes exactly', () {
      final bytes = parseHexBytes('55 01 aa');

      expect(bytes, isA<Uint8List>());
      expect(bytes, <int>[0x55, 0x01, 0xaa]);
    });

    test('parses compact hexadecimal bytes with mixed case', () {
      expect(parseHexBytes('5501aA'), <int>[0x55, 0x01, 0xaa]);
    });

    test('removes mixed whitespace', () {
      expect(parseHexBytes('\t55\n 01\r\nAa '), <int>[0x55, 0x01, 0xaa]);
    });

    test('returns an empty Uint8List for whitespace-only input', () {
      final bytes = parseHexBytes(' \t\n');

      expect(bytes, isA<Uint8List>());
      expect(bytes, isEmpty);
    });

    test('rejects odd-length input with a clear message', () {
      expect(
        () => parseHexBytes('550'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('even number'),
          ),
        ),
      );
    });

    test('rejects non-hexadecimal input with a clear message', () {
      expect(
        () => parseHexBytes('55 zZ'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('non-hexadecimal'),
          ),
        ),
      );
    });
  });

  group('formatHexBytes', () {
    test('formats bytes as lowercase two-digit spaced hex', () {
      expect(formatHexBytes(<int>[0x00, 0x05, 0xab, 0xff]), '00 05 ab ff');
    });

    test('formats an empty iterable as an empty string', () {
      expect(formatHexBytes(const <int>[]), isEmpty);
    });

    test('rejects a negative byte with useful context', () {
      expect(
        () => formatHexBytes(<int>[0x01, -1]),
        throwsA(
          isA<RangeError>()
              .having((error) => error.invalidValue, 'invalidValue', -1)
              .having((error) => error.name, 'name', 'bytes[1]'),
        ),
      );
    });

    test('rejects a byte greater than 255 with useful context', () {
      expect(
        () => formatHexBytes(<int>[256]),
        throwsA(
          isA<RangeError>()
              .having((error) => error.invalidValue, 'invalidValue', 256)
              .having((error) => error.name, 'name', 'bytes[0]'),
        ),
      );
    });
  });
}

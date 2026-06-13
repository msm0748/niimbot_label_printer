import 'dart:typed_data';

Uint8List parseHexBytes(String input) {
  final normalized = input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (normalized.isEmpty) {
    return Uint8List(0);
  }
  if (normalized.length.isOdd) {
    throw FormatException(
      'Hex input must contain an even number of digits; '
      'got ${normalized.length}.',
    );
  }

  final invalidMatch = RegExp(r'[^0-9a-f]').firstMatch(normalized);
  if (invalidMatch != null) {
    throw FormatException(
      'Hex input contains a non-hexadecimal character at digit '
      '${invalidMatch.start}: "${invalidMatch.group(0)}".',
    );
  }

  return Uint8List.fromList(<int>[
    for (var index = 0; index < normalized.length; index += 2)
      int.parse(normalized.substring(index, index + 2), radix: 16),
  ]);
}

String formatHexBytes(Iterable<int> bytes) {
  final formatted = <String>[];
  var index = 0;

  for (final byte in bytes) {
    if (byte < 0 || byte > 0xff) {
      throw RangeError.range(
        byte,
        0,
        0xff,
        'bytes[$index]',
        'Byte value must be in the range 0..255',
      );
    }
    formatted.add(byte.toRadixString(16).padLeft(2, '0'));
    index++;
  }

  return formatted.join(' ');
}

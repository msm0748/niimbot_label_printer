import 'dart:typed_data';

import 'hex_codec.dart';

final List<Uint8List> _capturedTestPrintWritesAfterSession = <Uint8List>[
  parseHexBytes('55 55 A3 01 01 A3 AA AA'),
  parseHexBytes(
    '55 55 84 03 00 00 7C FB AA AA '
    '55 55 83 0A 00 7C 00 02 00 0B 00 4C 00 4B FB AA AA '
    '55 55 85 18 00 87 00 0C 00 01 00 00 00 00 00 00 00 00 '
    '7F F8 00 00 00 00 00 00 00 00 90 AA AA '
    '55 55 85 18 00 88 00 0A 00 01 00 00 00 00 00 00 00 00 '
    '3F F0 00 00 00 00 00 00 00 00 D1 AA AA '
    '55 55 84 03 00 89 3F 31 AA AA',
  ),
  parseHexBytes('55 55 A3 01 01 A3 AA AA'),
  parseHexBytes('55 55 84 03 00 C8 3B 74 AA AA'),
  parseHexBytes('55 55 E3 01 01 E3 AA AA'),
];

final List<Uint8List> _capturedTestPrintSetupWrites = <Uint8List>[
  parseHexBytes('55 55 2C 01 01 2C AA AA'),
  parseHexBytes('55 55 23 01 01 23 AA AA'),
  parseHexBytes('55 55 21 01 03 23 AA AA'),
  parseHexBytes('55 55 01 09 00 01 00 00 00 00 00 01 00 08 AA AA'),
];

List<Uint8List> capturedTestPrintWrites({required String sessionId}) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(sessionId)) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'Must contain exactly 32 lowercase hexadecimal characters.',
    );
  }

  return List<Uint8List>.unmodifiable(
    <Uint8List>[
      ..._capturedTestPrintSetupWrites,
      _buildD11hFrame(0x13, <int>[
        0x01,
        0x03,
        0x00,
        0x8D,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        ...sessionId.codeUnits,
      ]),
      ..._capturedTestPrintWritesAfterSession,
    ].map((write) => Uint8List.fromList(write).asUnmodifiableView()),
  );
}

Uint8List buildD11hCommand(int command, List<int> payload) =>
    _buildD11hFrame(command, payload);

Uint8List _buildD11hFrame(int command, List<int> payload) {
  if (payload.length > 0xFF) {
    throw ArgumentError.value(
      payload.length,
      'payload',
      'Payload is too long.',
    );
  }
  var checksum = command ^ payload.length;
  for (final byte in payload) {
    checksum ^= byte;
  }
  return Uint8List.fromList(<int>[
    0x55,
    0x55,
    command,
    payload.length,
    ...payload,
    checksum,
    0xAA,
    0xAA,
  ]).asUnmodifiableView();
}

List<Uint8List> splitD11hFrames(Uint8List bytes) {
  final frames = <Uint8List>[];
  var offset = 0;

  while (offset < bytes.length) {
    if (offset + 4 > bytes.length ||
        bytes[offset] != 0x55 ||
        bytes[offset + 1] != 0x55) {
      throw const FormatException('Invalid D11H frame prefix.');
    }

    final frameLength = bytes[offset + 3] + 7;
    final end = offset + frameLength;
    if (end > bytes.length) {
      throw const FormatException('Truncated D11H frame.');
    }

    final frame = Uint8List.fromList(bytes.sublist(offset, end));
    if (frame[frame.length - 2] != 0xAA || frame[frame.length - 1] != 0xAA) {
      throw const FormatException('Invalid D11H frame suffix.');
    }
    frames.add(frame.asUnmodifiableView());
    offset = end;
  }

  return List<Uint8List>.unmodifiable(frames);
}

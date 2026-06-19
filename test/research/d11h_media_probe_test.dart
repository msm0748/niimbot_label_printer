import 'dart:typed_data';

import 'package:flutter_niimbot/niimbot_research.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('D11hProtocolFrame exposes immutable payload and lowercase hex', () {
    final payload = Uint8List.fromList(<int>[0x01, 0xA0, 0xFF]);
    final frame = D11hProtocolFrame(command: 0x1B, payload: payload);

    payload[0] = 0x99;

    expect(frame.command, 0x1B);
    expect(frame.payload, <int>[0x01, 0xA0, 0xFF]);
    expect(frame.payloadHex, '01 a0 ff');
    expect(() => frame.payload[0] = 0x00, throwsUnsupportedError);
  });

  test(
    'D11hMediaProbeResult stores information and optional status frames',
    () {
      final createdAt = DateTime.utc(2026, 6, 16, 12);
      final information = D11hProtocolFrame(
        command: 0x1B,
        payload: Uint8List.fromList(<int>[0x10]),
      );
      final status = D11hProtocolFrame(
        command: 0xB3,
        payload: Uint8List.fromList(<int>[0x00, 0x01]),
      );

      final result = D11hMediaProbeResult(
        createdAt: createdAt,
        informationResponse: information,
        statusResponse: status,
      );

      expect(result.createdAt, createdAt);
      expect(result.informationResponse, same(information));
      expect(result.statusResponse, same(status));
    },
  );
}

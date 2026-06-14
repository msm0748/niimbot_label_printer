import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_niimbot/niimbot_research.dart';

void main() {
  test('captured print writes contain valid D11H frames in observed order', () {
    final writes = capturedTestPrintWrites(
      sessionId: '0123456789abcdef0123456789abcdef',
    );

    expect(
      writes.map((write) => splitD11hFrames(write).map((frame) => frame[2])),
      <Iterable<int>>[
        <int>[0x2C],
        <int>[0x23],
        <int>[0x21],
        <int>[0x01],
        <int>[0x13],
        <int>[0xA3],
        <int>[0x84, 0x83, 0x85, 0x85, 0x84],
        <int>[0xA3],
        <int>[0x84],
        <int>[0xE3],
      ],
    );
    expect(
      String.fromCharCodes(splitD11hFrames(writes[4]).single.sublist(17, 49)),
      '0123456789abcdef0123456789abcdef',
    );

    for (final write in writes) {
      for (final frame in splitD11hFrames(write)) {
        expect(frame.take(2), <int>[0x55, 0x55]);
        expect(frame.skip(frame.length - 2), <int>[0xAA, 0xAA]);
        expect(frame.length, frame[3] + 7);

        var checksum = 0;
        for (final byte in frame.sublist(2, frame.length - 3)) {
          checksum ^= byte;
        }
        expect(frame[frame.length - 3], checksum);
      }
    }
  });
}

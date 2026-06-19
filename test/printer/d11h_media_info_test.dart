import 'dart:typed_data';

import 'package:flutter_niimbot/niimbot.dart';
import 'package:flutter_niimbot/niimbot_research.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses not loaded media response', () {
    final info = D11hMediaInfo.fromProbeResult(
      D11hMediaProbeResult(
        createdAt: DateTime.utc(2026, 6, 19),
        informationResponse: D11hProtocolFrame(
          command: 0x1B,
          payload: Uint8List.fromList(<int>[0x00]),
        ),
        statusResponse: D11hProtocolFrame(
          command: 0xB3,
          payload: Uint8List.fromList(<int>[0, 0, 0, 0, 0x15, 0x17, 2, 0]),
        ),
      ),
    );

    expect(info.state, D11hMediaState.notLoaded);
    expect(info.candidateSerial, isNull);
    expect(info.candidateCode, isNull);
    expect(info.usageCounter, isNull);
    expect(info.remainingEstimate, isNull);
  });

  test('parses 12x22 loaded response and remaining percentage', () {
    final payload = parseHexBytes(
      '88 1d 35 d3 07 97 00 00 '
      '0d 36 39 37 32 38 34 32 37 34 37 35 34 39 '
      '10 50 43 30 47 34 32 38 33 33 30 30 30 35 34 36 34 '
      '01 38 00 01 01',
    );

    final info = D11hMediaInfo.fromProbeResult(
      D11hMediaProbeResult(
        createdAt: DateTime.utc(2026, 6, 19),
        informationResponse: D11hProtocolFrame(command: 0x1B, payload: payload),
        statusResponse: null,
      ),
      profile: D11hMediaRollProfile.fromTotalLabels(
        totalLabels: 260,
        name: '12x22',
      ),
    );

    expect(info.state, D11hMediaState.loaded);
    expect(info.candidateSerial, '6972842747549');
    expect(info.candidateCode, 'PC0G428330005464');
    expect(info.usageCounter, 257);
    expect(info.remainingEstimate?.usedLabels, 1);
    expect(info.remainingEstimate?.remainingLabels, 259);
    expect(info.remainingEstimate?.remainingPercent, closeTo(99.615, 0.001));
    expect(info.remainingEstimate?.isOutOfRange, isFalse);
  });

  test('estimates remaining labels from total and observed counter only', () {
    final estimate = D11hRemainingEstimate.fromCounter(
      currentCounter: 456,
      profile: D11hMediaRollProfile.fromTotalLabels(totalLabels: 260),
    );

    expect(estimate.usedLabels, 200);
    expect(estimate.remainingLabels, 60);
    expect(estimate.remainingPercent, closeTo(23.076, 0.001));
    expect(estimate.isOutOfRange, isFalse);
  });

  test('parses 12x30 loaded response with caller profile', () {
    final payload = parseHexBytes(
      '88 1d 2c 87 98 1a 10 80 '
      '09 30 39 31 32 32 35 31 37 39 '
      '10 50 4a 30 49 33 31 31 37 31 31 30 30 30 35 35 31 '
      '00 ea 00 09 01',
    );

    final info = D11hMediaInfo.fromProbeResult(
      D11hMediaProbeResult(
        createdAt: DateTime.utc(2026, 6, 19),
        informationResponse: D11hProtocolFrame(command: 0x1B, payload: payload),
        statusResponse: null,
      ),
      profile: D11hMediaRollProfile(
        totalLabels: 195,
        counterAtBaseline: 259,
        remainingLabelsAtBaseline: 195,
        name: '12x30',
      ),
    );

    expect(info.candidateSerial, '091225179');
    expect(info.candidateCode, 'PJ0I311711000551');
    expect(info.usageCounter, 265);
    expect(info.remainingEstimate?.remainingLabels, 189);
    expect(info.remainingEstimate?.remainingPercent, closeTo(96.923, 0.001));
  });

  test('remaining estimate supports a used-roll baseline', () {
    final estimate = D11hRemainingEstimate.fromCounter(
      currentCounter: 458,
      profile: D11hMediaRollProfile(
        totalLabels: 260,
        counterAtBaseline: 456,
        remainingLabelsAtBaseline: 60,
      ),
    );

    expect(estimate.usedLabels, 202);
    expect(estimate.remainingLabels, 58);
    expect(estimate.remainingPercent, closeTo(22.307, 0.001));
    expect(estimate.isOutOfRange, isFalse);
  });

  test('remaining estimate clamps impossible profile data', () {
    final estimate = D11hRemainingEstimate.fromCounter(
      currentCounter: 300,
      profile: D11hMediaRollProfile(
        totalLabels: 10,
        counterAtBaseline: 100,
        remainingLabelsAtBaseline: 10,
      ),
    );

    expect(estimate.usedLabels, 10);
    expect(estimate.remainingLabels, 0);
    expect(estimate.remainingPercent, 0);
    expect(estimate.isOutOfRange, isTrue);
  });
}

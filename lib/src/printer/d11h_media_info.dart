import '../research/d11h_media_probe.dart';

enum D11hMediaState { loaded, notLoaded, unknown }

final class D11hMediaRollProfile {
  D11hMediaRollProfile._({
    required this.totalLabels,
    required this.counterAtBaseline,
    required this.remainingLabelsAtBaseline,
    this.name,
  });

  factory D11hMediaRollProfile({
    required int totalLabels,
    required int counterAtBaseline,
    required int remainingLabelsAtBaseline,
    String? name,
  }) {
    if (totalLabels <= 0) {
      throw ArgumentError.value(
        totalLabels,
        'totalLabels',
        'Must be positive.',
      );
    }
    if (counterAtBaseline < 0) {
      throw ArgumentError.value(
        counterAtBaseline,
        'counterAtBaseline',
        'Must be non-negative.',
      );
    }
    if (remainingLabelsAtBaseline < 0 ||
        remainingLabelsAtBaseline > totalLabels) {
      throw ArgumentError.value(
        remainingLabelsAtBaseline,
        'remainingLabelsAtBaseline',
        'Must be between 0 and totalLabels.',
      );
    }
    return D11hMediaRollProfile._(
      totalLabels: totalLabels,
      counterAtBaseline: counterAtBaseline,
      remainingLabelsAtBaseline: remainingLabelsAtBaseline,
      name: name,
    );
  }

  factory D11hMediaRollProfile.fromTotalLabels({
    required int totalLabels,
    int fullRollCounter = 256,
    String? name,
  }) {
    return D11hMediaRollProfile(
      totalLabels: totalLabels,
      counterAtBaseline: fullRollCounter,
      remainingLabelsAtBaseline: totalLabels,
      name: name,
    );
  }

  final int totalLabels;
  final int counterAtBaseline;
  final int remainingLabelsAtBaseline;
  final String? name;
}

final class D11hRemainingEstimate {
  const D11hRemainingEstimate._({
    required this.totalLabels,
    required this.usedLabels,
    required this.remainingLabels,
    required this.remainingRatio,
    required this.remainingPercent,
    required this.isOutOfRange,
  });

  factory D11hRemainingEstimate.fromCounter({
    required int currentCounter,
    required D11hMediaRollProfile profile,
  }) {
    final rawUsedSinceBaseline = currentCounter - profile.counterAtBaseline;
    final rawRemaining =
        profile.remainingLabelsAtBaseline - rawUsedSinceBaseline;
    final isOutOfRange =
        rawUsedSinceBaseline < 0 ||
        rawRemaining < 0 ||
        rawRemaining > profile.totalLabels;
    final remaining = rawRemaining.clamp(0, profile.totalLabels);
    final used = profile.totalLabels - remaining;
    final ratio = remaining / profile.totalLabels;
    return D11hRemainingEstimate._(
      totalLabels: profile.totalLabels,
      usedLabels: used,
      remainingLabels: remaining,
      remainingRatio: ratio,
      remainingPercent: ratio * 100,
      isOutOfRange: isOutOfRange,
    );
  }

  final int totalLabels;
  final int usedLabels;
  final int remainingLabels;
  final double remainingRatio;
  final double remainingPercent;
  final bool isOutOfRange;
}

final class D11hMediaInfo {
  const D11hMediaInfo._({
    required this.state,
    required this.createdAt,
    required this.candidateSerial,
    required this.candidateCode,
    required this.usageCounter,
    required this.remainingEstimate,
    required this.informationResponse,
    required this.statusResponse,
  });

  factory D11hMediaInfo.fromProbeResult(
    D11hMediaProbeResult result, {
    D11hMediaRollProfile? profile,
  }) {
    final payload = result.informationResponse.payload;
    if (payload.length == 1 && payload.single == 0) {
      return D11hMediaInfo._(
        state: D11hMediaState.notLoaded,
        createdAt: result.createdAt,
        candidateSerial: null,
        candidateCode: null,
        usageCounter: null,
        remainingEstimate: null,
        informationResponse: result.informationResponse,
        statusResponse: result.statusResponse,
      );
    }

    if (payload.length < 2) {
      return D11hMediaInfo._(
        state: D11hMediaState.unknown,
        createdAt: result.createdAt,
        candidateSerial: null,
        candidateCode: null,
        usageCounter: null,
        remainingEstimate: null,
        informationResponse: result.informationResponse,
        statusResponse: result.statusResponse,
      );
    }

    final strings = _candidateAsciiStrings(payload);
    final counter = payload[payload.length - 2] | (payload.last << 8);
    return D11hMediaInfo._(
      state: D11hMediaState.loaded,
      createdAt: result.createdAt,
      candidateSerial: strings.isNotEmpty ? strings[0] : null,
      candidateCode: strings.length > 1 ? strings[1] : null,
      usageCounter: counter,
      remainingEstimate: profile == null
          ? null
          : D11hRemainingEstimate.fromCounter(
              currentCounter: counter,
              profile: profile,
            ),
      informationResponse: result.informationResponse,
      statusResponse: result.statusResponse,
    );
  }

  final D11hMediaState state;
  final DateTime createdAt;
  final String? candidateSerial;
  final String? candidateCode;
  final int? usageCounter;
  final D11hRemainingEstimate? remainingEstimate;
  final D11hProtocolFrame informationResponse;
  final D11hProtocolFrame? statusResponse;
}

List<String> _candidateAsciiStrings(List<int> payload) {
  final values = <String>[];
  for (var index = 0; index < payload.length; index++) {
    final length = payload[index];
    final start = index + 1;
    final end = start + length;
    if (length < 4 || end > payload.length) {
      continue;
    }
    final bytes = payload.sublist(start, end);
    final printable = bytes.every((byte) => byte >= 0x20 && byte <= 0x7E);
    if (printable) {
      values.add(String.fromCharCodes(bytes));
      index = end - 1;
    }
  }
  return values;
}

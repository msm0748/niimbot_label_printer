import 'dart:typed_data';

import 'hex_codec.dart';

final class D11hProtocolFrame {
  D11hProtocolFrame({required this.command, required Uint8List payload})
    : payload = Uint8List.fromList(payload).asUnmodifiableView();

  final int command;
  final Uint8List payload;

  String get payloadHex => formatHexBytes(payload);
}

final class D11hMediaProbeResult {
  const D11hMediaProbeResult({
    required this.createdAt,
    required this.informationResponse,
    required this.statusResponse,
  });

  final DateTime createdAt;
  final D11hProtocolFrame informationResponse;
  final D11hProtocolFrame? statusResponse;
}

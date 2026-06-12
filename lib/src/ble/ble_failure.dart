enum BleFailureCode {
  unsupported,
  unauthorized,
  poweredOff,
  scanFailed,
  connectionFailed,
  discoveryFailed,
  subscriptionFailed,
  writeFailed,
  mtuFailed,
  invalidState,
  unknown,
}

final class BleFailure implements Exception {
  const BleFailure({required this.code, required this.message, this.cause});

  final BleFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'BleFailure($code, $message)';
}

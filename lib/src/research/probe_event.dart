enum ProbeEventKind {
  readiness,
  scan,
  connection,
  serviceDiscovery,
  mtu,
  subscription,
  write,
  notification,
  error,
}

final class ProbeEvent {
  const ProbeEvent({
    required this.timestamp,
    required this.kind,
    required this.message,
  });

  final DateTime timestamp;
  final ProbeEventKind kind;
  final String message;

  String toLogLine() =>
      '${timestamp.toUtc().toIso8601String()} ${kind.name} $message';
}

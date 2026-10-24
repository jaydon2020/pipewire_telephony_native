/// A local protocol, connection, or remote D-Bus failure.
final class PipeWireTelephonyException implements Exception {
  /// Creates an error preserving the failing operation and D-Bus error name.
  const PipeWireTelephonyException({
    required this.category,
    required this.name,
    required this.message,
    required this.operation,
    required this.path,
    this.requestId,
  });

  /// Error origin, such as `local`, `connection`, or `remote`.
  final String category;

  /// D-Bus or package-defined error name.
  final String name;

  /// Human-readable error detail.
  final String message;

  /// Operation that failed.
  final String operation;

  /// D-Bus object path targeted by the operation.
  final String path;

  /// Request identity, or null for a lifecycle error.
  final int? requestId;

  @override
  String toString() => '$name: $message';
}

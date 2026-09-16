final class PipeWireTelephonyException implements Exception {
  const PipeWireTelephonyException({
    required this.category,
    required this.name,
    required this.message,
    required this.operation,
    required this.path,
    this.requestId,
  });

  final String category;
  final String name;
  final String message;
  final String operation;
  final String path;
  final int? requestId;

  @override
  String toString() => '$name: $message';
}

/// Immutable failure contract shared across modules.
final class AppFailure {
  const AppFailure({
    required this.code,
    required this.message,
    this.retryable = false,
    this.objectId,
    this.stage,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final String message;
  final bool retryable;
  final String? objectId;
  final String? stage;
  final Object? cause;
  final StackTrace? stackTrace;
}

/// Carries an [AppFailure] across an asynchronous module seam.
final class AppOperationException implements Exception {
  const AppOperationException(this.failure);

  final AppFailure failure;

  @override
  String toString() =>
      'AppOperationException(${failure.code}): ${failure.message}';
}

// lib/core/api_exception.dart

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? originalError;

  ApiException(
    this.message, {
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message, originalError: $originalError)';
}

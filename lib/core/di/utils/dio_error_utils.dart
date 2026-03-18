// lib/core/network/dio_error_utils.dart
import 'dart:io';
import 'package:dio/dio.dart';

bool shouldQueueOnDioError(DioException e) {
  // Нет ответа от сервера вообще (сеть/днс/обрыв)
  final underlying = e.error;
  if (underlying is SocketException) return true;

  // Таймауты/проблемы соединения
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return true;

    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;

      // Сервер/шлюз упал или временно недоступен
      if (code != null && code >= 500) return true;

      // Часто имеет смысл тоже класть в очередь
      if (code == 408 || code == 429) return true;

      // 4xx (400/401/403/404/422...) — это не “временно”, в очередь не кладём
      return false;

    case DioExceptionType.cancel:
      // отмена пользователем — точно не в очередь
      return false;

    case DioExceptionType.unknown:
      // иногда dio кидает unknown с SocketException выше; иначе — не гадать
      return underlying is SocketException;
    case DioExceptionType.badCertificate:
      return false;
  }
}

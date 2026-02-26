// // lib/features/auth/data/auth_service.dart

// import 'package:dio/dio.dart';
// import 'package:leemon_app/core/di/api/api_client.dart';
// import 'package:leemon_app/core/di/api/api_exception.dart';
// import 'package:leemon_app/core/models/login_response.dart';

// class AuthService {
//   final Dio _dio;

//   AuthService({Dio? dio}) : _dio = dio ?? ApiClient.dio;

//   /// Логин по email / password.
//   ///
//   /// Возвращает [LoginResponse] с токеном.
//   Future<LoginResponse> login({
//     required String email,
//     required String password,
//   }) async {
//     try {
//       final response = await _dio.post(
//         '/login',
//         data: <String, dynamic>{
//           'email': email.trim(),
//           'password': password,
//         },
//       );

//       // На всякий случай проверим статус
//       if (response.statusCode != 200) {
//         throw ApiException(
//           'Ошибка авторизации',
//           statusCode: response.statusCode,
//           originalError: response.data,
//         );
//       }

//       // Ожидаем JSON вида { "token": "..." }
//       final data = response.data;
//       if (data is! Map<String, dynamic>) {
//         throw ApiException(
//           'Неверный формат ответа от сервера',
//           statusCode: response.statusCode,
//           originalError: data,
//         );
//       }

//       return LoginResponse.fromJson(data);
//     } on DioException catch (e) {
//       // HTTP ошибка
//       final statusCode = e.response?.statusCode;

//       // Можно сделать чуть умнее разбор по коду
//       String message = 'Не удалось выполнить запрос';
//       if (statusCode == 400 || statusCode == 401) {
//         message = 'Неверный email или пароль';
//       } else if (statusCode != null && statusCode >= 500) {
//         message = 'Сервер временно недоступен, попробуйте позже';
//       }

//       throw ApiException(
//         message,
//         statusCode: statusCode,
//         originalError: e,
//       );
//     } catch (e) {
//       // Любая другая ошибка
//       throw ApiException(
//         'Неизвестная ошибка при авторизации',
//         originalError: e,
//       );
//     }
//   }
// }

// // lib/core/api_client.dart

// import 'dart:io';

// import 'package:dio/dio.dart';

// import 'app_config.dart';

// class ApiClient {
//   ApiClient._internal() {
//     _dio = Dio(
//       BaseOptions(
//         baseUrl: AppConfig.I.baseUrl,
//         connectTimeout: const Duration(seconds: 10),
//         receiveTimeout: const Duration(seconds: 10),
//         // если нужен JSON по умолчанию
//         headers: {
//           HttpHeaders.contentTypeHeader: 'application/json',
//           HttpHeaders.acceptHeader: 'application/json',
//         },
//       ),
//     );

//     // сюда потом можно добавить interceptors для токена, логирования и т.д.
//     // _dio.interceptors.add(LogInterceptor(responseBody: true));
//   }

//   late final Dio _dio;

//   static final ApiClient _instance = ApiClient._internal();

//   static Dio get dio => _instance._dio;
// }

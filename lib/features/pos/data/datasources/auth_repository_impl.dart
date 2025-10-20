// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:pos_desktop_clean/core/errors/failures.dart';
// import 'package:pos_desktop_clean/core/http/api_client.dart';
// import 'package:pos_desktop_clean/features/pos/data/dto/login_request_dto.dart';
// import 'package:pos_desktop_clean/features/pos/data/repositories/auth_repository.dart';
// import 'package:pos_desktop_clean/features/pos/domain/entities/auth_result.dart';
// import 'package:pos_desktop_clean/features/pos/domain/repositories/auth_repository.dart';
// import 'auth_api.dart';

// class AuthRepositoryImpl implements AuthRepository {
//   final AuthApi api;
//   final FlutterSecureStorage secureStorage;
//   AuthRepositoryImpl(this.api, this.secureStorage);

//   static const _kAccess = 'access_token';
//   static const _kRefresh = 'refresh_token';
//   static const _kApiBase = 'api_base_url';

//   @override
//   Future<AuthResult> login({
//     required String email,
//     required String password,
//     bool rememberMe = false,
//   }) async {
//     try {
//       final resp = await api.login(LoginRequestDto(email: email, password: password));
//       if (rememberMe) {
//         await secureStorage.write(key: _kAccess, value: resp.accessToken);
//         await secureStorage.write(key: _kRefresh, value: resp.refreshToken);
//         await secureStorage.write(key: _kApiBase, value: resp.apiBaseUrl);
//       }
//       return AuthResult(
//         accessToken: resp.accessToken,
//         refreshToken: resp.refreshToken,
//         apiBaseUrl: Uri.parse(resp.apiBaseUrl),
//       );
//     } on ApiException catch (e) {
//       throw Failure.message(e.message);
//     } catch (e) {
//       throw const Failure.unexpected();
//     }
//   }
// }

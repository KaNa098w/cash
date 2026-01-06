import 'package:dio/dio.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';

class AuthRemoteDataSource {
  final Dio _dio;
  AuthRemoteDataSource(this._dio);

  Future<PosProvisionResponse> provisionPos({
    required String key,
    required String deviceId,
  }) async {
    final safeKey = key.trim();

    final res = await _dio.get(
      'https://leemon.kz/api/organizations/pos/$safeKey',
      queryParameters: {
        'device_id': deviceId,
        'include': 'users',
      },
    );

    if (res.data is Map<String, dynamic>) {
      return PosProvisionResponse.fromJson(res.data as Map<String, dynamic>);
    }

    throw Exception('Unexpected response type: ${res.data.runtimeType}');
  }
}

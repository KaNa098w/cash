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
      '/organizations/pos/$safeKey',
      queryParameters: {
        'device_id': deviceId,
        'include': 'users',
      },
    );

    final data = res.data;
    if (data is Map<String, dynamic>) {
      return PosProvisionResponse.fromJson(data);
    }

    throw Exception('Unexpected response type: ${data.runtimeType}');
  }
}

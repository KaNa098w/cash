import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/app_update_response.dart';

class AppUpdateRemoteDataSource {
  final Dio _dio;

  AppUpdateRemoteDataSource(this._dio);

  Future<AppUpdateResponse> fetchLatest({
    required String channel,
    required String currentVersion,
    String? packageType,
  }) async {
    try {
      final response = await _dio.get(
        '/app-updates/latest',
        queryParameters: <String, Object?>{
          'channel': channel,
          'current_version': currentVersion,
          if (packageType != null && packageType.isNotEmpty)
            'package_type': packageType,
        },
      );
      final data = response.data;

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid update response format: expected Map, got ${data.runtimeType}',
        );
      }

      return AppUpdateResponse.fromJson(data);
    } on DioException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }
}

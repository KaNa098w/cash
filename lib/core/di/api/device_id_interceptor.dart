import 'package:dio/dio.dart';
import 'package:leemon_app/core/di/api/device_id_store.dart';

class DeviceIdInterceptor extends Interceptor {
  DeviceIdInterceptor(this._store);

  final DeviceIdStore _store;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final deviceId = _store.deviceId?.trim() ?? '';

    if (deviceId.isNotEmpty && options.path.contains('/organizations/pos/')) {
      final method = options.method.toUpperCase();
      if (method == 'GET' || method == 'DELETE') {
        options.queryParameters.putIfAbsent('device_id', () => deviceId);
      } else if (options.data == null) {
        options.data = {'device_id': deviceId};
      } else if (options.data is Map) {
        final body = Map<String, dynamic>.from(options.data as Map);
        body.putIfAbsent('device_id', () => deviceId);
        options.data = body;
      } else {
        options.queryParameters.putIfAbsent('device_id', () => deviceId);
      }
    }

    handler.next(options);
  }
}

import 'package:dio/dio.dart';
import 'package:pos_desktop_clean/core/di/api/device_id_store.dart';

class DeviceIdInterceptor extends Interceptor {
  DeviceIdInterceptor(this._store);

  final DeviceIdStore _store;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = _store.deviceId;

    if (id != null && id.isNotEmpty) {
      // не перетираем если уже передали руками
      options.queryParameters.putIfAbsent('device_id', () => id);
    }

    handler.next(options);
  }
}

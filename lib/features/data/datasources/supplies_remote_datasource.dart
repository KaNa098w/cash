import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/supply.dart';

String supplyError(Object error) {
  if (error is DioException) {
    final j = supplyMap(error.response?.data);
    final errors = supplyMap(j['errors']);
    final details = errors.entries
        .map((e) =>
            '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}')
        .join('\n');
    if (error.response?.statusCode == 401) {
      return 'Доступ POS или ключ управляющего недействителен. Проверьте подключение кассы и ключ этого магазина.';
    }
    if (error.response?.statusCode == 404) {
      return 'Документ недоступен или уже удалён. Обновите список.';
    }
    if (details.isNotEmpty) return details;
    if (j['message'] != null) return '${j['message']}';
    return 'Нет подтверждения сервера. Проверьте интернет и результат операции перед повтором.';
  }
  if (error is StateError) return error.message;
  return 'Не удалось обработать ответ сервера. Обновите данные.';
}

class SuppliesRemoteDataSource {
  SuppliesRemoteDataSource(this.dio, {this.directorUserId});
  final Dio dio;
  final String? directorUserId;
  bool get isDirector => (directorUserId ?? '').trim().isNotEmpty;
  SuppliesRemoteDataSource forDirector(String id) =>
      SuppliesRemoteDataSource(dio, directorUserId: id.trim());
  Map<String, dynamic> writeData(String device, Map<String, dynamic> payload) =>
      {
        ...payload,
        'device_id': device,
        if (isDirector) 'user_id': directorUserId!.trim(),
      };
  String base(String key) =>
      '/organizations/pos/${Uri.encodeComponent(key)}/supplies';
  String doc(String key, String id) =>
      '${base(key)}/${Uri.encodeComponent(id)}';
  Options access(String key) {
    if (isDirector) return Options();
    if (key.trim().isEmpty) {
      throw StateError('Для записи нужен ключ управляющего');
    }
    return Options(headers: {'X-Return-Access-Key': key.trim()});
  }

  Map<String, dynamic> data(dynamic body) {
    final root = supplyMap(body);
    final value = root['data'];
    if (value is! Map) throw const FormatException('Missing data');
    return supplyMap(value);
  }

  Future<SupplyReferences> references(String key, String device) async =>
      SupplyReferences.fromJson(data((await dio.get('${base(key)}/references',
              queryParameters: {'device_id': device}))
          .data));
  Future<SupplyPage> list(String key, String device,
          {int page = 1, Map<String, dynamic> filters = const {}}) async =>
      SupplyPage.fromJson(supplyMap((await dio.get(base(key), queryParameters: {
        ...filters,
        'device_id': device,
        'page': page,
        'perPage': 20
      }))
          .data));
  Future<SupplyDocument> get(String key, String device, String id) async {
    final result = SupplyDocument(data(
        (await dio.get(doc(key, id), queryParameters: {'device_id': device}))
            .data));
    if (result.id.isEmpty) throw const FormatException('Missing supply id');
    return result;
  }

  Future<String> save(
      String key, String device, String manager, Map<String, dynamic> payload,
      {String? id}) async {
    final body = writeData(device, payload);
    final response = id == null
        ? await dio.post(base(key), data: body, options: access(manager))
        : await dio.put(doc(key, id), data: body, options: access(manager));
    if (id != null) return id;
    final created = '${data(response.data)['id'] ?? ''}';
    if (created.isEmpty) {
      throw const FormatException('Missing created supply id');
    }
    return created;
  }

  Future<void> status(String key, String device, String manager, String id,
      bool completed) async {
    await dio.patch('${doc(key, id)}/status',
        data: writeData(device, {'completed': completed}),
        options: access(manager));
  }

  Future<void> delete(
      String key, String device, String manager, String id) async {
    await dio.delete(doc(key, id),
        data: writeData(device, {}), options: access(manager));
  }

  Future<SupplyReference> supplier(String key, String device, String manager,
          Map<String, dynamic> payload) async =>
      SupplyReference.fromJson(data((await dio.post('${base(key)}/suppliers',
              data: writeData(device, payload), options: access(manager)))
          .data));
  Future<void> payment(String key, String device, String manager, String id,
      Map<String, dynamic> payload,
      {String? paymentId}) async {
    final path = '${doc(key, id)}/payments';
    final body = writeData(device, payload);
    if (paymentId == null) {
      await dio.post(path, data: body, options: access(manager));
    } else {
      await dio.put('$path/${Uri.encodeComponent(paymentId)}',
          data: body, options: access(manager));
    }
  }

  Future<void> deletePayment(String key, String device, String manager,
      String id, String paymentId) async {
    await dio.delete(
        '${doc(key, id)}/payments/${Uri.encodeComponent(paymentId)}',
        data: writeData(device, {}),
        options: access(manager));
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/payment_invoice.dart';
import 'customers_remote_datasource.dart';

String invoiceError(Object error) {
  if (error is DioException) {
    dynamic body = error.response?.data;
    if (body is List<int>) {
      try {
        body = jsonDecode(utf8.decode(body));
      } catch (_) {}
    }
    if (body is Map) {
      final errors = body['errors'];
      if (errors is Map) {
        final messages = errors.values
            .expand((v) => v is List ? v : [v])
            .map((v) => v.toString())
            .where((v) => v.isNotEmpty)
            .toList();
        if (messages.isNotEmpty) return messages.join('\n');
      }
      if (body['message'] != null) return body['message'].toString();
    }
    return 'Не удалось получить ответ сервера. Проверьте соединение и повторите.';
  }
  if (error is StateError) return error.message;
  return 'Не удалось выполнить действие. Попробуйте снова.';
}

/// Only field validation establishes that the request can be edited safely.
/// An idempotency conflict may refer to an already issued document.
bool invoiceValidationCanBeCorrected(Object error) {
  if (error is! DioException || error.response?.statusCode != 422) return false;
  final body = error.response?.data;
  if (body is! Map) return false;
  final errors = body['errors'];
  if (errors is! Map || errors.isEmpty) return false;
  final text = jsonEncode(body).toLowerCase();
  if (text.contains('idempotency') ||
      text.contains('client_invoice_id') ||
      text.contains('client_payment_id')) {
    return false;
  }
  return true;
}

class InvoicesRemoteDataSource {
  InvoicesRemoteDataSource(this._dio);
  final Dio _dio;
  String _base(String key) => '/organizations/pos/${Uri.encodeComponent(key)}';
  Map<String, dynamic> _data(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data']);
    }
    throw const FormatException('Invalid invoice response');
  }

  PaymentInvoice _invoice(dynamic body) {
    final invoice = PaymentInvoice(_data(body));
    if (invoice.id.isEmpty) throw const FormatException('Missing invoice id');
    return invoice;
  }

  Future<List<OrganizationBankAccount>> bankAccounts(String key) async {
    final r = await _dio.get('${_base(key)}/bank-accounts');
    return (r.data['data'] as List)
        .map((v) => OrganizationBankAccount(Map<String, dynamic>.from(v)))
        .toList();
  }

  Future<CustomerDto> createCustomer(String key,
      {required String name,
      required String userId,
      String phone = '',
      String bin = '',
      String legalName = '',
      String legalAddress = ''}) async {
    if (name.trim().isEmpty) throw StateError('Укажите имя покупателя');
    if (bin.trim().isNotEmpty &&
        (!RegExp(r'^\d{12}$').hasMatch(bin.trim()) ||
            legalName.trim().isEmpty ||
            legalAddress.trim().isEmpty)) {
      throw StateError('Укажите 12 цифр ИИН/БИН, юридическое название и адрес');
    }
    final r = await _dio.post('${_base(key)}/customers', data: {
      'name': name.trim(),
      'user_id': userId,
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (bin.trim().isNotEmpty) ...{
        'bin': bin.trim(),
        'legal_type': 'legal_entity',
        'legal_name': legalName.trim(),
        'legal_address': legalAddress.trim(),
      },
    });
    return CustomerDto.fromJson(_data(r.data));
  }

  Future<PaymentInvoice> create(
      String key, Map<String, dynamic> payload) async {
    final r = await _dio.post('${_base(key)}/invoices', data: payload);
    return _invoice(r.data);
  }

  Future<PaymentInvoicePage> list(String key, {int page = 1}) async {
    final r = await _dio.get('${_base(key)}/invoices',
        queryParameters: {'perPage': 15, 'page': page});
    final body = Map<String, dynamic>.from(r.data);
    final meta = body['meta'] as Map? ?? {};
    return PaymentInvoicePage(
        (body['data'] as List)
            .map((v) => PaymentInvoice(Map<String, dynamic>.from(v)))
            .toList(),
        int.tryParse('${meta['current_page']}') ?? page,
        int.tryParse('${meta['last_page']}') ?? page);
  }

  Future<PaymentInvoice> get(String key, String id) async => _invoice(
      (await _dio.get('${_base(key)}/invoices/${Uri.encodeComponent(id)}'))
          .data);

  Future<PaymentInvoice> confirm(
      String key, String id, Map<String, dynamic> payload) async {
    final result = _invoice((await _dio.post(
            '${_base(key)}/invoices/${Uri.encodeComponent(id)}/confirm-payment',
            data: payload))
        .data);
    if (result.status != 'paid' || result.saleId.isEmpty) {
      throw const FormatException('Payment confirmation was not returned');
    }
    return result;
  }

  Future<void> cancel(String key, String id) async {
    await _dio.delete('${_base(key)}/invoices/${Uri.encodeComponent(id)}');
  }

  Future<Uint8List> document(String key, String id,
      {String format = 'pdf'}) async {
    final r = await _dio.get<List<int>>(
        '${_base(key)}/invoices/${Uri.encodeComponent(id)}/document',
        queryParameters: {'format': format},
        options: Options(responseType: ResponseType.bytes, headers: {
          'Accept': format == 'pdf'
              ? 'application/pdf'
              : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        }, extra: {
          'silentDioLog': true
        }));
    final bytes = r.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Сервер вернул пустой документ');
    }
    return Uint8List.fromList(bytes);
  }
}

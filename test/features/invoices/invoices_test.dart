import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/di/api/device_id_interceptor.dart';
import 'package:leemon_app/core/di/api/device_id_store.dart';
import 'package:leemon_app/core/models/payment_invoice.dart';
import 'package:leemon_app/features/data/datasources/invoices_remote_datasource.dart';
import 'package:leemon_app/features/data/repositories/invoice_payment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default bank falls back to first and empty list blocks selection', () {
    final first = OrganizationBankAccount({'id': 'A'});
    final preferred = OrganizationBankAccount({'id': 'B', 'is_default': true});
    expect(OrganizationBankAccount.preferred([first, preferred]), preferred);
    expect(OrganizationBankAccount.preferred([first]), first);
    expect(OrganizationBankAccount.preferred([]), isNull);
  });

  test('expiry uses calendar day and never replaces paid or cancelled status',
      () {
    final today = DateTime(2026, 9, 21, 23, 59);
    expect(
        PaymentInvoice({'status': 'issued', 'due_at': '2026-09-21'})
            .statusAt(today),
        'issued');
    expect(
        PaymentInvoice({'status': 'issued', 'due_at': '2026-09-20'})
            .statusAt(today),
        'expired');
    for (final status in ['paid', 'cancelled', 'expired']) {
      expect(
          PaymentInvoice({'status': status, 'due_at': '2026-09-20'})
              .statusAt(today),
          status);
    }
  });

  test('payment retry after restart preserves UUID, date, shift and comment',
      () async {
    final payload = await InvoicePaymentStore().prepare(
        scope: 'POS:DEVICE',
        invoiceId: 'INV',
        sessionId: 'SHIFT',
        userId: 'USER',
        comment: 'Получено',
        date: DateTime(2026, 9, 21, 14, 30));
    expect(payload['date'], '2026-09-21 14:30:00');
    final retry = await InvoicePaymentStore().prepare(
        scope: 'POS:DEVICE',
        invoiceId: 'INV',
        sessionId: 'NEW_SHIFT',
        userId: 'OTHER',
        comment: 'Changed',
        date: DateTime(2026, 9, 22));
    expect(retry, payload);
    final other = await InvoicePaymentStore().prepare(
        scope: 'OTHER:DEVICE',
        invoiceId: 'INV',
        sessionId: 'SHIFT',
        userId: 'USER',
        comment: '',
        date: DateTime(2026));
    expect(other['client_payment_id'], isNot(payload['client_payment_id']));
  });

  test('422 uses field messages including errors returned as binary document',
      () {
    final request = RequestOptions(path: '/invoices');
    final data = {
      'message': 'The given data was invalid.',
      'errors': {
        'items.0.quantity': ['Недостаточно товара'],
        'due_at': ['Срок истёк']
      }
    };
    for (final body in [data, utf8.encode(jsonEncode(data))]) {
      expect(
          invoiceError(DioException(
              requestOptions: request,
              response: Response(
                  requestOptions: request, statusCode: 422, data: body))),
          'Недостаточно товара\nСрок истёк');
    }
  });

  test(
      'POS invoice endpoints preserve payload and use existing device authentication',
      () async {
    final device = DeviceIdStore();
    device.deviceId = 'DEVICE';
    final requests = <RequestOptions>[];
    final dio = Dio()..interceptors.add(DeviceIdInterceptor(device));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      dynamic body = {
        'data': {'id': 'INV', 'status': 'issued'}
      };
      if (r.path.endsWith('/bank-accounts')) {
        body = {
          'data': [
            {'id': 'BANK', 'is_default': true}
          ]
        };
      }
      if (r.path.endsWith('/customers')) {
        body = {
          'data': {'id': 'CUSTOMER', 'name': 'Иван'}
        };
      }
      if (r.path.endsWith('/invoices') && r.method == 'GET') {
        body = {
          'data': [
            {'id': 'INV', 'status': 'issued'}
          ],
          'meta': {'current_page': 2, 'last_page': 3}
        };
      }
      if (r.path.endsWith('/document')) body = [37, 80, 68, 70];
      if (r.path.endsWith('/confirm-payment')) {
        body = {
          'data': {'id': 'INV', 'status': 'paid', 'sale_id': 'SALE'}
        };
      }
      if (r.method == 'DELETE') body = null;
      h.resolve(Response(requestOptions: r, statusCode: 200, data: body));
    }));
    final api = InvoicesRemoteDataSource(dio);
    await api.bankAccounts('KEY');
    await api.createCustomer('KEY', name: 'Иван', userId: 'USER');
    expect(requests.last.data,
        {'name': 'Иван', 'user_id': 'USER', 'device_id': 'DEVICE'});
    await api.createCustomer('KEY',
        name: 'Компания',
        userId: 'USER',
        phone: '+77011234567',
        bin: '123456789012',
        legalName: 'ТОО Компания',
        legalAddress: 'Алматы, Абая 1');
    expect(requests.last.data, {
      'name': 'Компания',
      'user_id': 'USER',
      'device_id': 'DEVICE',
      'phone': '+77011234567',
      'bin': '123456789012',
      'legal_type': 'legal_entity',
      'legal_name': 'ТОО Компания',
      'legal_address': 'Алматы, Абая 1',
    });
    final count = requests.length;
    await expectLater(
        api.createCustomer('KEY', name: 'Компания', userId: 'USER', bin: '123'),
        throwsStateError);
    expect(requests.length, count);
    final payload = {
      'client_invoice_id': 'STABLE',
      'customer_id': 'CUSTOMER',
      'organization_bank_account_id': 'BANK',
      'items': [
        {
          'product_id': 'P',
          'quantity': 2,
          'price': 1500,
          'total_price': 3000,
          'mark_codes': ['CODE']
        }
      ]
    };
    await api.create('KEY', payload);
    await api.create('KEY', payload);
    expect(requests[requests.length - 2].data, requests.last.data);
    expect(payload.containsKey('device_id'), isFalse);
    final page = await api.list('KEY', page: 2);
    expect(page.lastPage, 3);
    expect(requests.last.queryParameters,
        {'page': 2, 'perPage': 15, 'device_id': 'DEVICE'});
    await api.get('KEY', 'INV');
    await api.confirm('KEY', 'INV',
        {'client_payment_id': 'PAY', 'date': '2026-09-21 14:30:00'});
    expect(requests.last.path,
        '/organizations/pos/KEY/invoices/INV/confirm-payment');
    final bytes = await api.document('KEY', 'INV', format: 'xlsx');
    expect(bytes, [37, 80, 68, 70]);
    expect(requests.last.queryParameters,
        {'format': 'xlsx', 'device_id': 'DEVICE'});
    await api.cancel('KEY', 'INV');
    expect(requests.last.method, 'DELETE');
    expect(requests.every((r) => r.path.startsWith('/organizations/pos/KEY/')),
        isTrue);
    expect(requests.any((r) => r.path.endsWith('/sales')), isFalse);
  });
  test('only definitive field rejection permits changing a saved request', () {
    final request = RequestOptions(path: '/invoices');
    DioException failure(Map<String, dynamic> body) => DioException(
        requestOptions: request,
        response:
            Response(requestOptions: request, statusCode: 422, data: body));
    expect(
        invoiceValidationCanBeCorrected(failure({
          'errors': {
            'due_at': ['Дата в прошлом']
          }
        })),
        isTrue);
    expect(
        invoiceValidationCanBeCorrected(failure({
          'errors': {
            'client_invoice_id': ['Конфликт']
          }
        })),
        isFalse);
    expect(
        invoiceValidationCanBeCorrected(
            failure({'message': 'Неизвестная ошибка'})),
        isFalse);
  });
}

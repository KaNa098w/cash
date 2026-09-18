import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';

void main() {
  late Dio dio;
  late List<RequestOptions> requests;
  setUp(() {
    requests = [];
    dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'data': request.path.endsWith('/sales')
              ? []
              : {
                  'id': 'DOCUMENT',
                  'agent': {'debt_balance': -25.50},
                },
        }));
      }));
  });

  test('outbox settlement uses customer endpoint and never sends sale linkage',
      () async {
    await PosSyncRemoteDataSource(dio).sendOperation(
        type: OutboxOperationType.settlement,
        key: 'KEY',
        payload: {
          'customer_id': 'CUSTOMER',
          'account_id': 'BANK',
          'amount': 100.25,
          'date': '2026-09-18 15:00:00',
          'user_id': 'USER',
          'client_settlement_id': 'STABLE',
        });
    expect(requests.single.path,
        '/organizations/pos/KEY/customers/CUSTOMER/settlements');
    expect(requests.single.data, {
      'account_id': 'BANK',
      'amount': 100.25,
      'date': '2026-09-18 15:00:00',
      'user_id': 'USER',
      'client_settlement_id': 'STABLE',
    });
  });

  test('sale discovery uses POS key and customer filter', () async {
    final ds = SaleRemoteDataSource(dio);
    await ds.fetchSaleById(key: 'KEY', saleId: 'SALE');
    expect(requests.last.path, '/organizations/pos/KEY/sales/SALE');
    await ds.getAllSales(key: 'KEY', customerId: 'CUSTOMER');
    expect(requests.last.path, '/organizations/pos/KEY/sales');
    expect(requests.last.queryParameters['filter[customer_id]'], 'CUSTOMER');
  });

  test('settlement accepts balance-only agent and formats exact date',
      () async {
    final ds = CustomersRemoteDataSource(dio);
    final result = await ds.settleDebt(
        key: 'KEY',
        customerId: 'CUSTOMER',
        accountId: 'BANK',
        amount: 0.01,
        date: DateTime(2026, 9, 18, 15),
        userId: 'USER',
        clientSettlementId: 'STABLE');
    expect(requests.single.data['date'], '2026-09-18 15:00:00');
    expect(result.agent.id, 'CUSTOMER');
    expect(result.agent.debtBalance, -25.50);
    expect(result.agent.balance, -25.50);
    expect(result.agent.debtState, 'advance');
  });
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/service/kaspi_payment_service.dart';

Map<String, dynamic> response(String status) => {
      'statusCode': 0,
      'data': {
        'processId': '123',
        'status': status,
        if (status == 'success') 'transactionId': 'order-42'
      },
    };

void main() {
  late Map<String, String> disk;
  late List<String> calls;
  late KaspiRequest transport;
  KaspiPaymentService service({int maxPolls = 4, DateTime Function()? now}) =>
      KaspiPaymentService(
        request: (path, parameters) {
          calls.add(path);
          return transport(path, parameters);
        },
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
        pollInterval: Duration.zero,
        maxPolls: maxPolls,
        now: now,
      );
  setUp(() {
    disk = {};
    calls = [];
    transport = (path, parameters) async =>
        response(path == '/v2/payment' ? 'wait' : 'success');
  });

  test('only the selected Kaspi bank portion is sent, not cash or another bank',
      () {
    expect(
        kaspiPaymentAmount([
          {
            'amount': 200,
            'account': {'name': 'Kaspi наличные', 'type': 'CASH'}
          },
          {
            'amount': 300,
            'account': {'name': 'Kaspi Bank', 'type': 'BANK'}
          },
          {
            'amount': 400,
            'account': {'name': 'Halyk', 'type': 'BANK'}
          },
        ]),
        300);
    expect(isKaspiAccountName('КАСПИ'), isTrue);
    expect(
        kaspiPaymentAmount([
          {'amount': 100}
        ]),
        0);
  });

  test('success is durable and retry after restart never starts a new payment',
      () async {
    transport = (path, p) async {
      if (path == '/v2/payment') {
        expect(p['amount'], 5000);
        expect(p['owncheque'], isFalse);
      }
      return response(path == '/v2/payment' ? 'wait' : 'success');
    };
    expect(
        (await service().pay(saleId: 'sale1', amount: 5000))['transactionId'],
        'order-42');
    await service().pay(saleId: 'sale1', amount: 5000);
    expect(calls, ['/v2/payment', '/v2/status']);
    expect(disk[KaspiPaymentService.activeKey], '');
  });

  test('lost status response resumes with the same processId after restart',
      () async {
    transport = (path, p) async {
      if (path == '/v2/status') throw StateError('connection lost');
      return response('wait');
    };
    await expectLater(
        service().pay(saleId: 'sale1', amount: 100), throwsStateError);
    transport = (path, p) async {
      expect(path, '/v2/status');
      expect(p['processId'], '123');
      return response('success');
    };
    await service().pay(saleId: 'sale1', amount: 100);
    expect(calls.where((p) => p == '/v2/payment').length, 1);
  });

  test('lost start response permanently blocks automatic resend', () async {
    transport = (_, __) async => throw TimeoutException('lost');
    await expectLater(service().pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    await expectLater(service().pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    await expectLater(service().pay(saleId: 'sale2', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    expect(calls, ['/v2/payment']);
  });

  test('unknown is actualized and success permits checkout', () async {
    transport = (path, p) async => response(switch (path) {
          '/v2/payment' => 'wait',
          '/v2/status' => 'unknown',
          _ => 'success',
        });
    await service().pay(saleId: 'sale1', amount: 100);
    expect(calls, ['/v2/payment', '/v2/status', '/v2/actualize']);
  });

  test(
      'unknown remains locked and actualize respects 10 seconds across restarts',
      () async {
    final now = DateTime(2026, 10, 26, 13);
    transport =
        (path, p) async => response(path == '/v2/payment' ? 'wait' : 'unknown');
    await expectLater(service(now: () => now).pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    await expectLater(service(now: () => now).pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    expect(calls.where((p) => p == '/v2/actualize').length, 1);
    expect(disk[KaspiPaymentService.activeKey], 'sale1');
    await expectLater(service().pay(saleId: 'sale2', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
  });

  test('explicit failure allows a new attempt for the same checkout', () async {
    transport =
        (path, p) async => response(path == '/v2/payment' ? 'wait' : 'fail');
    await expectLater(service().pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    transport =
        (path, p) async => response(path == '/v2/payment' ? 'wait' : 'success');
    await service().pay(saleId: 'sale1', amount: 100);
    expect(calls.where((p) => p == '/v2/payment').length, 2);
  });

  test('fractional, nonpositive and nonfinite amounts never reach the terminal',
      () async {
    for (final amount in [0.0, -1.0, 10.25, double.nan, double.infinity]) {
      await expectLater(service().pay(saleId: 'sale1', amount: amount),
          throwsA(isA<KaspiPaymentException>()));
    }
    expect(calls, isEmpty);
    expect(disk, isEmpty);
  });

  test('a definitively failed payment permits a corrected amount', () async {
    transport =
        (path, p) async => response(path == '/v2/payment' ? 'wait' : 'fail');
    await expectLater(service().pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    transport = (path, p) async {
      if (path == '/v2/payment') expect(p['amount'], 200);
      return response(path == '/v2/payment' ? 'wait' : 'success');
    };
    await service().pay(saleId: 'sale1', amount: 200);
  });

  test(
      'changing the amount of a successful checkout cannot start another payment',
      () async {
    await service().pay(saleId: 'sale1', amount: 100);
    await expectLater(service().pay(saleId: 'sale1', amount: 200),
        throwsA(isA<KaspiPaymentException>()));
    expect(calls.where((p) => p == '/v2/payment').length, 1);
  });

  test('missing processId leaves the start request locked', () async {
    transport = (_, __) async => {'statusCode': 0, 'data': {}};
    await expectLater(service().pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    await expectLater(service().pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    expect(calls, ['/v2/payment']);
  });

  test('crash after writing success recovers without a terminal request',
      () async {
    disk[KaspiPaymentService.activeKey] = 'sale1';
    disk['kaspi.payment.sale1'] = jsonEncode({
      'amount': 100,
      'status': 'success',
      'result': response('success')['data'],
    });
    await service().pay(saleId: 'sale1', amount: 100);
    expect(disk[KaspiPaymentService.activeKey], '');
    expect(calls, isEmpty);
  });

  test('failed durable write prevents payment from reaching terminal',
      () async {
    final broken = KaspiPaymentService(
        request: transport,
        read: (_) async => null,
        write: (_, __) async => throw StateError('disk full'));
    await expectLater(
        broken.pay(saleId: 'sale1', amount: 100), throwsStateError);
    expect(calls, isEmpty);
  });

  test('double clicking cannot send parallel payment requests', () async {
    final pending = Completer<Map<String, dynamic>>();
    transport = (path, p) async =>
        path == '/v2/payment' ? pending.future : response('success');
    final terminal = service();
    final first = terminal.pay(saleId: 'sale1', amount: 100);
    await expectLater(terminal.pay(saleId: 'sale1', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    pending.complete(response('wait'));
    await first;
    expect(calls.where((p) => p == '/v2/payment').length, 1);
  });
}

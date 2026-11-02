import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/service/kaspi_terminal.dart';
import 'package:leemon_app/core/service/kaspi_payment_service.dart';

class _Adapter implements HttpClientAdapter {
  final paths = <String>[];
  late Future<ResponseBody> Function(RequestOptions, Future<void>?) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) {
    paths.add(options.path);
    return handler(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(Map<String, dynamic> data, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

Future<ResponseBody> _hang(RequestOptions options, Future<void>? cancelled) {
  final pending = Completer<ResponseBody>();
  cancelled?.then((_) => pending.completeError(
      DioException(requestOptions: options, type: DioExceptionType.cancel)));
  return pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('launch deadline cancels a silent terminal without resending', () async {
    final adapter = _Adapter()..handler = _hang;
    final dio = Dio()..httpClientAdapter = adapter;
    final terminal = KaspiTerminal.forTesting(
        client: dio, launchTimeout: const Duration(milliseconds: 50));
    await expectLater(
        terminal.pay(saleId: 'sale', amount: 100),
        throwsA(isA<KaspiPaymentException>()
            .having((e) => e.message, 'message', contains('15 секунд'))));
    expect(adapter.paths, ['/v2/payment']);
  });

  test('access refresh shares the same launch deadline and cannot resend late',
      () async {
    final adapter = _Adapter();
    adapter.handler = (options, cancelled) async {
      if (options.path == '/v2/payment') return _response({}, status: 403);
      return _hang(options, cancelled);
    };
    final terminal = KaspiTerminal.forTesting(
        client: Dio()..httpClientAdapter = adapter,
        launchTimeout: const Duration(milliseconds: 50));
    await expectLater(terminal.pay(saleId: 'sale', amount: 100),
        throwsA(isA<KaspiPaymentException>()));
    expect(adapter.paths, ['/v2/payment', '/v2/revoke']);
  });

  test('launch deadline does not interrupt a customer paying after QR appears',
      () async {
    final adapter = _Adapter();
    final status = Completer<ResponseBody>();
    final statusRequested = Completer<void>();
    adapter.handler = (options, cancelled) async {
      if (options.path == '/v2/payment') {
        return _response({
          'statusCode': 0,
          'data': {'processId': 'p', 'status': 'wait'}
        });
      }
      statusRequested.complete();
      return status.future;
    };
    final terminal = KaspiTerminal.forTesting(
        client: Dio()..httpClientAdapter = adapter,
        launchTimeout: const Duration(milliseconds: 100));
    final payment = terminal.pay(saleId: 'sale', amount: 100);
    await statusRequested.future;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    status.complete(_response({
      'statusCode': 0,
      'data': {'status': 'success'}
    }));
    expect((await payment)['status'], 'success');
    expect(adapter.paths, ['/v2/payment', '/v2/status']);
  });
}

import 'dart:async';
import 'dart:convert';

typedef KaspiRequest = Future<Map<String, dynamic>> Function(
    String path, Map<String, dynamic> parameters);
typedef KaspiRead = Future<String?> Function(String key);
typedef KaspiWrite = Future<void> Function(String key, String value);

class KaspiPaymentException implements Exception {
  const KaspiPaymentException(this.message, {this.confirmedFailure = false});
  final String message;
  final bool confirmedFailure;
  @override
  String toString() => message;
}

/// Kaspi accounts are identified by their displayed name, never their logo URL.
bool isKaspiAccountName(String name) =>
    RegExp(r'kaspi|каспи', caseSensitive: false).hasMatch(name);

double kaspiPaymentAmount(List<Map<String, dynamic>> payments) => payments
    .where((p) =>
        p['account'] is Map &&
        (p['account']['type'] ?? '').toString().trim().toLowerCase() ==
            'bank' &&
        isKaspiAccountName((p['account']['name'] ?? '').toString()))
    .fold(0.0, (sum, p) => sum + (p['amount'] as num).toDouble());

/// Durable payment journal. A request with a lost response must never be replayed.
/// Checkout payloads remain frozen until the backend has accepted the sale.
class KaspiPaymentService {
  KaspiPaymentService({
    required this.request,
    required this.read,
    required this.write,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPolls = 300,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final KaspiRequest request;
  final KaspiRead read;
  final KaspiWrite write;
  final Duration pollInterval;
  final int maxPolls;
  final DateTime Function() now;
  bool _busy = false;
  static const activeKey = 'kaspi.activePayment';

  Future<Map<String, dynamic>> pay({
    required String saleId,
    required double amount,
    void Function(String message)? onProgress,
  }) async {
    if (_busy) {
      throw const KaspiPaymentException('Дождитесь текущей операции Kaspi');
    }
    if (!amount.isFinite || amount <= 0 || amount != amount.roundToDouble()) {
      throw const KaspiPaymentException(
          'Kaspi принимает только целую сумму в тенге. Исправьте сумму безналичной оплаты.');
    }
    _busy = true;
    try {
      final key = 'kaspi.payment.$saleId';
      final raw = await read(key);
      var record = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw));
      if (record.isNotEmpty &&
          record['amount'] != amount &&
          record['status'] != 'fail') {
        throw const KaspiPaymentException(
            'Сумма сохранённой операции Kaspi отличается. Нужна сверка оплаты.');
      }
      if (record['status'] == 'success') {
        // Finish releasing the terminal lock if the previous process stopped
        // after writing success but before releasing the lock.
        if (await read(activeKey) == saleId) await write(activeKey, '');
        return Map<String, dynamic>.from(record['result']);
      }
      final active = await read(activeKey);
      if (active != null && active.isNotEmpty && active != saleId) {
        throw const KaspiPaymentException(
            'Есть незавершённая оплата Kaspi в другой корзине. Сначала проверьте её результат.');
      }
      // Record the lock before any network request. On a crash without a
      // processId, fail closed and require reconciliation on the terminal.
      await write(activeKey, saleId);
      if (record['status'] == 'starting') {
        throw const KaspiPaymentException(
            'Ответ на запуск Kaspi потерян. Проверьте историю терминала; повторная отправка заблокирована. Обратитесь к администратору.');
      }
      if (record.isEmpty || record['status'] == 'fail') {
        record = {'amount': amount, 'status': 'starting'};
        await write(key, jsonEncode(record));
        onProgress?.call('Отправка суммы на Kaspi…');
        Map<String, dynamic> started;
        try {
          started = await request(
              '/v2/payment', {'amount': amount.toInt(), 'owncheque': false});
        } catch (_) {
          throw const KaspiPaymentException(
              'Нет ответа от Kaspi. Проверьте терминал. Повторная отправка заблокирована до сверки.');
        }
        if (started['statusCode'] != 0) {
          record['status'] = 'fail';
          await write(key, jsonEncode(record));
          await write(activeKey, '');
          throw KaspiPaymentException(
              'Kaspi: ${started['errorText'] ?? 'не удалось начать оплату'}',
              confirmedFailure: true);
        }
        final data = Map<String, dynamic>.from(started['data'] ?? {});
        final processId = (data['processId'] ?? '').toString();
        if (processId.isEmpty) {
          throw const KaspiPaymentException(
              'Kaspi не вернул номер операции. Проверьте историю терминала перед повторной оплатой.');
        }
        record.addAll({'status': 'wait', 'processId': processId});
        await write(key, jsonEncode(record));
      }

      for (var i = 0; i < maxPolls; i++) {
        onProgress?.call('Ожидаем оплату на Kaspi. QR или карта.');
        final response =
            await request('/v2/status', {'processId': record['processId']});
        if (response['statusCode'] != 0) {
          throw KaspiPaymentException(
              'Не удалось проверить Kaspi: ${response['errorText'] ?? 'ошибка'}. Номер операции сохранён; повторите проверку.');
        }
        var result = Map<String, dynamic>.from(response['data'] ?? {});
        if (result['status'] == 'unknown') {
          onProgress?.call('Уточняем результат оплаты Kaspi…');
          final last = DateTime.tryParse(record['actualizedAt'] ?? '');
          if (last == null || now().difference(last).inSeconds >= 10) {
            record['actualizedAt'] = now().toIso8601String();
            await write(key, jsonEncode(record));
            final actualized = await request(
                '/v2/actualize', {'processId': record['processId']});
            if (actualized['statusCode'] == 0) {
              result = Map<String, dynamic>.from(actualized['data'] ?? {});
            }
          }
        }
        if (result['status'] == 'success' || result['status'] == 'fail') {
          record.addAll({'status': result['status'], 'result': result});
          await write(key, jsonEncode(record));
          await write(activeKey, '');
          if (result['status'] == 'success') return result;
          throw KaspiPaymentException(
              'Оплата Kaspi не выполнена: ${result['message'] ?? 'отменена или отклонена'}. Можно повторить оплату.',
              confirmedFailure: true);
        }
        await Future<void>.delayed(pollInterval);
      }
      throw const KaspiPaymentException(
          'Kaspi ещё не подтвердил результат. Номер операции сохранён. Повторите проверку оплаты.');
    } finally {
      _busy = false;
    }
  }
}

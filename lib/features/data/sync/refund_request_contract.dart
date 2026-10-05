import 'dart:convert';

/// Local outbox metadata; never included in the HTTP JSON body.
const refundRequestJsonKey = '_refund_request_json';

Map<String, dynamic> refundHttpBody(Map<String, dynamic> payload) {
  final body = Map<String, dynamic>.from(payload)
    ..remove('return_access_key')
    ..remove('refund_access_key')
    ..remove(refundRequestJsonKey);
  if ((body['sale_id'] ?? '').toString().trim().isEmpty &&
      (body['client_sale_id'] ?? '').toString().trim().isEmpty) {
    body.remove('sale_id');
    body.remove('client_sale_id');
    body.remove('account_id');
    if (body['items'] is List) {
      body['items'] = (body['items'] as List).map((item) {
        final line = Map<String, dynamic>.from(item as Map);
        line.remove('sale_item_id');
        return line;
      }).toList();
    }
  }
  return body;
}

String refundRequestJson(Map<String, dynamic> payload) =>
    payload[refundRequestJsonKey] as String? ??
    jsonEncode(refundHttpBody(payload));

void validateRefundWithoutSale({
  required num totalAmount,
  required String paymentMethod,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> payments,
  String? reasonCode,
  String? inventoryAction,
}) {
  if (!{'cash', 'card', 'mixed', 'debt', 'bank_transfer'}
      .contains(paymentMethod)) {
    throw ArgumentError('Недопустимый способ выплаты возврата');
  }
  if (items.isEmpty || payments.isEmpty) {
    throw ArgumentError('Добавьте товары и выплаты для возврата');
  }
  if (paymentMethod == 'mixed' && payments.length < 2) {
    throw ArgumentError('Для смешанной выплаты выберите минимум два платежа');
  }
  if (reasonCode != null &&
      reasonCode.isNotEmpty &&
      !{
        'customer_changed_mind',
        'defective',
        'damaged',
        'expired',
        'wrong_item',
        'incorrect_quantity',
        'incorrect_price',
        'duplicate_sale',
        'other',
      }.contains(reasonCode)) {
    throw ArgumentError('Недопустимая причина возврата');
  }
  if (inventoryAction != null &&
      !{
        'return_to_stock',
        'write_off',
        'reverse_sale',
        'amount_correction',
      }.contains(inventoryAction)) {
    throw ArgumentError('Недопустимое действие с остатками');
  }
  final totalCents = _scaled(totalAmount, 100, 'total_amount');
  if (totalCents < 100 || totalCents > 99999999899) {
    throw ArgumentError('Сумма возврата должна быть от 1 до 999999998.99');
  }
  var lineThousandthsOfCent = 0;
  for (final item in items) {
    if ((item['product_id'] ?? '').toString().trim().isEmpty) {
      throw ArgumentError('Не указан товар возврата');
    }
    final price = _scaled(item['price'], 100, 'price');
    final quantity = _scaled(item['quantity'], 1000, 'quantity');
    if (price < 0 || quantity <= 0) {
      throw ArgumentError('Проверьте цену и количество товара');
    }
    lineThousandthsOfCent += price * quantity;
  }
  final itemCents = (lineThousandthsOfCent / 1000).round();
  var paymentCents = 0;
  for (final payment in payments) {
    if ((payment['account_id'] ?? '').toString().trim().isEmpty ||
        (payment['client_payment_id'] ?? '').toString().trim().isEmpty) {
      throw ArgumentError('Не указан счёт или идентификатор выплаты');
    }
    final amount = _scaled(payment['amount'], 100, 'payment.amount');
    if (amount < 1) {
      throw ArgumentError('Каждая выплата должна быть не меньше 0.01');
    }
    paymentCents += amount;
  }
  if (itemCents != totalCents || paymentCents != totalCents) {
    throw ArgumentError(
        'Сумма возврата должна совпадать с суммой товаров и выплат');
  }
}

int _scaled(Object? raw, int scale, String field) {
  final value = raw is num ? raw : num.tryParse('$raw');
  if (value == null ||
      !value.isFinite ||
      (value * scale - (value * scale).round()).abs() > 0.000001) {
    throw ArgumentError('Некорректное значение или точность поля $field');
  }
  return (value * scale).round();
}

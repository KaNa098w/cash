import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/service/kaspi_account_binding.dart';
import 'package:leemon_app/core/service/kaspi_payment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final payments = <Map<String, dynamic>>[
    {
      'account_id': 'cash',
      'amount': 100,
      'account': {'type': 'CASH', 'name': 'Kaspi'}
    },
    {
      'account_id': 'selected',
      'amount': 300,
      'account': {'type': 'BANK', 'name': 'Расчётный'}
    },
    {
      'account_id': 'other',
      'amount': 500,
      'account': {'type': 'BANK', 'name': 'Kaspi'}
    },
  ];

  test('existing registered terminals remain disabled without explicit opt-in',
      () async {
    SharedPreferences.setMockInitialValues(
        {'kaspi.connection': '{"host":"192.168.18.208"}'});
    final binding = await KaspiAccountBinding.load();
    expect(binding.enabled, isFalse);
    expect(binding.accountId, isNull);
    expect(binding.amountFor(payments), 0);
    expect(kaspiPaymentAmount(payments), 0);
  });

  test('saved binding survives reload and selects only its exact bank ID',
      () async {
    await const KaspiAccountBinding(enabled: true, accountId: 'selected')
        .save();
    final binding = await KaspiAccountBinding.load();
    expect(binding.enabled, isTrue);
    expect(binding.accountId, 'selected');
    expect(binding.amountFor(payments), 300);
    expect(binding.amountFor([payments.last]), 0);
  });

  test('disabling a saved account stops routing without deleting the choice',
      () async {
    await const KaspiAccountBinding(enabled: true, accountId: 'selected')
        .save();
    await const KaspiAccountBinding(accountId: 'selected').save();
    final binding = await KaspiAccountBinding.load();
    expect(binding.accountId, 'selected');
    expect(binding.enabled, isFalse);
    expect(binding.amountFor(payments), 0);
  });

  test('cash cannot route even if its ID is accidentally bound', () {
    expect(
        const KaspiAccountBinding(enabled: true, accountId: 'cash')
            .amountFor(payments),
        0);
  });

  test(
      'unstarted frozen checkout obeys disabled setting, pending operations retain original amount',
      () async {
    final checkout = <String, dynamic>{'kaspi_required': true};
    expect(
        await resolveKaspiCheckoutAmount(
            payments: payments,
            saleId: 'sale',
            cashless: true,
            checkout: checkout),
        0);
    final prefs = await SharedPreferences.getInstance();
    for (final status in ['starting', 'wait', 'success']) {
      await prefs.setString(
          'kaspi.payment.sale', jsonEncode({'status': status, 'amount': 700}));
      expect(
          await resolveKaspiCheckoutAmount(
              payments: payments,
              saleId: 'sale',
              cashless: true,
              checkout: checkout),
          700);
    }
    await prefs.setString(
        'kaspi.payment.sale', jsonEncode({'status': 'fail', 'amount': 700}));
    expect(
        await resolveKaspiCheckoutAmount(
            payments: payments,
            saleId: 'sale',
            cashless: true,
            checkout: checkout),
        0);
  });

  test('enabling binding never retroactively charges an old manual checkout',
      () async {
    await const KaspiAccountBinding(enabled: true, accountId: 'selected')
        .save();
    expect(
        await resolveKaspiCheckoutAmount(
            payments: payments, saleId: 'sale', cashless: true),
        300);
    expect(
        await resolveKaspiCheckoutAmount(
            payments: payments, saleId: 'sale', cashless: true, checkout: {}),
        0);
    expect(
        await resolveKaspiCheckoutAmount(
            payments: payments, saleId: 'sale', cashless: false),
        0);
  });

  test(
      'enabled setting requires an explicit account and pending payments block changes',
      () async {
    await expectLater(const KaspiAccountBinding(enabled: true).save(),
        throwsA(isA<KaspiPaymentException>()));
    await const KaspiAccountBinding(enabled: true, accountId: 'selected')
        .save();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KaspiPaymentService.activeKey, 'pending-sale');
    await expectLater(const KaspiAccountBinding(accountId: 'other').save(),
        throwsA(isA<KaspiPaymentException>()));
    expect((await KaspiAccountBinding.load()).accountId, 'selected');
    expect((await KaspiAccountBinding.load()).enabled, isTrue);
  });
}

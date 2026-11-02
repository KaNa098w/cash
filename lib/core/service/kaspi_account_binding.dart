import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'kaspi_payment_service.dart';

/// Device-local opt-in. Existing terminal registrations do not enable routing.
class KaspiAccountBinding {
  const KaspiAccountBinding({this.enabled = false, this.accountId});
  final bool enabled;
  final String? accountId;
  static const storageKey = 'kaspi.accountBinding';

  static Future<KaspiAccountBinding> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return const KaspiAccountBinding();
    final data = Map<String, dynamic>.from(jsonDecode(raw));
    return KaspiAccountBinding(
        enabled: data['enabled'] == true,
        accountId: data['accountId'] as String?);
  }

  Future<void> save() async {
    if (enabled && (accountId ?? '').trim().isEmpty) {
      throw const KaspiPaymentException(
          'Выберите банковский счёт для терминала');
    }
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString(KaspiPaymentService.activeKey) ?? '').isNotEmpty) {
      throw const KaspiPaymentException(
          'Сначала завершите сохранённую оплату Kaspi, затем измените привязку счёта');
    }
    if (!await prefs.setString(
        storageKey,
        jsonEncode({
          'enabled': enabled,
          'accountId': accountId,
        }))) {
      throw const KaspiPaymentException('Не удалось сохранить привязку счёта');
    }
  }

  double amountFor(List<Map<String, dynamic>> payments) =>
      enabled ? kaspiPaymentAmount(payments, accountId: accountId) : 0;
}

Future<double> resolveKaspiCheckoutAmount({
  required List<Map<String, dynamic>> payments,
  required String saleId,
  required bool cashless,
  Map<String, dynamic>? checkout,
}) async {
  if (!cashless) return 0;
  if (checkout != null) {
    if (checkout['kaspi_required'] != true) return 0;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('kaspi.payment.$saleId');
    if (raw != null) {
      final record = Map<String, dynamic>.from(jsonDecode(raw));
      if (record['status'] != 'fail' && record['amount'] is num) {
        // Reconcile the operation actually recorded before the network call.
        // An unstarted checkout still obeys the current enabled/account choice.
        return (record['amount'] as num).toDouble();
      }
    }
  }
  return (await KaspiAccountBinding.load()).amountFor(payments);
}

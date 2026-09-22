import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

/// Persists the whole confirmation before sending, including its timestamp.
class InvoicePaymentStore {
  String _key(String scope, String id) =>
      'invoice_payment_v1:${Uri.encodeComponent(scope)}:$id';
  Future<Map<String, dynamic>?> read(String scope, String invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key(scope, invoiceId));
    return saved == null ? null : Map<String, dynamic>.from(jsonDecode(saved));
  }

  Future<Map<String, dynamic>> prepare(
      {required String scope,
      required String invoiceId,
      required String sessionId,
      required String userId,
      required String comment,
      required DateTime date}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(scope, invoiceId);
    final saved = prefs.getString(key);
    if (saved != null) return Map<String, dynamic>.from(jsonDecode(saved));
    final payload = <String, dynamic>{
      'date': DateFormat('yyyy-MM-dd HH:mm:ss').format(date),
      'pos_session_id': sessionId,
      'user_id': userId,
      'client_payment_id': const Uuid().v4(),
      'comment': comment,
    };
    if (!await prefs.setString(key, jsonEncode(payload))) {
      throw StateError(
          'Не удалось сохранить подтверждение оплаты на устройстве');
    }
    return payload;
  }

  Future<void> clear(String scope, String invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(scope, invoiceId));
  }
}

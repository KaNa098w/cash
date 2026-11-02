import 'package:shared_preferences/shared_preferences.dart';

class CashDrawerSettings {
  const CashDrawerSettings(
      {this.enabled = true,
      this.printerName,
      this.pin = 0,
      this.pulseMs = 100});
  final bool enabled;
  final String? printerName;
  final int pin;
  final int pulseMs;

  static Future<CashDrawerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final pulse = prefs.getInt('cashDrawer.pulseMs') ?? 100;
    return CashDrawerSettings(
      enabled: prefs.getBool('receiptPrint.openDrawerOnCashSale') ?? true,
      printerName: prefs.getString('cashDrawer.printerName'),
      pin: prefs.getInt('receiptPrint.drawerPin') == 1 ? 1 : 0,
      pulseMs: const [50, 100, 120].contains(pulse) ? pulse : 100,
    );
  }

  Future<void> save() async {
    if (pin != 0 && pin != 1 || !const [50, 100, 120].contains(pulseMs)) {
      throw ArgumentError('Некорректные параметры денежного ящика');
    }
    final prefs = await SharedPreferences.getInstance();
    final name = printerName?.trim() ?? '';
    if (name.isEmpty) {
      await prefs.remove('cashDrawer.printerName');
    } else if (!await prefs.setString('cashDrawer.printerName', name)) {
      throw StateError('Не удалось сохранить принтер ящика');
    }
    if (!await prefs.setBool('receiptPrint.openDrawerOnCashSale', enabled) ||
        !await prefs.setInt('receiptPrint.drawerPin', pin) ||
        !await prefs.setInt('cashDrawer.pulseMs', pulseMs)) {
      throw StateError('Не удалось сохранить настройки денежного ящика');
    }
  }
}

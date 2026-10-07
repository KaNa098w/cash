import 'package:shared_preferences/shared_preferences.dart';

/// Device-local settings shared by every receipt printing entry point.
class ReceiptPrinterSettings {
  const ReceiptPrinterSettings({
    this.localLengthMm = 200,
    this.fiscalLengthMm = 200,
    this.fixedLength = false,
    this.usePrinterSettings = false,
    this.leftMarginMm = 0,
    this.rightMarginMm = 8.5,
    this.topMarginMm = 4.2,
    this.bottomMarginMm = 4.2,
    this.feedMm = 35,
  });

  final double localLengthMm, fiscalLengthMm;
  final bool fixedLength, usePrinterSettings;
  final double leftMarginMm, rightMarginMm, topMarginMm, bottomMarginMm, feedMm;

  static double _number(SharedPreferences p, String key, double fallback,
      double min, double max) {
    final value = p.getDouble('receiptPrint.$key') ?? fallback;
    return value.isFinite ? value.clamp(min, max).toDouble() : fallback;
  }

  static Future<ReceiptPrinterSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ReceiptPrinterSettings(
      localLengthMm: _number(p, 'localLength', 200, 80, 500),
      fiscalLengthMm: _number(p, 'fiscalLength', 200, 80, 500),
      fixedLength: p.getBool('receiptPrint.fixedLength') ?? false,
      usePrinterSettings: p.getBool('receiptPrint.driverSettings') ?? false,
      leftMarginMm: _number(p, 'left', 0, 0, 10),
      rightMarginMm: _number(p, 'right', 8.5, 0, 15),
      topMarginMm: _number(p, 'top', 4.2, 0, 15),
      bottomMarginMm: _number(p, 'bottom', 4.2, 0, 15),
      feedMm: _number(p, 'feed', 35, 0, 50),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    for (final entry in {
      'localLength': localLengthMm,
      'fiscalLength': fiscalLengthMm,
      'left': leftMarginMm,
      'right': rightMarginMm,
      'top': topMarginMm,
      'bottom': bottomMarginMm,
      'feed': feedMm,
    }.entries) {
      await p.setDouble('receiptPrint.${entry.key}', entry.value);
    }
    await p.setBool('receiptPrint.fixedLength', fixedLength);
    await p.setBool('receiptPrint.driverSettings', usePrinterSettings);
  }
}

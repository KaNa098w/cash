import 'dart:ffi';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';
import 'cash_drawer_settings.dart';

typedef DrawerWriter = Future<void> Function(String printer, List<int> command);

/// ESC/POS ESC p: pin 2, 100 ms ON, 500 ms OFF. No receipt is printed.
const cashDrawerOpenCommand = <int>[0x1b, 0x70, 0, 50, 250];

class CashDrawerService {
  CashDrawerService({DrawerWriter? writer})
      : _writer = writer ?? _writeInWorker;
  static final instance = CashDrawerService();
  final DrawerWriter _writer;
  final _sending = <String>{};
  final _opened = <String>{};
  final List<String> diagnostics = [];

  void record(String message) {
    diagnostics.add('${DateTime.now().toLocal().toIso8601String()} $message');
    if (diagnostics.length > 30) diagnostics.removeAt(0);
  }

  Future<bool> openAfterSale({
    required String saleId,
    required String paymentMethod,
    required String? printerName,
  }) async {
    if (!const {'cash', 'mixed'}.contains(paymentMethod.trim().toLowerCase()) ||
        saleId.isEmpty ||
        _sending.contains(saleId) ||
        _opened.contains(saleId)) {
      return false;
    }
    _sending.add(saleId);
    try {
      final settings = await CashDrawerSettings.load();
      if (!settings.enabled) {
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('cashDrawer.openedSales') ?? [];
      if (history.contains(saleId)) return false;
      await open(
          printerName: settings.printerName ?? printerName,
          pin: settings.pin,
          pulseMs: settings.pulseMs);
      _opened.add(saleId);
      if (_opened.length > 100) _opened.remove(_opened.first);
      final next = [...history, saleId];
      await prefs.setStringList('cashDrawer.openedSales',
          next.length > 100 ? next.sublist(next.length - 100) : next);
      return true;
    } finally {
      _sending.remove(saleId);
    }
  }

  Future<void> open(
      {required String? printerName, int pin = 0, int pulseMs = 100}) async {
    final name = printerName?.trim() ?? '';
    if (name.isEmpty) {
      throw StateError('Выберите чековый принтер для открытия ящика');
    }
    if (pin != 0 && pin != 1) throw ArgumentError.value(pin, 'pin');
    if (!const [50, 100, 120].contains(pulseMs)) {
      throw ArgumentError.value(pulseMs, 'pulseMs');
    }
    try {
      await _writer(name, [27, 112, pin, pulseMs ~/ 2, 250]);
      record('Команда передана: $name; выход ${pin + 1}; импульс $pulseMs мс.');
    } catch (error) {
      record('Ошибка открытия: $error');
      rethrow;
    }
  }

  Future<String> diagnose(String? printerName) async {
    if (!Platform.isWindows) {
      return 'Диагностика подключения доступна в Windows.';
    }
    if ((printerName ?? '').trim().isEmpty) return 'Принтер не выбран.';
    final result = await Process.run(
            'powershell.exe',
            [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); '
                  r'$p=Get-Printer | Where-Object {$_.Name -eq $env:LEEMON_DRAWER_PRINTER}; '
                  r'if (-not $p) { throw "Printer not found" }; '
                  r'$port=Get-PrinterPort | Where-Object {$_.Name -eq $p.PortName}; '
                  r'[pscustomobject]@{Name=$p.Name;Driver=$p.DriverName;Port=$p.PortName;'
                  r'Status=[string]$p.PrinterStatus;Address=$port.PrinterHostAddress;'
                  r'Jobs=@(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue).Count} | ConvertTo-Json -Compress'
            ],
            environment: {'LEEMON_DRAWER_PRINTER': printerName!},
            stdoutEncoding: utf8,
            stderrEncoding: utf8)
        .timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      throw StateError(
          'Не удалось прочитать состояние принтера. Обновите список и проверьте его подключение.');
    }
    final data = jsonDecode(result.stdout.toString()) as Map;
    final report = 'Принтер: ${data['Name']}\nДрайвер: ${data['Driver']}\n'
        'Порт: ${data['Port']}\nСостояние Windows: ${data['Status']}\n'
        '${(data['Address'] ?? '').toString().isEmpty ? '' : 'IP: ${data['Address']}\n'}'
        'Заданий в очереди: ${data['Jobs']}\n'
        'Физическое открытие проверяется кнопкой «Открыть ящик — тест».';
    record('Диагностика: ${data['Name']}; ${data['Port']}; ${data['Status']}.');
    return report;
  }
}

Future<void> _writeInWorker(String printer, List<int> command) =>
    Isolate.run(() => _writeRaw(printer, command));

void _writeRaw(String printer, List<int> command) {
  if (!Platform.isWindows) {
    throw UnsupportedError('Открытие денежного ящика поддерживается в Windows');
  }
  final name = printer.toNativeUtf16();
  final handle = calloc<IntPtr>();
  final info = calloc<DOC_INFO_1>();
  final document = 'Leemon cash drawer'.toNativeUtf16();
  final type = 'RAW'.toNativeUtf16();
  final data = calloc<Uint8>(command.length);
  final written = calloc<Uint32>();
  var opened = false;
  var started = false;
  var completed = false;
  try {
    if (OpenPrinter(name, handle, nullptr) == 0) {
      throw StateError(
          'Не удалось открыть принтер «$printer»: ${GetLastError()}');
    }
    opened = true;
    info.ref
      ..pDocName = document
      ..pOutputFile = nullptr
      ..pDatatype = type;
    if (StartDocPrinter(handle.value, 1, info) == 0) {
      throw StateError('Не удалось создать команду ящика: ${GetLastError()}');
    }
    started = true;
    if (StartPagePrinter(handle.value) == 0) {
      throw StateError('Принтер не принял команду ящика: ${GetLastError()}');
    }
    data.asTypedList(command.length).setAll(0, command);
    if (WritePrinter(handle.value, data, command.length, written) == 0 ||
        written.value != command.length) {
      throw StateError('Не удалось отправить команду ящика: ${GetLastError()}');
    }
    if (EndPagePrinter(handle.value) == 0) {
      throw StateError('Не удалось завершить команду ящика: ${GetLastError()}');
    }
    if (EndDocPrinter(handle.value) == 0) {
      throw StateError('Не удалось передать команду ящика: ${GetLastError()}');
    }
    completed = true;
  } finally {
    if (started && !completed) AbortPrinter(handle.value);
    if (opened) ClosePrinter(handle.value);
    calloc.free(name);
    calloc.free(handle);
    calloc.free(info);
    calloc.free(document);
    calloc.free(type);
    calloc.free(data);
    calloc.free(written);
  }
}

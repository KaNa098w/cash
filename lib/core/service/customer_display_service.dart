import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';

enum CustomerDisplayProtocol { epson, ascii, asciiLine }

class CustomerDisplaySettings {
  const CustomerDisplaySettings(
      {this.enabled = false,
      this.port = '',
      this.baudRate = 9600,
      this.columns = 8,
      this.protocol = CustomerDisplayProtocol.asciiLine});
  final bool enabled;
  final String port;
  final int baudRate;
  final int columns;
  final CustomerDisplayProtocol protocol;

  static Future<CustomerDisplaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CustomerDisplaySettings(
      enabled: prefs.getBool('customer_display_enabled') ?? false,
      port: prefs.getString('customer_display_port') ?? '',
      baudRate: prefs.getInt('customer_display_baud') ?? 9600,
      columns: prefs.getInt('customer_display_columns') ?? 8,
      protocol: CustomerDisplayProtocol.values.firstWhere(
          (p) => p.name == prefs.getString('customer_display_protocol'),
          orElse: () => CustomerDisplayProtocol.asciiLine),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('customer_display_enabled', enabled);
    await prefs.setString('customer_display_port', port);
    await prefs.setInt('customer_display_baud', baudRate);
    await prefs.setInt('customer_display_columns', columns);
    await prefs.setString('customer_display_protocol', protocol.name);
  }
}

List<int> customerDisplayBytes(CustomerDisplaySettings settings, double total) {
  if (!total.isFinite || total < 0) throw ArgumentError('Некорректная сумма');
  final amount = total.toStringAsFixed(2);
  if (amount.length > settings.columns) {
    throw StateError(
        'Сумма $amount не помещается в ${settings.columns} символов');
  }
  if (settings.protocol == CustomerDisplayProtocol.asciiLine) {
    return ascii.encode('$amount\r\n');
  }
  final text = ascii.encode(amount.padLeft(settings.columns));
  // Epson customer display CLR (0C), HOM (0B). ASCII mode uses CR only.
  return settings.protocol == CustomerDisplayProtocol.epson
      ? [0x0c, 0x0b, ...text]
      : [0x0d, ...text, 0x0d];
}

typedef CustomerDisplayWriter = Future<void> Function(
    CustomerDisplaySettings settings, List<int> bytes);

class CustomerDisplayService extends ChangeNotifier {
  CustomerDisplayService({CustomerDisplayWriter? writer})
      : _writer = writer ?? _writeInWorker;
  final CustomerDisplayWriter _writer;
  CustomerDisplaySettings settings = const CustomerDisplaySettings();
  double total = 0;
  String? error;
  String? lastSent;
  DateTime? sentAt;
  bool sending = false;
  bool _disposed = false;
  int _revision = 0;
  Timer? _debounce;
  Future<void> _queue = Future<void>.value();

  Future<void> initialize() async {
    try {
      settings = await CustomerDisplaySettings.load();
      if (_disposed) return;
      _schedule();
    } catch (e) {
      error = 'Не удалось загрузить настройки: $e';
    }
    if (!_disposed) notifyListeners();
  }

  void updateTotal(double value) {
    if (_disposed || value == total) return;
    total = value;
    _schedule();
    notifyListeners();
  }

  Future<void> configure(CustomerDisplaySettings next) async {
    if (next.enabled && next.port.isEmpty) {
      throw StateError('Выберите порт дисплея покупателя');
    }
    await next.save();
    if (_disposed) return;
    final previous = settings;
    settings = next;
    error = null;
    _schedule();
    if (previous.enabled &&
        previous.port.isNotEmpty &&
        (!next.enabled || previous.port != next.port)) {
      await _enqueue(() async {
        try {
          await _send(previous, 0);
        } catch (e) {
          error = 'Не удалось сбросить прежний дисплей: $e';
        }
      });
    }
    if (!_disposed) notifyListeners();
  }

  void _schedule() {
    _debounce?.cancel();
    final revision = ++_revision;
    if (!settings.enabled || _disposed) return;
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _enqueue(() async {
        if (_disposed || revision != _revision || !settings.enabled) return;
        sending = true;
        notifyListeners();
        try {
          await _send(settings, total);
          error = null;
        } catch (e) {
          error = e.toString();
        } finally {
          sending = false;
          if (!_disposed) notifyListeners();
        }
      });
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _send(CustomerDisplaySettings config, double value) async {
    if (_disposed) return;
    if (config.port.isEmpty) throw StateError('Порт не выбран');
    await _writer(config, customerDisplayBytes(config, value));
    if (_disposed) return;
    lastSent = value.toStringAsFixed(2);
    sentAt = DateTime.now();
  }

  Future<void> test(CustomerDisplaySettings config, double value) =>
      _enqueue(() async {
        try {
          await _send(config, value);
          await Future<void>.delayed(const Duration(seconds: 2));
        } finally {
          // Restore the latest basket value, including changes during the test.
          await _send(config,
              settings.enabled && settings.port == config.port ? total : 0);
        }
        if (!_disposed) notifyListeners();
      });

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _debounce?.cancel();
    super.dispose();
  }
}

Future<void> _writeInWorker(
        CustomerDisplaySettings settings, List<int> bytes) =>
    Isolate.run(() => _writeSerial(settings, bytes));

Future<void> _writeSerial(
    CustomerDisplaySettings settings, List<int> bytes) async {
  if (Platform.isMacOS || Platform.isLinux) {
    final result = await Process.run('stty', [
      Platform.isMacOS ? '-f' : '-F',
      settings.port,
      '${settings.baudRate}',
      'cs8',
      '-cstopb',
      '-parenb',
      'raw',
      '-echo',
      '-ixon',
      '-ixoff'
    ]);
    if (result.exitCode != 0) {
      throw StateError('Настройка порта: ${result.stderr}');
    }
    final port = await File(settings.port).open(mode: FileMode.writeOnlyAppend);
    try {
      await port.writeFrom(bytes);
    } finally {
      await port.close();
    }
    return;
  }
  if (!Platform.isWindows) {
    throw UnsupportedError('Платформа не поддерживается');
  }
  final path = '\\\\.\\${settings.port}'.toNativeUtf16();
  final definition =
      'baud=${settings.baudRate} parity=N data=8 stop=1'.toNativeUtf16();
  final dcb = calloc<DCB>();
  final timeouts = calloc<COMMTIMEOUTS>();
  final buffer = calloc<Uint8>(bytes.length);
  final written = calloc<Uint32>();
  var handle = INVALID_HANDLE_VALUE;
  try {
    handle = CreateFile(
        path,
        GENERIC_ACCESS_RIGHTS.GENERIC_READ |
            GENERIC_ACCESS_RIGHTS.GENERIC_WRITE,
        0,
        nullptr,
        FILE_CREATION_DISPOSITION.OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_NORMAL,
        0);
    if (handle == INVALID_HANDLE_VALUE) {
      throw StateError(
          'Не удалось открыть ${settings.port} (Windows ${GetLastError()}). Порт занят или недоступен.');
    }
    dcb.ref.DCBlength = sizeOf<DCB>();
    if (BuildCommDCB(definition, dcb) == 0 || SetCommState(handle, dcb) == 0) {
      throw StateError('Не удалось настроить порт (Windows ${GetLastError()})');
    }
    timeouts.ref.WriteTotalTimeoutConstant = 1000;
    if (SetCommTimeouts(handle, timeouts) == 0) {
      throw StateError('Не удалось задать тайм-аут порта');
    }
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    if (WriteFile(handle, buffer, bytes.length, written, nullptr) == 0 ||
        written.value != bytes.length) {
      throw StateError(
          'Сумма не отправлена полностью (Windows ${GetLastError()})');
    }
  } finally {
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    calloc.free(path);
    calloc.free(definition);
    calloc.free(dcb);
    calloc.free(timeouts);
    calloc.free(buffer);
    calloc.free(written);
  }
}

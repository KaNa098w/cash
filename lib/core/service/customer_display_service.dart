import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class CustomerDisplayService {
  CustomerDisplayService({
    this.portName = 'COM2',
    this.baudRate = 9600,
  });

  final String portName;
  final int baudRate;

  String? _lastText;
  Future<void> _pending = Future<void>.value();

  void showTotal(num total) {
    if (!Platform.isWindows) return;

    final amount = total.isFinite ? total.round() : 0;
    final text = amount < 0 ? '0' : amount.toString();
    if (_lastText == text) return;
    _lastText = text;

    _pending = _pending.then((_) => _writeText(text)).catchError((_) {});
  }

  Future<void> _writeText(String text) async {
    final targetPortName = portName;
    final targetBaudRate = baudRate;
    final payload = '$text\r\n';
    await Isolate.run(
      () => _writeSerialMessage(
        portName: targetPortName,
        baudRate: targetBaudRate,
        text: payload,
      ),
    ).timeout(const Duration(seconds: 2));
  }

  static void _writeSerialMessage({
    required String portName,
    required int baudRate,
    required String text,
  }) {
    final portPath = _windowsPortPath(portName);
    final portPathPtr = portPath.toNativeUtf16();
    final dcb = calloc<DCB>();
    final timeouts = calloc<COMMTIMEOUTS>();
    final bytesWritten = calloc<Uint32>();
    Pointer<Uint8>? buffer;
    var handle = INVALID_HANDLE_VALUE;

    try {
      handle = CreateFile(
        portPathPtr,
        GENERIC_ACCESS_RIGHTS.GENERIC_WRITE,
        0,
        nullptr,
        FILE_CREATION_DISPOSITION.OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_NORMAL,
        0,
      );
      if (handle == INVALID_HANDLE_VALUE) return;

      final dcbDef = 'baud=$baudRate parity=N data=8 stop=1'.toNativeUtf16();
      try {
        dcb.ref.DCBlength = sizeOf<DCB>();
        if (BuildCommDCB(dcbDef, dcb) == 0) return;
        if (SetCommState(handle, dcb) == 0) return;
      } finally {
        calloc.free(dcbDef);
      }

      timeouts.ref.WriteTotalTimeoutConstant = 500;
      timeouts.ref.WriteTotalTimeoutMultiplier = 10;
      SetCommTimeouts(handle, timeouts);

      final bytes = ascii.encode(text);
      buffer = calloc<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);

      WriteFile(handle, buffer, bytes.length, bytesWritten, nullptr);
    } catch (_) {
      // Customer display is optional: a missing/locked COM port must not block POS.
    } finally {
      if (handle != INVALID_HANDLE_VALUE) {
        CloseHandle(handle);
      }
      if (buffer != null) {
        calloc.free(buffer);
      }
      calloc.free(bytesWritten);
      calloc.free(timeouts);
      calloc.free(dcb);
      calloc.free(portPathPtr);
    }
  }

  static String _windowsPortPath(String port) {
    final trimmed = port.trim();
    if (trimmed.startsWith(r'\\.\')) return trimmed;
    return '\\\\.\\$trimmed';
  }
}

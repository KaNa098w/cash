import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScaleProtocol { auto, cas, pos2, continuous }

class ScaleHardwareDiagnostics {
  const ScaleHardwareDiagnostics({
    required this.ports,
    required this.usbSerialAdapter,
  });

  final List<String> ports;
  final String? usbSerialAdapter;

  bool get needsDriver => usbSerialAdapter != null && ports.isEmpty;
}

class ScaleSettings {
  const ScaleSettings({
    this.enabled = true,
    this.port = '',
    this.baudRate = 9600,
    this.protocol = ScaleProtocol.auto,
  });

  final bool enabled;
  final String port;
  final int baudRate;
  final ScaleProtocol protocol;

  static Future<ScaleSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('scale_protocol') ?? 'auto';
    return ScaleSettings(
      enabled: prefs.getBool('scale_enabled') ?? true,
      port: prefs.getString('scale_port') ?? '',
      baudRate: prefs.getInt('scale_baud_rate') ?? 9600,
      protocol: ScaleProtocol.values.firstWhere(
        (value) => value.name == name,
        orElse: () => ScaleProtocol.auto,
      ),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scale_enabled', enabled);
    await prefs.setString('scale_port', port);
    await prefs.setInt('scale_baud_rate', baudRate);
    await prefs.setString('scale_protocol', protocol.name);
  }
}

class ScaleReading {
  const ScaleReading({
    required this.grams,
    required this.portName,
    required this.receivedAt,
  });

  final double grams;
  final String portName;
  final DateTime receivedAt;
}

class ScaleConnection {
  ScaleConnection._(this.readings, this.errors);

  final Stream<ScaleReading> readings;
  final Stream<String> errors;
  Isolate? _isolate;
  SendPort? _controlPort;
  bool _closeRequested = false;

  void _attachIsolate(Isolate isolate) => _isolate = isolate;

  void _attachControlPort(SendPort port) {
    _controlPort = port;
    if (_closeRequested) port.send('stop');
  }

  /// Stops serial polling cooperatively. The worker leaves ReadFile, closes
  /// the Windows handle in finally and only then exits the isolate.
  void close() {
    _closeRequested = true;
    _controlPort?.send('stop');
  }

  void forceShutdown() => _isolate?.kill(priority: Isolate.immediate);
}

/// Reads POS scales over a serial port on Windows and macOS.
class ScaleService {
  const ScaleService({
    this.baudRate = 9600,
    this.portCandidates = const [],
    this.protocol = ScaleProtocol.auto,
  });

  final int baudRate;
  final List<String> portCandidates;
  final ScaleProtocol protocol;

  static Future<ScaleHardwareDiagnostics> diagnoseHardware() async {
    final ports = await availablePorts();
    if (!Platform.isMacOS) {
      return ScaleHardwareDiagnostics(ports: ports, usbSerialAdapter: null);
    }
    try {
      final result =
          await Process.run('ioreg', ['-p', 'IOUSB', '-l', '-w', '0']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final matches = RegExp(r'"USB Product Name"\s*=\s*"([^"]+)"')
            .allMatches(output)
            .map((match) => match.group(1)!)
            .where((name) => RegExp(r'serial|uart|rs.?232|prolific|pl2303',
                    caseSensitive: false)
                .hasMatch(name))
            .toList();
        return ScaleHardwareDiagnostics(
          ports: ports,
          usbSerialAdapter: matches.isEmpty ? null : matches.first,
        );
      }
    } catch (_) {}
    return ScaleHardwareDiagnostics(ports: ports, usbSerialAdapter: null);
  }

  static Future<List<String>> availablePorts() async {
    if (Platform.isMacOS) return _macScalePorts();
    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          r'[System.IO.Ports.SerialPort]::GetPortNames() -join "`n"',
        ]);
        if (result.exitCode == 0) {
          final ports = result.stdout
              .toString()
              .trim()
              .split(RegExp(r'\s+'))
              .where((port) =>
                  RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(port))
              .toList();
          ports.sort();
          return ports;
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<ScaleConnection> connect() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      return ScaleConnection._(
        const Stream<ScaleReading>.empty(),
        Stream<String>.value('Весы недоступны на этой платформе'),
      );
    }

    final receivePort = ReceivePort();
    final readingController = StreamController<ScaleReading>();
    final errorController = StreamController<String>();
    final connection = ScaleConnection._(
      readingController.stream,
      errorController.stream,
    );
    final isolate = await Isolate.spawn(
      _scaleReaderEntry,
      <Object>[receivePort.sendPort, baudRate, portCandidates, protocol.index],
      debugName: 'pos-scale-reader',
    );
    connection._attachIsolate(isolate);

    receivePort.listen((message) {
      if (message is! Map) return;
      if (message['control'] case final SendPort controlPort) {
        connection._attachControlPort(controlPort);
        return;
      }
      if (message['error'] case final String error) {
        errorController.add(error);
        return;
      }
      final grams = message['grams'];
      final port = message['port'];
      if (grams is num && port is String) {
        readingController.add(ScaleReading(
          grams: grams.toDouble(),
          portName: port,
          receivedAt: DateTime.now(),
        ));
      }
    });

    return connection;
  }
}

Future<void> _scaleReaderEntry(List<Object> args) async {
  final sendPort = args[0] as SendPort;
  final baudRate = args[1] as int;
  final protocol = ScaleProtocol.values[args[3] as int];
  final configuredPorts = (args[2] as List).cast<String>();
  final ports = configuredPorts.isNotEmpty
      ? configuredPorts
      : Platform.isMacOS
          ? _macScalePorts()
          : const ['COM8'];
  final controlPort = ReceivePort();
  var stopping = false;
  controlPort.listen((message) {
    if (message == 'stop') stopping = true;
  });
  sendPort.send({'control': controlPort.sendPort});

  if (Platform.isMacOS && ports.isEmpty) {
    sendPort.send({
      'error': 'Mac не видит последовательный USB-порт весов. '
          'Проверьте кабель, переходник и драйвер USB–RS-232.',
    });
    controlPort.close();
    return;
  }

  for (final port in ports) {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (await (Platform.isMacOS ? _readMacScalePort : _readScalePort)(
        sendPort,
        port,
        baudRate,
        protocol: protocol,
        shouldStop: () => stopping,
      )) {
        controlPort.close();
        return;
      }
      if (stopping) {
        controlPort.close();
        return;
      }
      // The previous weighing dialog may still be completing CloseHandle.
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }
  if (!stopping) {
    sendPort.send({
      'error': Platform.isMacOS
          ? 'Последовательный порт найден, но весы не отвечают. '
              'Проверьте питание, режим обмена и скорость $baudRate бод.'
          : 'Весы не отвечают на ${ports.join(', ')}. '
              'Проверьте питание, режим обмена и скорость $baudRate бод.',
    });
  }
  controlPort.close();
}

List<String> _macScalePorts() {
  try {
    final ports = Directory('/dev')
        .listSync()
        .whereType<FileSystemEntity>()
        .map((entry) => entry.path)
        .where((path) =>
            path.startsWith('/dev/cu.') &&
            !RegExp(r'(Bluetooth|Buds|debug|wlan|Incoming-Port)',
                    caseSensitive: false)
                .hasMatch(path))
        .toList();
    ports.sort();
    return ports;
  } catch (_) {
    return const [];
  }
}

Future<bool> _readMacScalePort(
  SendPort sendPort,
  String portName,
  int baudRate, {
  required ScaleProtocol protocol,
  required bool Function() shouldStop,
}) async {
  RandomAccessFile? port;
  try {
    final setup = await Process.run('stty', [
      '-f',
      portName,
      '$baudRate',
      'cs8',
      '-cstopb',
      '-parenb',
      'raw',
      '-echo',
      'min',
      '0',
      'time',
      '2',
    ]);
    if (setup.exitCode != 0) return false;
    port = await File(portName).open(mode: FileMode.append);
    var pending = <int>[];
    final firstDataTimeout = Stopwatch()..start();
    while (!shouldStop()) {
      // M-ER 328 supports CAS-M and POS2-M request protocols.
      final cas =
          protocol == ScaleProtocol.auto || protocol == ScaleProtocol.cas
              ? await _requestMacCasWeight(port)
              : null;
      if (cas != null) {
        sendPort.send({'grams': cas, 'port': portName});
        firstDataTimeout.reset();
        continue;
      }
      final pos =
          protocol == ScaleProtocol.auto || protocol == ScaleProtocol.pos2
              ? await _requestMacPos2Weight(port)
              : null;
      if (pos != null) {
        sendPort.send({'grams': pos, 'port': portName});
        firstDataTimeout.reset();
        continue;
      }
      final bytes = await port.read(256);
      if (bytes.isNotEmpty) {
        firstDataTimeout.reset();
        pending.addAll(bytes);
        if (pending.length > 1024) {
          pending = pending.sublist(pending.length - 512);
        }
        final reading = _parseScaleWeightBytes(pending);
        if (reading != null) {
          sendPort.send({'grams': reading, 'port': portName});
          pending = <int>[];
        }
      } else if (firstDataTimeout.elapsed > const Duration(seconds: 2)) {
        return false;
      }
      await Future<void>.delayed(Duration.zero);
    }
    return true;
  } catch (_) {
    return port != null;
  } finally {
    await port?.close();
  }
}

Future<double?> _requestMacCasWeight(RandomAccessFile port) async {
  await port.writeFrom(const [0x05]);
  if (!(await port.read(64)).contains(0x06)) return null;
  await port.writeFrom(const [0x11]);
  return _parseCasWeight(await port.read(64));
}

Future<double?> _requestMacPos2Weight(RandomAccessFile port) async {
  await port.writeFrom(const [0x05]);
  if (!(await port.read(64)).contains(0x06)) return null;
  final request = <int>[0x02, 0x05, 0x3A, 0x30, 0x30, 0x33, 0x30];
  var lrc = 0;
  for (final byte in request.skip(1)) {
    lrc ^= byte;
  }
  request.add(lrc);
  await port.writeFrom(request);
  var response = await port.read(64);
  if (response.length == 1 && response.first == 0x06) {
    response = await port.read(64);
  } else if (response.isNotEmpty && response.first == 0x06) {
    response = response.sublist(1);
  }
  final weight = _parsePos2Weight(response);
  if (weight != null) await port.writeFrom(const [0x06]);
  return weight;
}

Future<bool> _readScalePort(
  SendPort sendPort,
  String portName,
  int baudRate, {
  required ScaleProtocol protocol,
  required bool Function() shouldStop,
}) async {
  final path = '\\\\.\\$portName'.toNativeUtf16();
  final dcb = calloc<DCB>();
  final timeouts = calloc<COMMTIMEOUTS>();
  final bytesRead = calloc<Uint32>();
  final bytesWritten = calloc<Uint32>();
  final buffer = calloc<Uint8>(256);
  var handle = INVALID_HANDLE_VALUE;

  try {
    handle = CreateFile(
      path,
      GENERIC_ACCESS_RIGHTS.GENERIC_READ | GENERIC_ACCESS_RIGHTS.GENERIC_WRITE,
      0,
      nullptr,
      FILE_CREATION_DISPOSITION.OPEN_EXISTING,
      FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_NORMAL,
      0,
    );
    if (handle == INVALID_HANDLE_VALUE) return false;

    final definition = 'baud=$baudRate parity=N data=8 stop=1'.toNativeUtf16();
    try {
      dcb.ref.DCBlength = sizeOf<DCB>();
      if (BuildCommDCB(definition, dcb) == 0 ||
          SetCommState(handle, dcb) == 0) {
        return false;
      }
    } finally {
      calloc.free(definition);
    }

    timeouts.ref.ReadIntervalTimeout = 50;
    timeouts.ref.ReadTotalTimeoutConstant = 200;
    timeouts.ref.ReadTotalTimeoutMultiplier = 2;
    if (SetCommTimeouts(handle, timeouts) == 0) return false;

    var pending = <int>[];
    final firstDataTimeout = Stopwatch()..start();
    while (true) {
      // Let the isolate process the cooperative stop message between the
      // short, timeout-bounded native serial reads.
      await Future<void>.delayed(Duration.zero);
      if (shouldStop()) return true;

      // M-ER 328 can work in CAS-M or POS2-M request mode. Try both official
      // handshakes; this also works when the scales were switched in settings.
      final casWeight =
          protocol == ScaleProtocol.auto || protocol == ScaleProtocol.cas
              ? _requestCasWeight(handle, bytesRead, bytesWritten)
              : null;
      if (casWeight != null) {
        sendPort.send({'grams': casWeight, 'port': portName});
        firstDataTimeout.reset();
        continue;
      }

      final posWeight =
          protocol == ScaleProtocol.auto || protocol == ScaleProtocol.pos2
              ? _requestPos2Weight(handle, bytesRead, bytesWritten)
              : null;
      if (posWeight != null) {
        sendPort.send({'grams': posWeight, 'port': portName});
        firstDataTimeout.reset();
        continue;
      }

      // Some firmware is configured for continuous CAS transmission.
      bytesRead.value = 0;
      final ok = ReadFile(handle, buffer, 256, bytesRead, nullptr);
      if (ok == 0) return true;
      final count = bytesRead.value;
      if (count == 0) {
        if (shouldStop()) return true;
        if (firstDataTimeout.elapsed > const Duration(seconds: 2)) {
          return false;
        }
        continue;
      }
      firstDataTimeout.reset();
      pending.addAll(buffer.asTypedList(count));
      if (pending.length > 1024) {
        pending = pending.sublist(pending.length - 512);
      }

      final reading = _parseScaleWeightBytes(pending);
      if (reading != null) {
        sendPort.send({'grams': reading, 'port': portName});
        pending = <int>[];
      }
    }
  } catch (_) {
    return handle != INVALID_HANDLE_VALUE;
  } finally {
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    calloc.free(buffer);
    calloc.free(bytesRead);
    calloc.free(bytesWritten);
    calloc.free(timeouts);
    calloc.free(dcb);
    calloc.free(path);
  }
}

bool _writeSerialBytes(int handle, List<int> bytes, Pointer<Uint32> written) {
  final data = calloc<Uint8>(bytes.length);
  try {
    data.asTypedList(bytes.length).setAll(0, bytes);
    written.value = 0;
    return WriteFile(handle, data, bytes.length, written, nullptr) != 0 &&
        written.value == bytes.length;
  } finally {
    calloc.free(data);
  }
}

List<int> _readSerialBytes(
  int handle,
  Pointer<Uint32> bytesRead, {
  int capacity = 64,
}) {
  final data = calloc<Uint8>(capacity);
  try {
    bytesRead.value = 0;
    if (ReadFile(handle, data, capacity, bytesRead, nullptr) == 0) {
      return const [];
    }
    return List<int>.from(data.asTypedList(bytesRead.value));
  } finally {
    calloc.free(data);
  }
}

double? _requestCasWeight(
  int handle,
  Pointer<Uint32> bytesRead,
  Pointer<Uint32> bytesWritten,
) {
  if (!_writeSerialBytes(handle, const [0x05], bytesWritten)) return null;
  final handshake = _readSerialBytes(handle, bytesRead);
  if (!handshake.contains(0x06)) return null;
  if (!_writeSerialBytes(handle, const [0x11], bytesWritten)) return null;
  final response = _readSerialBytes(handle, bytesRead);
  return _parseCasWeight(response);
}

double? _parseCasWeight(List<int> bytes) {
  final soh = bytes.indexOf(0x01);
  if (soh < 0 || bytes.length < soh + 14) return null;
  final stx = bytes.indexOf(0x02, soh + 1);
  if (stx < 0 || bytes.length < stx + 12) return null;
  final stable = bytes[stx + 1] == 0x53; // ASCII S
  if (!stable) return null;
  final sign = bytes[stx + 2];
  if (sign == 0x46 || sign == 0x2D) return null; // overload / negative
  final weightText = ascii.decode(
    bytes.sublist(stx + 3, stx + 9),
    allowInvalid: true,
  );
  final value = double.tryParse(weightText.trim());
  if (value == null || value < 0) return null;
  final unit = ascii
      .decode(bytes.sublist(stx + 9, stx + 11), allowInvalid: true)
      .toLowerCase();
  return unit == 'kg' ? value * 1000 : value;
}

double? _requestPos2Weight(
  int handle,
  Pointer<Uint32> bytesRead,
  Pointer<Uint32> bytesWritten,
) {
  if (!_writeSerialBytes(handle, const [0x05], bytesWritten)) return null;
  final handshake = _readSerialBytes(handle, bytesRead);
  if (!handshake.contains(0x06)) return null;

  final request = <int>[0x02, 0x05, 0x3A, 0x30, 0x30, 0x33, 0x30];
  var lrc = 0;
  for (final byte in request.skip(1)) {
    lrc ^= byte;
  }
  request.add(lrc);
  if (!_writeSerialBytes(handle, request, bytesWritten)) return null;

  var response = _readSerialBytes(handle, bytesRead);
  // ACK may arrive separately from the response packet.
  if (response.length == 1 && response.first == 0x06) {
    response = _readSerialBytes(handle, bytesRead);
  } else if (response.isNotEmpty && response.first == 0x06) {
    response = response.sublist(1);
  }
  final weight = _parsePos2Weight(response);
  if (weight != null) {
    _writeSerialBytes(handle, const [0x06], bytesWritten);
  }
  return weight;
}

double? _parsePos2Weight(List<int> bytes) {
  final stx = bytes.indexOf(0x02);
  if (stx < 0 || bytes.length < stx + 20) return null;
  final length = bytes[stx + 1];
  if (length != 0x11 || bytes[stx + 2] != 0x3A) return null;
  final end = stx + length + 3;
  if (bytes.length < end) return null;
  var lrc = 0;
  for (var i = stx + 1; i < end - 1; i++) {
    lrc ^= bytes[i];
  }
  if (lrc != bytes[end - 1] || bytes[stx + 3] != 0) return null;
  final status = bytes[stx + 4] | (bytes[stx + 5] << 8);
  // Extended protocol: bit 0 or bit 4 means stable. Simplified protocol has
  // all status bits cleared and is accepted as well.
  final extended = (status & 0x04) != 0;
  final stable = !extended || (status & 0x11) != 0;
  if (!stable) return null;
  final offset = stx + 6;
  var raw = bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
  if ((raw & 0x80000000) != 0) raw -= 0x100000000;
  return raw >= 0 && raw <= 1000000 ? raw.toDouble() : null;
}

double? _parseScaleWeightBytes(List<int> bytes) {
  final cas = _parseCasWeight(bytes);
  if (cas != null) return cas;
  final pos = _parsePos2Weight(bytes);
  if (pos != null) return pos;
  final raw = ascii.decode(bytes, allowInvalid: true);
  final normalized = raw.toLowerCase().replaceAll(',', '.');
  final matches = RegExp(r'[-+]?\s*\d+(?:\.\d+)?\s*(kg|кг|g|гр|г)?')
      .allMatches(normalized)
      .toList();
  if (matches.isEmpty) return null;
  final match = matches.last;
  final value = double.tryParse(
    match.group(0)!.replaceAll(RegExp(r'[^0-9.+-]'), ''),
  );
  if (value == null || !value.isFinite || value < 0) return null;
  final unit = match.group(1);
  final grams = unit == 'kg' || unit == 'кг' ? value * 1000 : value;
  return grams <= 1000000 ? grams : null;
}

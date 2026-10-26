import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kaspi_payment_service.dart';

/// Dedicated client: POS authentication headers and HTTP loggers must never be
/// attached to the terminal connection.
class KaspiTerminal {
  KaspiTerminal._();
  static final instance = KaspiTerminal._();
  static const _secure = FlutterSecureStorage();
  static const _credentialsKey = 'kaspi.credentials';
  static const _settingsKey = 'kaspi.connection';
  static const clientName = 'Leemon-POS';

  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _credentials;
  Dio? _dio;
  KaspiPaymentService? _payments;

  String get host => (_settings?['host'] ?? '').toString();
  bool get registered =>
      (_credentials?['accessToken'] ?? '').toString().isNotEmpty;

  Future<void> initialize() async {
    if (_settings != null) return;
    final prefs = await SharedPreferences.getInstance();
    var settings = prefs.getString(_settingsKey);
    final importingBootstrap = settings == null;
    // One-time migration of the registration approved on this Windows PC.
    if (settings == null && Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base != null) {
        final file = File('$base/Leemon/Kaspi/connection.json');
        if (await file.exists()) settings = await file.readAsString();
      }
    }
    final connection = settings == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(settings));
    var credentials = await _secure.read(key: _credentialsKey);
    if (credentials == null &&
        importingBootstrap &&
        Platform.isWindows &&
        connection.isNotEmpty) {
      // Decrypt under the same Windows user. Nothing is written in plaintext.
      final base = Platform.environment['LOCALAPPDATA'];
      if (base != null &&
          await File('$base/Leemon/Kaspi/registration.dpapi').exists()) {
        final imported = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$p = Join-Path $env:LOCALAPPDATA "Leemon\Kaspi\registration.dpapi"; '
              r'$s = (Get-Content -Raw -LiteralPath $p).Trim() | ConvertTo-SecureString; '
              r'$c = [System.Net.NetworkCredential]::new("", $s); '
              r'[Console]::Write($c.Password)'
        ]);
        if (imported.exitCode != 0) {
          throw const KaspiPaymentException(
              'Не удалось прочитать регистрацию Kaspi Windows');
        }
        final response = jsonDecode(imported.stdout.toString());
        credentials = jsonEncode(response['data']);
        await _secure.write(key: _credentialsKey, value: credentials);
      }
    }
    if (settings != null && !await prefs.setString(_settingsKey, settings)) {
      throw const KaspiPaymentException('Не удалось сохранить настройки Kaspi');
    }
    _credentials = credentials == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(credentials));
    _settings = connection;
  }

  Dio _client() {
    if (_dio != null) return _dio!;
    final fingerprint = _settings?['fingerprint'];
    if (host.isEmpty || fingerprint == null) {
      throw const KaspiPaymentException(
          'Откройте «Устройства → Kaspi POS» и настройте терминал');
    }
    final dio = Dio(BaseOptions(
      baseUrl: 'https://$host:8080',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      return HttpClient()
        ..badCertificateCallback = (cert, requestedHost, port) =>
            requestedHost == host &&
            port == 8080 &&
            sha256.convert(cert.der).toString() == fingerprint;
    });
    return _dio = dio;
  }

  Future<Map<String, dynamic>> _raw(
      String path, Map<String, dynamic> parameters,
      {bool authorized = true}) async {
    final response = await _client().get<Map<String, dynamic>>(path,
        queryParameters: parameters,
        options: Options(
          receiveTimeout:
              path == '/v2/register' ? const Duration(minutes: 2) : null,
          headers:
              authorized ? {'accesstoken': _credentials?['accessToken']} : {},
        ));
    return response.data ?? {};
  }

  Future<void> _saveCredentials(Map<String, dynamic> response) async {
    final data = Map<String, dynamic>.from(response['data'] ?? {});
    if (response['statusCode'] != 0 ||
        data['accessToken'] == null ||
        data['refreshToken'] == null) {
      final detail =
          (data['message'] ?? response['errorText'] ?? 'ошибка регистрации')
              .toString();
      throw KaspiPaymentException(detail
              .contains('Last register request not completed')
          ? 'На терминале ещё не завершён предыдущий запрос регистрации. Разрешите или отклоните его на терминале, затем повторите регистрацию один раз.'
          : 'Kaspi: $detail');
    }
    await _secure.write(key: _credentialsKey, value: jsonEncode(data));
    _credentials = data;
  }

  Future<void> _refresh() async => _saveCredentials(await _raw(
      '/v2/revoke',
      {
        'name': clientName,
        'refreshToken': _credentials?['refreshToken'],
      },
      authorized: false));

  Future<Map<String, dynamic>> _request(
      String path, Map<String, dynamic> parameters) async {
    try {
      return await _raw(path, parameters);
    } on DioException catch (e) {
      // A 403 means the terminal rejected authentication before starting the
      // operation. Never retry timeouts or lost payment responses.
      if (e.response?.statusCode != 403) rethrow;
      await _refresh();
      return _raw(path, parameters);
    }
  }

  Future<void> prepare() async {
    await initialize();
    _client();
    if (!registered) {
      throw const KaspiPaymentException(
          'Kaspi не зарегистрирован. Откройте «Устройства → Kaspi POS»');
    }
    final expiry =
        DateTime.tryParse((_credentials?['expirationDate'] ?? '').toString());
    if (expiry == null ||
        expiry.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      await _refresh();
    }
  }

  Future<void> checkConnection() async {
    await prepare();
    // Read-only request: a nonexistent operation confirms both connectivity
    // and authentication without starting a payment.
    final response = await _request('/v2/status', {'processId': '0'});
    if (response['statusCode'] != 101 && response['statusCode'] != 0) {
      throw KaspiPaymentException(
          'Kaspi: ${response['errorText'] ?? 'ошибка соединения'}');
    }
  }

  Future<Map<String, dynamic>> pay(
      {required String saleId,
      required double amount,
      void Function(String)? onProgress}) async {
    await prepare();
    final prefs = await SharedPreferences.getInstance();
    _payments ??= KaspiPaymentService(
      request: _request,
      read: (key) async => prefs.getString(key),
      write: (key, value) async {
        if (!await prefs.setString(key, value)) {
          throw const KaspiPaymentException(
              'Не удалось сохранить операцию Kaspi на компьютере');
        }
      },
    );
    return _payments!
        .pay(saleId: saleId, amount: amount, onProgress: onProgress);
  }

  /// Explicit registration pins the certificate of the local terminal selected
  /// by the operator; subsequent requests only accept this certificate.
  Future<void> register(String address) async {
    await initialize();
    final ip = InternetAddress.tryParse(address.trim());
    if (ip == null || ip.type != InternetAddressType.IPv4) {
      throw const KaspiPaymentException('Укажите IPv4-адрес терминала');
    }
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getString(KaspiPaymentService.activeKey);
    if (active != null && active.isNotEmpty) {
      throw const KaspiPaymentException(
          'Сначала завершите сохранённую операцию Kaspi');
    }
    final socket = await SecureSocket.connect(ip.address, 8080,
        timeout: const Duration(seconds: 5), onBadCertificate: (_) => true);
    final certificate = socket.peerCertificate;
    socket.destroy();
    if (certificate == null) {
      throw const KaspiPaymentException('Нет сертификата терминала');
    }
    _settings = {
      'host': ip.address,
      'fingerprint': sha256.convert(certificate.der).toString()
    };
    _dio?.close(force: true);
    _dio = null;
    // Clear credentials before changing endpoints so a rejected registration
    // cannot send an old terminal's tokens to the new terminal.
    await _secure.delete(key: _credentialsKey);
    _credentials = null;
    if (!await prefs.setString(_settingsKey, jsonEncode(_settings))) {
      throw const KaspiPaymentException('Не удалось сохранить адрес Kaspi');
    }
    await _saveCredentials(
        await _raw('/v2/register', {'name': clientName}, authorized: false));
  }
}

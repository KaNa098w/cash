import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leemon_app/core/models/fiscal_receipt.dart';
import 'package:leemon_app/core/print/print_service.dart';

class FiscalReceiptService {
  FiscalReceiptService(this._dio, this._printer);

  static const _storageKey = 'fiscal_receipts_v1';
  final Dio _dio;
  final PrintService _printer;
  final Map<String, Timer> _pollTimers = <String, Timer>{};

  FiscalReceipt? fromSaleResponse(Map<String, dynamic>? response) {
    if (response == null) return null;
    final raw = response['fiscal_receipt'];
    if (raw is! Map) return null;
    final receipt = FiscalReceipt.fromJson(Map<String, dynamic>.from(raw));
    return receipt.id.isEmpty ? null : receipt;
  }

  Future<FiscalReceipt> refresh({
    required String key,
    required String deviceId,
    required String receiptId,
  }) async {
    final response = await _dio.get(
      '/organizations/pos/$key/fiscal-receipts/$receiptId',
      queryParameters: {'device_id': deviceId},
    );
    final body = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    final raw = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final receipt = FiscalReceipt.fromJson(raw);
    await save(receipt);
    return receipt;
  }

  void startBackgroundPolling({
    required String key,
    required String deviceId,
    required FiscalReceipt receipt,
  }) {
    _pollTimers.remove(receipt.id)?.cancel();
    if (!receipt.isPending) return;
    _pollTimers[receipt.id] = Timer(
      Duration(seconds: receipt.pollAfterSeconds),
      () async {
        try {
          final updated = await refresh(
            key: key,
            deviceId: deviceId,
            receiptId: receipt.id,
          );
          if (updated.isPending) {
            startBackgroundPolling(
              key: key,
              deviceId: deviceId,
              receipt: updated,
            );
          } else {
            _pollTimers.remove(receipt.id)?.cancel();
          }
        } catch (_) {
          startBackgroundPolling(
            key: key,
            deviceId: deviceId,
            receipt: receipt,
          );
        }
      },
    );
  }

  Future<void> save(
    FiscalReceipt receipt, {
    bool? localReceiptPrinted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = <String, dynamic>{};
    final current = prefs.getString(_storageKey);
    if (current != null) {
      final decoded = jsonDecode(current);
      if (decoded is Map) stored.addAll(Map<String, dynamic>.from(decoded));
    }
    final previous = stored[receipt.id] is Map
        ? Map<String, dynamic>.from(stored[receipt.id] as Map)
        : const <String, dynamic>{};
    stored[receipt.id] = {
      ...previous,
      ...receipt.toJson(),
      'last_checked_at': DateTime.now().toIso8601String(),
      if (localReceiptPrinted != null)
        'local_receipt_printed': localReceiptPrinted,
    };
    await prefs.setString(_storageKey, jsonEncode(stored));
  }

  Future<List<FiscalReceipt>> loadUnfinished() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_storageKey);
    if (current == null || current.isEmpty) return const <FiscalReceipt>[];
    final decoded = jsonDecode(current);
    if (decoded is! Map) return const <FiscalReceipt>[];
    return decoded.values
        .whereType<Map>()
        .map((raw) => FiscalReceipt.fromJson(Map<String, dynamic>.from(raw)))
        .where((receipt) => receipt.isPending)
        .toList(growable: false);
  }

  Future<void> printTicket(
    FiscalReceipt receipt, {
    String? printerName,
  }) async {
    if (!receipt.canPrint || (receipt.ticketPrintUrl ?? '').isEmpty) {
      throw StateError('Фискальный чек ещё не готов к печати');
    }
    final response = await _dio.get<List<int>>(
      receipt.ticketPrintUrl!,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const <int>[]);
    final contentType =
        (response.headers.value(Headers.contentTypeHeader) ?? '').toLowerCase();
    if (contentType.contains('application/pdf')) {
      await _printer.printPdfBytesSilently(bytes, printerName: printerName);
      await _markPrinted(receipt.id);
      return;
    }
    if (contentType.startsWith('image/')) {
      final document = pw.Document()
        ..addPage(pw.Page(
            build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(bytes)))));
      await _printer.printPdfBytesSilently(
        await document.save(),
        printerName: printerName,
      );
      await _markPrinted(receipt.id);
      return;
    }
    throw FormatException('Неподдерживаемый формат чека: $contentType');
  }

  Future<void> _markPrinted(String receiptId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_storageKey);
    if (current == null || current.isEmpty) return;
    final decoded = jsonDecode(current);
    if (decoded is! Map) return;
    final stored = Map<String, dynamic>.from(decoded);
    final raw = stored[receiptId];
    if (raw is! Map) return;
    stored[receiptId] = {
      ...Map<String, dynamic>.from(raw),
      'fiscal_receipt_printed': true,
    };
    await prefs.setString(_storageKey, jsonEncode(stored));
  }
}

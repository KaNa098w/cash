import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
    Iterable<String> saleIds = const <String>[],
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
    final knownSaleIds = <String>{
      ...((previous['sale_ids'] as List?) ?? const <dynamic>[])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty),
      ...saleIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    };
    stored[receipt.id] = {
      ...previous,
      ...receipt.toJson(),
      'last_checked_at': DateTime.now().toIso8601String(),
      if (localReceiptPrinted != null)
        'local_receipt_printed': localReceiptPrinted,
      if (knownSaleIds.isNotEmpty) 'sale_ids': knownSaleIds.toList(),
    };
    await prefs.setString(_storageKey, jsonEncode(stored));
  }

  Future<FiscalReceipt?> findBySaleId(String saleId) async {
    final id = saleId.trim();
    if (id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_storageKey);
    if (current == null || current.isEmpty) return null;
    final decoded = jsonDecode(current);
    if (decoded is! Map) return null;
    for (final raw in decoded.values.whereType<Map>()) {
      final data = Map<String, dynamic>.from(raw);
      final saleIds = (data['sale_ids'] as List?) ?? const <dynamic>[];
      if (saleIds.any((value) => value.toString().trim() == id)) {
        return FiscalReceipt.fromJson(data);
      }
    }
    return null;
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
    required String key,
    required String deviceId,
    required int paperMm,
    String? printerName,
  }) async {
    if (!receipt.canPrint) {
      throw StateError('Фискальный чек ещё не готов к печати');
    }
    final response = await _dio.get<dynamic>(
      '/organizations/pos/$key/fiscal-receipts/${receipt.id}/print-format',
      queryParameters: {
        'device_id': deviceId,
        'paper_kind': paperMm == 80 ? 0 : 3,
      },
    );
    final body = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final rawLines = data['lines'] ?? data['Lines'];
    if (rawLines is! List || rawLines.isEmpty) {
      throw const FormatException('Webkassa вернула пустой PrintFormat');
    }

    final lines = rawLines
        .whereType<Map>()
        .map((line) => Map<String, dynamic>.from(line))
        .toList(growable: false)
      ..sort((a, b) => _lineInt(a, 'Order').compareTo(_lineInt(b, 'Order')));
    final regularFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final widgets = <pw.Widget>[];
    for (final line in lines) {
      final type = _lineInt(line, 'Type');
      final value = (line['Value'] ?? line['value'] ?? '').toString();
      if (value.isEmpty) continue;
      if (type == 0) {
        widgets.add(
          pw.Container(
            width: double.infinity,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: _lineInt(line, 'Style') == 1 ? boldFont : regularFont,
                fontSize: paperMm == 80 ? 10 : 8,
                fontWeight: _lineInt(line, 'Style') == 1
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
        );
      } else if (type == 1) {
        final encoded = value.contains(',') ? value.split(',').last : value;
        final bytes = base64Decode(encoded.replaceAll(RegExp(r'\s'), ''));
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Center(
              child: pw.Image(
                pw.MemoryImage(bytes),
                fit: pw.BoxFit.contain,
                width: paperMm == 80 ? 190 : 130,
              ),
            ),
          ),
        );
      } else if (type == 2) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: value,
                width: paperMm == 80 ? 120 : 95,
                height: paperMm == 80 ? 120 : 95,
              ),
            ),
          ),
        );
      }
    }

    final document = pw.Document()
      ..addPage(
        pw.Page(
          pageFormat:
              paperMm == 80 ? PdfPageFormat.roll80 : PdfPageFormat.roll57,
          margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          build: (_) => pw.Center(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: widgets,
            ),
          ),
        ),
      );
    await _printer.printPdfBytesSilently(
      await document.save(),
      printerName: printerName,
    );
    await _savePrintFormatFetchedAt(receipt.id);
    await _markPrinted(receipt.id);
  }

  int _lineInt(Map<String, dynamic> line, String key) {
    final value = line[key] ?? line[key.toLowerCase()];
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  Future<void> _savePrintFormatFetchedAt(String receiptId) async {
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
      'print_format_fetched_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_storageKey, jsonEncode(stored));
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

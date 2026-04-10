import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:leemon_app/core/models/app_update_response.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:printing/printing.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/app_update_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/deposit_to_cash_sheel.dart';
import 'package:path/path.dart' as path;
import 'package:leemon_app/core/di/api/app_version.dart';
import 'package:path_provider/path_provider.dart';

import 'package:window_manager/window_manager.dart';

const String _appUpdateChannel =
    String.fromEnvironment('APP_UPDATE_CHANNEL', defaultValue: 'stable');
const String _preferredUpdatePackageType =
    String.fromEnvironment('APP_UPDATE_PACKAGE_TYPE', defaultValue: 'zip');
const String _appExeName = 'Leemon.exe';
const String _updaterExeName = 'Leemon.Updater.exe';

Future<void> showPosActionsDialog(BuildContext context) {
  final actions = <_PosAction>[
    _PosAction('ВЫХОД ИЗ ПРОГРАММЫ', () async {
      Navigator.of(context, rootNavigator: true).pop();

      // (опционально) если нужно перед выходом что-то сохранить/закрыть — делай здесь

      await exitAppFully();
    }),
    _PosAction('ЗАБЛОКИРОВАТЬ КАССУ', () {
      Navigator.of(context, rootNavigator: true).pop();
      context.read<AuthCubit>().lockToCashiers();
    }),
    _PosAction('РАСПЕЧАТАТЬ ЧЕК\nПОСЛЕДНЕЙ ПРОДАЖИ', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await _printLastSaleReceipt(context);
    }),
    _PosAction(
      'СИНХРОНИЗАЦИЯ',
      () async {
        Navigator.of(context, rootNavigator: true).pop(); // закрыть диалог

        await _runSyncWithProgress(context);
      },
    ),
    _PosAction('ОЧЕРЕДЬ СЕРВИСОВ', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await _showServicesQueueDialog(context);
    }),
    _PosAction('СВЕРНУТЬ', () async {
      Navigator.of(context, rootNavigator: true).pop();

      if (kIsWeb ||
          !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        return;
      }

      final wasFs = await windowManager.isFullScreen();

      await windowManager.setMinimizable(true);

      // ⚠️ важно: в full-screen Windows часто не умеет minimize
      if (wasFs) {
        await windowManager.setFullScreen(false);
        await Future.delayed(const Duration(milliseconds: 80));
      }

      await windowManager.minimize();
    }),
    _PosAction('ПРОВЕРИТЬ ОБНОВЛЕНИЕ', () async {
      Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _UpdateCheckDialog(),
      );
    }),
    _PosAction('ВЗНОС В КАССУ', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await showDepositToCashSheet(context, true);
    }),
    _PosAction('РАСХОД', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await showDepositToCashSheet(context, false);
    }),
    _PosAction('СДАТЬ СМЕНУ', () async {
      Navigator.of(context, rootNavigator: true)
          .pop(); // закрыть actions dialog
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!context.mounted) return;
      context.go('/close-shift');
    }),
    _PosAction('ПРИНТЕР', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await _pickPrinterSettings(context);
    }),
  ];

  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: ThemeColors.greyB,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: LayoutBuilder(
              builder: (context, c) {
                // 4 колонки при ширине > 780, иначе 3
                final cols = c.maxWidth > 780 ? 4 : 3;
                return Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(6),
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 2.1,
                        ),
                        itemCount: actions.length,
                        itemBuilder: (context, i) =>
                            _ActionTile(action: actions[i]),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 240,
                        height: 64,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD45F4F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          child: const Text(
                            'ЗАКРЫТЬ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _showServicesQueueDialog(BuildContext context) async {
  final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
  final deviceId = context.read<AuthTokenProvider>().deviceId?.trim() ?? '';
  final sync = sl<PosSyncService>();

  List<QueueListItem> queueItems = await sync.loadQueueItems();
  var syncing = false;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> syncNow() async {
            if (syncing) return;
            if (key.isEmpty || deviceId.isEmpty) return;
            setState(() => syncing = true);
            await sync.pushPending(key: key, deviceId: deviceId, limit: 20);
            final next = await sync.loadQueueItems();
            setState(() {
              queueItems = next;
              syncing = false;
            });
          }

          Widget queueTile({
            required String title,
            required String subtitle,
            required Color dot,
            VoidCallback? onTap,
          }) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }

          Future<void> openQueueDetails(QueueListItem item) async {
            final details = await sync.loadQueueItemDetails(item.id);
            if (!context.mounted || details == null) return;
            await _showQueueItemDetailsDialog(context, details);
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Очередь сервисов',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'В очереди: ${queueItems.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: syncing ? null : syncNow,
                            icon: syncing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync_rounded),
                            label: const Text('Отправить сейчас'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Закрыть'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final item in queueItems) ...[
                            queueTile(
                              title: item.title ?? item.type.label,
                              subtitle: item.subtitle ??
                                  (item.status == OutboxOperationStatus.manual
                                      ? 'Требуется ручная обработка'
                                      : 'Ждет отправки'),
                              dot: item.status == OutboxOperationStatus.manual
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFDC2626),
                              onTap: item.errorCode != null ||
                                      item.errorMessage != null
                                  ? () => openQueueDetails(item)
                                  : null,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (queueItems.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.only(top: 28),
                                child: Text(
                                  'Очередь пустая',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> _runSyncWithProgress(BuildContext context) async {
  final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
  if (key.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет posKey')),
    );
    return;
  }

  final progress = ValueNotifier<double>(0.08);
  final stage = ValueNotifier<String>('Подготавливаем синхронизацию...');
  final stopRequested = ValueNotifier<bool>(false);

  bool dialogClosed = false;

  void closeDialogSafe() {
    if (dialogClosed) return;
    dialogClosed = true;
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, p, __) {
                return ValueListenableBuilder<String>(
                  valueListenable: stage,
                  builder: (_, s, __) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: stopRequested,
                      builder: (_, stopping, __) {
                        final percent = (p.clamp(0.0, 1.0) * 100).round();

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB)
                                        .withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.sync_rounded,
                                    color: Color(0xFF2563EB),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Синхронизация',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Text(
                                    '$percent%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Stage text
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: p.clamp(0.0, 1.0),
                                minHeight: 10,
                                backgroundColor: const Color(0xFFE5E7EB),
                                valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF2563EB),
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 46,
                                    child: OutlinedButton.icon(
                                      onPressed: stopping
                                          ? null
                                          : () {
                                              stopRequested.value = true;
                                              stage.value =
                                                  'Останавливаем синхронизацию...';
                                            },
                                      icon: stopping
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons
                                              .pause_circle_outline_rounded),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF0F172A),
                                        side: BorderSide(
                                          color: stopping
                                              ? const Color(0xFFE2E8F0)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        backgroundColor: Colors.white,
                                      ),
                                      label: Text(
                                        stopping
                                            ? 'Останавливается...'
                                            : 'Остановить',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 46,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        stopRequested.value = true;
                                        closeDialogSafe();
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF0F172A),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      label: const Text(
                                        'Закрыть',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );

  try {
    if (stopRequested.value) return;

    final deviceId = context.read<AuthTokenProvider>().deviceId?.trim() ?? '';
    if (deviceId.isEmpty) {
      throw Exception('Нет deviceId');
    }

    await sl<PosSyncService>().bootstrap(
      key: key,
      deviceId: deviceId,
      onProgress: (SyncProgress syncProgress) {
        if (stopRequested.value) return;
        progress.value = syncProgress.progress;
        stage.value = syncProgress.detail == null
            ? syncProgress.stage
            : '${syncProgress.stage}: ${syncProgress.detail}';
      },
    );

    if (!context.mounted || stopRequested.value) return;
    await context.read<ProductsCubit>().loadFirstPage(
          key: key,
          forceRefresh: false,
        );

    if (!context.mounted || stopRequested.value) return;
    stage.value = 'Синхронизация завершена';
    progress.value = 1.0;
    await Future.delayed(const Duration(milliseconds: 260));
  } catch (e) {
    if (context.mounted && !stopRequested.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка синхронизации: $e')),
      );
    }
  } finally {
    progress.dispose();
    stage.dispose();
    stopRequested.dispose();
    closeDialogSafe();
  }
}

Future<void> _printLastSaleReceipt(BuildContext context) async {
  final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
  final pageFormat = _receiptPageFormat(context);
  if (key.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет posKey')),
    );
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final remote = sl<SaleRemoteDataSource>();
    final sale = await remote.getLastSale(key: key);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (sale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Продажи не найдены')),
      );
      return;
    }

    final printer = PrintService();
    final auth = context.read<AuthTokenProvider>();
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? (sale.userId.trim().isEmpty ? '-' : sale.userId.trim())
        : auth.activeUserName!.trim();
    final storeName = (() {
      final name = (auth.storeName ?? '').trim();
      if (name.isNotEmpty) return name;
      final posName = (auth.posName ?? '').trim();
      if (posName.isNotEmpty) return posName;
      return 'Магазин';
    })();

    await printer.print80mmSilently(
      () => buildReceiptPdf(
        ReceiptPdfData(
          pageFormat: pageFormat,
          money: money,
          receiptDate: sale.date,
          receiptNumber: formatPosReceiptNumber(
            posNumber: auth.posNumber ?? '',
            saleNumber: sale.number,
            fallback: sale.localId,
          ),
          cashierName: cashierName,
          storeName: storeName,
          items: sale.items
              .map(
                (it) => ReceiptPdfItem(
                  name: (it.product?.name ?? '').trim().isEmpty
                      ? 'Товар ${it.productId}'
                      : it.product!.name,
                  quantity: it.quantity,
                  unitPrice: it.price,
                  lineTotal: it.totalPrice,
                ),
              )
              .toList(),
          total: sale.totalAmount,
          discountSum: 0,
          paymentMethodLabel: switch (sale.paymentMethod.toLowerCase()) {
            'cash' => 'Наличные',
            'card' => 'Безналичный',
            'credit' => 'В долг',
            _ => sale.paymentMethod,
          },
          isCashPayment: sale.paymentMethod.toLowerCase() == 'cash',
        ),
      ),
      printerName: auth.receiptPrinterName,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sale.number.trim().isEmpty
              ? 'Последний чек отправлен на печать'
              : 'Чек №${sale.number} отправлен на печать',
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка печати последнего чека: $e')),
      );
    }
  }
}

PdfPageFormat _receiptPageFormat(BuildContext context) {
  final mm = context.read<AuthTokenProvider>().receiptPaperMm;
  return mm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
}

Future<void> _pickPrinterSettings(BuildContext context) async {
  final provider = context.read<AuthTokenProvider>();

  final printers = await Printing.listPrinters();
  final printerNames = printers.map((p) => p.name).toList();

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      int selectedMm = provider.receiptPaperMm;
      String? selectedReceipt = provider.receiptPrinterName;
      String? selectedInvoice = provider.invoicePrinterName;

      // Если сохранённый принтер больше не доступен — сбросить
      if (selectedReceipt != null && !printerNames.contains(selectedReceipt)) {
        selectedReceipt = null;
      }
      if (selectedInvoice != null && !printerNames.contains(selectedInvoice)) {
        selectedInvoice = null;
      }

      return StatefulBuilder(
        builder: (context, setState) {
          Widget sectionTitle(String text) => Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 14),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF374151),
                  ),
                ),
              );

          Widget printerDropdown({
            required String label,
            required String? value,
            required void Function(String?) onChanged,
          }) {
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint:
                    const Text('По умолчанию', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('По умолчанию', style: TextStyle(fontSize: 13)),
                  ),
                  ...printerNames.map(
                    (name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            );
          }

          Widget paperCard(
              {required int value,
              required String title,
              required String subtitle}) {
            final isSelected = selectedMm == value;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => selectedMm = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEAF2FF)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A))),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.print_rounded, color: Color(0xFF2563EB)),
                          SizedBox(width: 8),
                          Text(
                            'Настройки принтеров',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      sectionTitle('Размер бумаги чека'),
                      paperCard(
                          value: 80,
                          title: '80 мм',
                          subtitle: 'Стандартный широкий чек'),
                      const SizedBox(height: 8),
                      paperCard(
                          value: 57,
                          title: '57 мм',
                          subtitle: 'Узкий термочек'),
                      sectionTitle('Принтер для чеков (термопринтер)'),
                      printerDropdown(
                        label: 'Чеки / Z-отчёт',
                        value: selectedReceipt,
                        onChanged: (v) => setState(() => selectedReceipt = v),
                      ),
                      sectionTitle('Принтер для накладных (A4)'),
                      printerDropdown(
                        label: 'Накладные',
                        value: selectedInvoice,
                        onChanged: (v) => setState(() => selectedInvoice = v),
                      ),
                      if (printerNames.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Принтеры не найдены. Проверьте подключение.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFFDC2626)),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0F172A),
                                  side: const BorderSide(
                                      color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Отмена',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: FilledButton(
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  await provider.setReceiptPaperMm(selectedMm);
                                  await provider
                                      .setReceiptPrinterName(selectedReceipt);
                                  await provider
                                      .setInvoicePrinterName(selectedInvoice);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Сохранить',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

// ignore: unused_element
Future<void> _pickReceiptPaperSize(BuildContext context) async {
  final provider = context.read<AuthTokenProvider>();
  final current = provider.receiptPaperMm;

  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) {
      int selected = current;
      return StatefulBuilder(
        builder: (context, setState) {
          Widget paperCard({
            required int value,
            required String title,
            required String subtitle,
          }) {
            final isSelected = selected == value;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => selected = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEAF2FF)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Размер чека',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Выберите ширину бумаги для печати',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  paperCard(
                    value: 80,
                    title: '80 мм',
                    subtitle: 'Стандартный широкий чек',
                  ),
                  const SizedBox(height: 10),
                  paperCard(
                    value: 57,
                    title: '57 мм',
                    subtitle: 'Узкий термочек',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F172A),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Отмена',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(selected),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Сохранить',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (picked == null || !context.mounted) return;
  await provider.setReceiptPaperMm(picked);
  if (!context.mounted) return;
  await openWindowsPrintersSettings(context);
}

Future<void> openWindowsPrintersSettings(BuildContext context) async {
  if (kIsWeb || !Platform.isWindows) return;

  Future<bool> runCommand(List<String> args) async {
    try {
      final res = await Process.run(args.first, args.sublist(1));
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  final okSettings = await runCommand(['explorer.exe', 'ms-settings:printers']);
  if (okSettings) return;

  // 2) Панель управления: "Устройства и принтеры" (классика)
  final okControl = await runCommand(['control.exe', 'printers']);
  if (okControl) return;

  // 3) Fallback: открыть Панель управления (если вдруг "printers" не сработал)
  await runCommand(['control.exe']);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Открываю настройки принтера…')),
    );
  }
}

Future<void> _showQueueItemDetailsDialog(
  BuildContext context,
  QueueItemDetails details,
) {
  final storedError = details.lastErrorDetails ?? const <String, dynamic>{};
  final requestPayload = _asMap(storedError['request_payload']) ?? details.payload;
  final errorDetails =
      _asMap(storedError['error_details']) ?? const <String, dynamic>{};
  final requestMeta = _asMap(errorDetails['request']) ?? const <String, dynamic>{};
  final responseMeta =
      _asMap(errorDetails['response']) ?? const <String, dynamic>{};
  final items = _asListOfMaps(requestPayload['items']);

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  details.title ?? details.type.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  [
                    'Код: ${details.errorCode ?? '-'}',
                    'Ошибка: ${details.errorMessage ?? '-'}',
                    if ((responseMeta['status_code'] ?? '').toString().isNotEmpty)
                      'HTTP: ${responseMeta['status_code']}',
                    if ((requestMeta['method'] ?? '').toString().isNotEmpty ||
                        (requestMeta['path'] ?? '').toString().isNotEmpty)
                      'Запрос: ${requestMeta['method'] ?? ''} ${requestMeta['path'] ?? ''}',
                  ].join('\n'),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    children: [
                      if (items.isNotEmpty) ...[
                        _queueDetailsSection(
                          title: 'Товары',
                          child: Column(
                            children: [
                              for (final item in items) _queueItemRow(item: item),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _queueDetailsSection(
                        title: 'Что отправили',
                        child: SelectableText(
                          _prettyJson(requestPayload),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _queueDetailsSection(
                        title: 'Что вернул сервер',
                        child: SelectableText(
                          _prettyJson(
                            responseMeta.isNotEmpty
                                ? responseMeta
                                : errorDetails.isNotEmpty
                                    ? errorDetails
                                    : <String, dynamic>{
                                        'code': details.errorCode,
                                        'message': details.errorMessage,
                                      },
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Закрыть'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _queueDetailsSection({
  required String title,
  required Widget child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

Widget _queueItemRow({
  required Map<String, dynamic> item,
}) {
  final name = (item['product_name'] ?? item['name'] ?? item['product_id'] ?? '-')
      .toString();
  final quantity = item['quantity']?.toString() ?? '-';
  final price = item['price']?.toString() ?? '-';
  final total = item['total_price']?.toString() ?? '-';

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'qty: $quantity  price: $price  sum: $total',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    ),
  );
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

String _prettyJson(dynamic value) {
  const encoder = JsonEncoder.withIndent('  ');
  try {
    return encoder.convert(value);
  } catch (_) {
    return value?.toString() ?? 'null';
  }
}

Future<File> _downloadUpdatePackage(
  AppUpdateResponse latest,
  ValueNotifier<double> progress,
) async {
  final dio = sl<Dio>();
  final directory = await getTemporaryDirectory();
  final safeVersion =
      latest.latestVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final packageType = latest.packageType.trim().toLowerCase();
  final extension = switch (packageType) {
    'zip' => 'zip',
    'exe' => 'exe',
    _ => packageType.isEmpty ? 'bin' : packageType,
  };
  final targetPath = path.join(
    directory.path,
    'leemon_update_$safeVersion.$extension',
  );
  final target = File(targetPath);

  if (await target.exists()) {
    await target.delete();
  }

  await dio.download(
    latest.downloadUrl,
    target.path,
    onReceiveProgress: (received, total) {
      if (total > 0) {
        final ratio = received / total;
        progress.value = 0.1 + (ratio.clamp(0.0, 1.0) * 0.75);
      }
    },
  );

  final actualSize = await target.length();
  if (latest.fileSize > 0 && actualSize != latest.fileSize) {
    throw Exception(
        'Размер скачанного файла не совпадает с серверным значением.');
  }

  if (latest.checksumSha256.isNotEmpty) {
    final bytes = await target.readAsBytes();
    final actual = sha256.convert(bytes).toString().toLowerCase();
    if (actual != latest.checksumSha256.toLowerCase()) {
      throw Exception('Контрольная сумма файла обновления не совпала.');
    }
  }

  return target;
}

Future<void> _installAndRestartApp(
  File file,
  AppUpdateResponse latest,
  BuildContext context,
) async {
  if (!file.existsSync()) {
    throw Exception('Файл обновления не найден на диске.');
  }

  if (!Platform.isWindows) {
    throw Exception('Обновление пока не поддерживается для этой ОС.');
  }

  final packageType = latest.packageType.trim().toLowerCase();

  if (packageType == 'zip') {
    await _runZipUpdater(file, context);
    return;
  }

  if (packageType == 'exe') {
    await _runSilentInstaller(file, context);
    return;
  }

  throw Exception(
    'Неподдерживаемый тип пакета обновления: ${latest.packageType}',
  );
}

Future<void> _runZipUpdater(File packageFile, BuildContext context) async {
  if (kDebugMode) {
    throw Exception(
      'Updater нельзя корректно проверить через flutter run в debug. '
      'Проверь обновление из установленной release-сборки.',
    );
  }

  final updaterFile = _resolveUpdaterExecutable();
  if (!await updaterFile.exists()) {
    throw Exception(
      'Updater не найден: ${updaterFile.path}. Сначала установите сборку с helper updater.',
    );
  }

  final targetDir = File(Platform.resolvedExecutable).parent.path;
  await Process.start(
    updaterFile.path,
    [
      '--zip',
      packageFile.path,
      '--target-dir',
      targetDir,
      '--app-exe',
      _appExeName,
    ],
    mode: ProcessStartMode.detached,
    workingDirectory: updaterFile.parent.path,
  );

  await Future.delayed(const Duration(milliseconds: 400));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Завершаю приложение и запускаю updater...'),
      ),
    );
  }
  await exitAppFully();
}

Future<void> _runSilentInstaller(
    File installerFile, BuildContext context) async {
  await Process.start(
    installerFile.path,
    const [
      '/SP-',
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ],
    mode: ProcessStartMode.detached,
  );

  await Future.delayed(const Duration(milliseconds: 500));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Запускаю тихое обновление и перезапускаю приложение...'),
      ),
    );
  }
  await exitAppFully();
}

File _resolveUpdaterExecutable() {
  final appDir = File(Platform.resolvedExecutable).parent.path;
  return File(path.join(appDir, 'updater', _updaterExeName));
}

Future<String> _getInstalledAppVersion() async {
  return kAppVersion;
}

int _compareVersionStrings(String newest, String installed) {
  final newParts = _normalizeVersion(newest);
  final installedParts = _normalizeVersion(installed);

  final len = newParts.length > installedParts.length
      ? newParts.length
      : installedParts.length;

  for (int i = 0; i < len; i++) {
    final n = i < newParts.length ? newParts[i] : 0;
    final c = i < installedParts.length ? installedParts[i] : 0;

    if (n > c) return 1;
    if (n < c) return -1;
  }

  return 0;
}

List<int> _normalizeVersion(String value) {
  final base = value.split('+').first;
  final parts = base.split('.');
  final normalized = <int>[];

  for (final part in parts) {
    normalized.add(int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0);
  }

  return normalized;
}

enum _UpdStage { idle, checking, upToDate, available, downloading }

class _UpdateCheckDialog extends StatefulWidget {
  const _UpdateCheckDialog();

  @override
  State<_UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<_UpdateCheckDialog> {
  _UpdStage _stage = _UpdStage.idle;
  AppUpdateResponse? _response;
  double _dlProgress = 0;
  String _dlText = '';
  String? _error;

  Future<void> _check() async {
    setState(() {
      _stage = _UpdStage.checking;
      _error = null;
    });
    try {
      final updateApi = sl<AppUpdateRemoteDataSource>();
      final latest = await updateApi.fetchLatest(
        channel: _appUpdateChannel,
        currentVersion: kAppVersion,
        packageType: _preferredUpdatePackageType,
      );
      if (!mounted) return;
      if (latest.updateAvailable &&
          _compareVersionStrings(latest.latestVersion, kAppVersion) > 0) {
        setState(() {
          _stage = _UpdStage.available;
          _response = latest;
        });
      } else {
        setState(() {
          _stage = _UpdStage.upToDate;
          _response = latest;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdStage.idle;
        _error = e.toString();
      });
    }
  }

  Future<void> _download() async {
    final latest = _response;
    if (latest == null) return;
    setState(() {
      _stage = _UpdStage.downloading;
      _dlProgress = 0;
      _dlText = 'Подготовка...';
      _error = null;
    });
    try {
      final progress = ValueNotifier<double>(0);
      progress.addListener(() {
        if (mounted) {
          setState(() {
            _dlProgress = progress.value;
            _dlText = 'Скачивание: ${(_dlProgress * 100).round()}%';
          });
        }
      });
      final file = await _downloadUpdatePackage(latest, progress);
      progress.dispose();
      if (!mounted) return;
      setState(() => _dlText = 'Применяем обновление...');
      await _installAndRestartApp(file, latest, context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdStage.available;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_stage) {
      _UpdStage.idle || _UpdStage.checking => _buildIdle(),
      _UpdStage.upToDate => _buildUpToDate(),
      _UpdStage.available => _buildAvailable(),
      _UpdStage.downloading => _buildDownloading(),
    };
  }

  Widget _buildIdle() {
    final checking = _stage == _UpdStage.checking;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Icons.system_update_alt_rounded,
          iconColor: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
          title: 'Обновление приложения',
        ),
        const SizedBox(height: 20),
        _VersionRow(label: 'Текущая версия', version: kAppVersion),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(message: _error!),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: checking ? null : () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: checking ? null : _check,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(checking ? 'Проверяем...' : 'Проверить'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpToDate() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF16A34A),
          iconBg: const Color(0xFFDCFCE7),
          title: 'Версия актуальна',
        ),
        const SizedBox(height: 20),
        _VersionRow(label: 'Установлена', version: kAppVersion),
        if (_response != null) ...[
          const SizedBox(height: 6),
          _VersionRow(
              label: 'Последняя',
              version: _response!.latestVersion,
              color: const Color(0xFF16A34A)),
        ],
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Готово'),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailable() {
    final latest = _response!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Icons.download_rounded,
          iconColor: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
          title: 'Доступно обновление',
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Текущая',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  Text(
                    kAppVersion,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF475569)),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child:
                    Icon(Icons.arrow_forward_rounded, color: Color(0xFF94A3B8)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Новая',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  Text(
                    latest.latestVersion,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2563EB)),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (latest.releaseNotes.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Что нового',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latest.releaseNotes.trim(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(message: _error!),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Обновить'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Icons.download_rounded,
          iconColor: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
          title: 'Установка обновления',
        ),
        const SizedBox(height: 20),
        Text(
          _dlText,
          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _dlProgress > 0 ? _dlProgress : null,
            minHeight: 10,
            backgroundColor: const Color(0xFFE2E8F0),
            color: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(_dlProgress * 100).clamp(0, 100).round()}%',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Не закрывайте приложение',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(width: 14),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.version,
    this.color = const Color(0xFF111827),
  });

  final String label;
  final String version;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        Text(
          version,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
      ),
    );
  }
}

Future<void> exitAppFully() async {
  if (kIsWeb) return;

  // Только desktop
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;

  try {
    // Если окно в full-screen — сначала выйдем из него (иначе close/minimize может глючить)
    final wasFs = await windowManager.isFullScreen();
    if (wasFs) {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 80));
    }

    // Попытка красиво закрыть окно
    await windowManager.close();

    // Если по какой-то причине не закрылось — добиваем процесс
    await Future.delayed(const Duration(milliseconds: 150));
    exit(0);
  } catch (_) {
    exit(0);
  }
}

class _PosAction {
  final String title;
  final FutureOr<void> Function() onTap;
  const _PosAction(this.title, this.onTap);
}

class _ActionTile extends StatelessWidget {
  final _PosAction action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async => action.onTap(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              action.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

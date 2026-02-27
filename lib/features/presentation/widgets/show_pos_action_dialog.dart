import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/product_local_datasource.dart';
import 'package:leemon_app/features/data/datasources/sale_local_datasource.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/close_shift_bottom.dart';
import 'package:leemon_app/features/presentation/widgets/deposit_to_cash_sheel.dart';
import 'package:printing/printing.dart';

import 'package:window_manager/window_manager.dart';

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
    _PosAction('ПРОВЕРИТЬ ОБНОВЛЕНИЕ', () {/* TODO */}),
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
      await showCloseShiftSheet(context); // открыть sheet с клавой
    }),
    _PosAction('ПРИНТЕР', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await _pickReceiptPaperSize(context);
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
  final local = sl<SaleLocalDataSource>();
  final repo = sl<SaleRepository>();

  List<SaleModel> pending = await local.loadPending();
  final sentIds = <String>{};
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
            final beforeIds = pending.map((e) => e.localId).toSet();
            await repo.syncPendingSales(key: key, deviceId: deviceId);
            final next = await local.loadPending();
            final afterIds = next.map((e) => e.localId).toSet();
            final delivered =
                beforeIds.where((id) => !afterIds.contains(id)).toSet();
            sentIds.addAll(delivered);
            setState(() {
              pending = next;
              syncing = false;
            });
          }

          Widget queueTile({
            required String title,
            required String subtitle,
            required Color dot,
          }) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
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
                ],
              ),
            );
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
                      'В очереди: ${pending.length}  •  Отправлено: ${sentIds.length}',
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
                                    child: CircularProgressIndicator(strokeWidth: 2),
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
                          for (final sale in pending) ...[
                            queueTile(
                              title: 'Чек: ${sale.number.isEmpty ? sale.localId : sale.number}',
                              subtitle: 'Ждёт интернет',
                              dot: const Color(0xFFDC2626),
                            ),
                            const SizedBox(height: 8),
                          ],
                          for (final id in sentIds) ...[
                            queueTile(
                              title: 'Чек: $id',
                              subtitle: 'Уже отправлено',
                              dot: const Color(0xFF16A34A),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (pending.isEmpty && sentIds.isEmpty)
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

  final progress = ValueNotifier<double>(0.06);
  final stage = ValueNotifier<String>('Подготавливаем синхронизацию...');

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, p, __) {
                return ValueListenableBuilder<String>(
                  valueListenable: stage,
                  builder: (_, s, __) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.sync_rounded,
                                color: Color(0xFF2563EB), size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Синхронизация',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${(p * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
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
    stage.value = 'Очистка локальных данных...';
    progress.value = 0.2;
    final local = sl<ProductLocalDataSource>();
    await local.clear();

    if (!context.mounted) return;
    stage.value = 'Загрузка товаров...';
    progress.value = 0.52;
    await context.read<ProductsCubit>().loadFirstPage(
          key: key,
          forceRefresh: true,
        );

    if (!context.mounted) return;
    stage.value = 'Загрузка быстрых товаров...';
    progress.value = 0.84;
    await context
        .read<ProductsCubit>()
        .loadPopularFirstPage(key: key, forceRefresh: true);

    if (!context.mounted) return;
    stage.value = 'Синхронизация завершена';
    progress.value = 1.0;
    await Future.delayed(const Duration(milliseconds: 260));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка синхронизации: $e')),
      );
    }
  } finally {
    progress.dispose();
    stage.dispose();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }
}

Future<pw.Document> _buildReceiptFromSale(
  SaleModel sale, {
  required PdfPageFormat pageFormat,
}) async {
  final base = await PdfGoogleFonts.robotoRegular();
  final bold = await PdfGoogleFonts.robotoBold();
  final mono = await PdfGoogleFonts.robotoMonoRegular();

  final doc = pw.Document();

  pw.Widget rowKV(String k, String v, {bool strong = false, double fs = 8}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(
            k,
            style: pw.TextStyle(font: strong ? bold : base, fontSize: fs),
          ),
        ),
        pw.Text(
          v,
          style: pw.TextStyle(font: strong ? bold : base, fontSize: fs),
        ),
      ],
    );
  }

  pw.Widget divider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Divider(height: 1, thickness: 1),
      );

  final paymentLabel = switch (sale.paymentMethod.toLowerCase()) {
    'cash' => 'Наличные',
    'card' => 'Безнал',
    'credit' => 'В долг',
    _ => sale.paymentMethod,
  };

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      orientation: pw.PageOrientation.portrait,
      margin: const pw.EdgeInsets.only(right: 18, top: 12, bottom: 12),
      build: (_) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'ЧЕК',
              style: pw.TextStyle(font: bold, fontSize: 10),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Дата: ${sale.date.toLocal()}',
              style: pw.TextStyle(font: base, fontSize: 7),
            ),
            if (sale.number.trim().isNotEmpty)
              pw.Text(
                '№ ${sale.number.trim()}',
                style: pw.TextStyle(font: base, fontSize: 7),
              ),
            divider(),
            for (final it in sale.items) ...[
              pw.Text(
                (it.product?.name ?? '').trim().isEmpty
                    ? 'Товар ${it.productId}'
                    : it.product!.name,
                style: pw.TextStyle(font: base, fontSize: 8),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${it.quantity} x ${money(it.price)}',
                    style: pw.TextStyle(font: mono, fontSize: 8),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    money(it.totalPrice),
                    style: pw.TextStyle(font: mono, fontSize: 8),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
            ],
            divider(),
            rowKV('ИТОГО', money(sale.totalAmount), strong: true),
            pw.SizedBox(height: 4),
            rowKV('Метод', paymentLabel),
            pw.SizedBox(height: 6),
            pw.Text(
              'Спасибо за покупку!',
              style: pw.TextStyle(font: base, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 35 * PdfPageFormat.mm),
          ],
        );
      },
    ),
  );

  return doc;
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
    await printer.print80mmSilently(
      () => _buildReceiptFromSale(sale, pageFormat: pageFormat),
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pos_desktop_clean/core/models/sale_model.dart'
    show SaleItemModel, SaleModel;
import 'package:pos_desktop_clean/core/print/print_service.dart';
import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/data/utils/app_theme.dart';
import 'package:pos_desktop_clean/features/data/utils/money.dart';
import 'package:pos_desktop_clean/features/domain/entities/payment.dart';
import 'package:pos_desktop_clean/features/domain/repositories/sale_repository.dart';
import 'package:pos_desktop_clean/features/presentation/state/pos_cubit.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/footer_panels_widget.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/live_data_text.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/payment_panel.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/quit_products_screen.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

class FooterStatus extends StatelessWidget {
  const FooterStatus({super.key});

  static const _mobileBp = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < _mobileBp) return const SizedBox.shrink();
        return const _FooterDesktop();
      },
    );
  }
}

class _FooterDesktop extends StatelessWidget {
  const _FooterDesktop();

  Future<pw.Document> _buildReceipt80mm(PosCubit cubit) async {
    final items = cubit.state.items;
    final total = cubit.total;
    final discountSum = cubit.discountSum;
    final received = cubit.state.received;
    final change = cubit.change.clamp(0, double.infinity);

    final base = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();
    final mono = await PdfGoogleFonts.robotoMonoRegular();

    final doc = pw.Document();

    pw.Widget rowKV(String k, String v, {bool strong = false, double fs = 8}) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
              child: pw.Text(k,
                  style:
                      pw.TextStyle(font: strong ? bold : base, fontSize: fs))),
          pw.Text(v,
              style: pw.TextStyle(font: strong ? bold : base, fontSize: fs)),
        ],
      );
    }

    pw.Widget divider() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Divider(height: 1, thickness: 1),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // ширина 80 мм, высота 200 мм
        orientation: pw.PageOrientation.portrait, // книжная
        margin: const pw.EdgeInsets.only(right: 18, top: 12, bottom: 12),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('ЧЕК (ТЕСТ)',
                  style: pw.TextStyle(font: bold, fontSize: 10),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 2),
              pw.Text('Дата: ${DateTime.now().toLocal()}',
                  style: pw.TextStyle(font: base, fontSize: 7)),
              divider(),
              for (final it in items) ...[
                pw.Text(it.product.name,
                    style: pw.TextStyle(font: base, fontSize: 8)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${it.qty} x ${money(it.product.price)}'
                      '${it.discount > 0 ? '  (-${it.discount.toStringAsFixed(0)}%)' : ''}',
                      style: pw.TextStyle(font: mono, fontSize: 8),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(money(it.sum),
                        style: pw.TextStyle(font: mono, fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],
              divider(),
              rowKV('Без скидок', money(total + discountSum)),
              rowKV('Скидка', money(discountSum)),
              rowKV('ИТОГО', money(total), strong: true),
              pw.SizedBox(height: 3),
              rowKV('Получено', money(received)),
              rowKV('Сдача', money(change), strong: true),
              pw.SizedBox(height: 4),
              rowKV(
                  'Метод',
                  switch (cubit.state.paymentKind) {
                    PaymentKind.cash => 'Наличные',
                    PaymentKind.card => 'Безнал',
                    PaymentKind.credit => 'В долг',
                  }),
              pw.SizedBox(height: 6),
              pw.Text('Спасибо за покупку!',
                  style: pw.TextStyle(font: base, fontSize: 8),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 35 * PdfPageFormat.mm),
            ],
          );
        },
      ),
    );

    return doc;
  }

  Future<void> _payByCardWithPrint(BuildContext context) async {
    final posCubit = context.read<PosCubit>();
    final auth = context.read<AuthTokenProvider>();

    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final storeId = auth.storeId?.trim() ?? '';
    final posId = auth.posId?.trim() ?? '';
    final userId = auth.users.isNotEmpty ? (auth.users.first.id ?? '') : '';

    if (key.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет posKey')));
      return;
    }
    if (deviceId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет deviceId')));
      return;
    }
    if (storeId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет storeId')));
      return;
    }
    if (posId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет posId')));
      return;
    }
    if (userId.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет userId')));
      return;
    }
    if (posCubit.state.items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Корзина пустая')));
      return;
    }

    final total = posCubit.total;
    final ok = await _confirmCardPayment(context, amount: money(total));
    if (!ok) return;

    posCubit.setPaymentKind(PaymentKind.card);
    posCubit.setReceived(total);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final saleItems = <SaleItemModel>[];
      for (final it in posCubit.state.items) {
        if (it.qty % 1 != 0) {
          throw Exception(
              'Дробное количество не поддерживается: ${it.product.name}');
        }
        final qty = it.qty.toInt();
        final price = it.product.price.round();
        final totalPrice = (it.product.price * it.qty).round();

        saleItems.add(
          SaleItemModel(
            productId: it.product.id,
            quantity: qty,
            price: price,
            totalPrice: totalPrice,
            id: '',
            saleId: '',
          ),
        );
      }

      final customerId = posCubit.state.activeCustomer?.id;

      final sale = SaleModel(
        localId: const Uuid().v4(),
        number: '',
        date: DateTime.now(),
        totalAmount: total.round(),
        paymentMethod: 'card', // ✅ сразу card
        posId: posId,
        storeId: storeId,
        userId: userId,
        accountId: userId,
        customerId: customerId,
        items: saleItems,
      );

      final repo = GetIt.I<SaleRepository>();
      final result =
          await repo.createSale(key: key, deviceId: deviceId, sale: sale);

      if (!context.mounted) return;
      Navigator.of(context).pop(); // закрыть лоадер

      if (result == CreateSaleResult.rejected) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Оплата не прошла'),
            content: const Text('Сервер отклонил продажу.'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Ок'),
              ),
            ],
          ),
        );
        return;
      }

      final printer = PrintService();

      await printer.print80mmSilently(() => _buildReceipt80mm(posCubit));

      await showDialog<void>(
        context: context,
        
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.45),
        builder: (ctx) {
          final message = result == CreateSaleResult.queued
              ? 'Нет сети: продажа добавлена в очередь.\nЧек распечатан.'
              : 'Продажа отправлена.\nЧек распечатан.';

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ success icon
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7), // light green
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF16A34A),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text(
                      'Оплата успешна',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Готово',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      posCubit.clearAfterPayment();
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).maybePop(); // если лоадер ещё открыт
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка безнала: $e')),
        );
      }
    }
  }

  Future<bool> _confirmCardPayment(
    BuildContext context, {
    required String amount,
  }) async {
    final theme = Theme.of(context);

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) {
        return Dialog(
          backgroundColor: ThemeColors.greyB,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // icon
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF), // light blue
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.credit_card_rounded,
                      color: Color(0xFF2563EB),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Безналичная оплата',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // amount card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Сумма к оплате',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          amount,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF111827),
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF111827),
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Отмена',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Оплатить',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Container(
        height: 182,
        decoration: BoxDecoration(
          color: const Color(0xFF2B3440),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                width: 190,
                height: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 6),
                        StreamBuilder(
                          stream: Stream.periodic(const Duration(seconds: 1)),
                          builder: (_, __) {
                            return Text(
                              TimeOfDay.now().format(context),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const LiveDateText(),
                    const Spacer(),
                    const Text(
                      'Касса-1\nНаименование Магаза',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Expanded(
              child: BlocBuilder<PosCubit, PosState>(
                builder: (context, state) {
                  final cubit = context.read<PosCubit>();
                  final total = cubit.total;
                  final discount = cubit.discountSum;
                  final beforeDiscount = total + discount;
                  return FooterControlsOnly(
                    smallAmountText: money(beforeDiscount),
                    bigAmountText: money(total),
                    onMinus: cubit.decrementSelectedQty,
                    onPlus: cubit.incrementSelectedQty,
                    onQuick: () async {
                      final products = List.generate(
                        20,
                        (i) => QuickProduct(
                            title: 'Наименование товара ... 2 строк',
                            price: 315.00),
                      );

                      final picked = await showQuickProductsDialog(
                        context,
                        products: products,
                      );

                      if (picked == null) return;
                    },
                    onCancel: () async {
                      final ok = await _confirmClearCart(context);
                      if (ok) cubit.clearAfterPayment();
                    },
                    onPayCard: () async {
                      await _payByCardWithPrint(context);
                    },
                    onPay: () => _showPaymentPanelCenter(context),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentPanelCenter(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'payment',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final panelWidth =
                      w >= 460 ? 420.0 : (w - 32).clamp(280.0, 420.0);

                  return Container(
                    width: panelWidth,
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const PaymentPanel(),
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero, // в центр
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}

Future<bool> _confirmClearCart(BuildContext context) async {
  final theme = Theme.of(context);

  final res = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: ThemeColors.greyB,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2), // light red
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Очистить корзину?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Все товары будут удалены. Продолжить?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF111827),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Да, очистить',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return res ?? false;
}

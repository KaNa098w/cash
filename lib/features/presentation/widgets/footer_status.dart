import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/features/presentation/widgets/quit_products_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:leemon_app/core/models/sale_model.dart'
    show ProductModel, SaleItemModel, SaleModel;
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/domain/entities/payment.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/footer_panels_widget.dart';
import 'package:leemon_app/features/presentation/widgets/live_data_text.dart';
import 'package:leemon_app/features/presentation/widgets/payment_panel.dart';
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

  Future<bool> _confirmRemoveCartItem(
    BuildContext context, {
    required String productName,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => TouchDeleteDialog(productName: productName),
        ) ??
        false;
  }


  Future<void> _payByCardWithPrint(BuildContext context) async {
    final posCubit = context.read<PosCubit>();
    final auth = context.read<AuthTokenProvider>();

    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final storeId = auth.storeId?.trim() ?? '';
    final posId = auth.posId?.trim() ?? '';
    final userId = auth.activeUserId?.trim() ?? '';
    final accountId = auth.accountId?.trim() ?? '';

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
    if (accountId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет accountId')));
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
    final pageFormat =
        auth.receiptPaperMm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
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
        accountId: accountId,
        posSessionId: auth.shiftId?.trim(),
        customerId: customerId,
        items: saleItems
            .asMap()
            .entries
            .map(
              (entry) => entry.value.copyWith(
                product: ProductModel(
                  id: posCubit.state.items[entry.key].product.id,
                  name: posCubit.state.items[entry.key].product.name,
                  measurementUnit: 'шт.',
                  arrivalCost: 0,
                  sellingPrice: posCubit.state.items[entry.key].product.price,
                  wholesalePrice: 0,
                ),
              ),
            )
            .toList(),
      );

      final repo = GetIt.I<SaleRepository>();
      final outcome =
          await repo.createSale(key: key, deviceId: deviceId, sale: sale);
      final result = outcome.result;
      final printedSale = outcome.sale;

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

      await printer.print80mmSilently(
        () => buildReceiptPdf(
          ReceiptPdfData(
            pageFormat: pageFormat,
            money: money,
            receiptDate: printedSale.date,
            receiptNumber:
                printedSale.number.trim().isEmpty
                    ? printedSale.localId
                    : printedSale.number.trim(),
            cashierName: (auth.activeUserName ?? '').trim().isEmpty
                ? userId
                : auth.activeUserName!.trim(),
            storeName: (() {
              final name = (auth.storeName ?? '').trim();
              if (name.isNotEmpty) return name;
              final posName = (auth.posName ?? '').trim();
              if (posName.isNotEmpty) return posName;
              return 'Магазин';
            })(),
            items: posCubit.state.items
                .map(
                  (it) => ReceiptPdfItem(
                    name: it.product.name,
                    quantity: it.qty,
                    unitPrice: it.product.price,
                    lineTotal: it.sum,
                    discountPercent: it.discount,
                  ),
                )
                .toList(),
            total: posCubit.total,
            discountSum: posCubit.discountSum,
            paymentMethodLabel: 'Безналичный',
            isCashPayment: false,
            received: posCubit.state.received,
            change: posCubit.change,
          ),
        ),
      );

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
    return LayoutBuilder(
      builder: (context, c) {
        final auth = context.watch<AuthTokenProvider>();
        final compact = c.maxWidth < 1200;
        final infoWidth = compact ? 152.0 : 190.0;
        final infoPad = compact ? 12.0 : 16.0;
        final clockSize = compact ? 26.0 : 34.0;
        final bottomInset = MediaQuery.of(context).viewPadding.bottom;
        final baseFooterHeight = compact ? 172.0 : 182.0;
        final footerHeight = baseFooterHeight + bottomInset;
        final posName = (auth.posName ?? '').trim();
        final storeName = (auth.storeName ?? '').trim();
        final footerTitle = '${posName.isEmpty ? 'Касса-1' : posName}\n'
            '${storeName.isEmpty ? 'Наименование магазина' : storeName}';

        return SizedBox(
          height: footerHeight,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF2B3440),
            ),
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.all(infoPad),
                  child: Container(
                    width: infoWidth,
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
                            Icon(Icons.access_time,
                                color: Colors.white, size: compact ? 18 : 20),
                            const SizedBox(width: 6),
                            StreamBuilder(
                              stream:
                                  Stream.periodic(const Duration(seconds: 1)),
                              builder: (_, __) {
                                return Text(
                                  TimeOfDay.now().format(context),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: clockSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const LiveDateText(),
                        SizedBox(height: compact ? 8 : 14),
                        Text(
                          footerTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        // На 1024x768 держим блок кнопок в "дизайн"-ширине,
                        // чтобы ряды были как в макете и не расползались.
                        maxWidth: compact ? 605 : double.infinity,
                      ),
                      child: BlocBuilder<PosCubit, PosState>(
                        builder: (context, state) {
                          final cubit = context.read<PosCubit>();
                          final total = cubit.total;
                          final discount = cubit.discountSum;
                          final beforeDiscount = total + discount;
                          return FooterControlsOnly(
                            smallAmountText: money(beforeDiscount),
                            bigAmountText: money(total),
                            onMinus: () async {
                              final idx = cubit.state.selectedItemIndex;
                              if (idx == null ||
                                  idx < 0 ||
                                  idx >= cubit.state.items.length) {
                                return;
                              }
                              final item = cubit.state.items[idx];
                              if (item.qty > 1) {
                                cubit.decrementSelectedQty();
                                return;
                              }
                              final confirmed = await _confirmRemoveCartItem(
                                context,
                                productName: item.product.name,
                              );
                              if (!confirmed) return;
                              cubit.removeAt(idx);
                            },
                            onPlus: cubit.incrementSelectedQty,
                            onQuick: () async {
                              final auth = context.read<AuthTokenProvider>();
                              final key = auth.posKey?.trim() ?? '';
                              if (key.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Нет posKey')),
                                );
                                return;
                              }

                              showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(
                                    child: CircularProgressIndicator()),
                              );

                              try {
                                final items = await context
                                    .read<ProductsCubit>()
                                    .loadPopularFirstPage(
                                      key: key,
                                      forceRefresh: false,
                                    );

                                if (!context.mounted) return;

                                Navigator.of(context, rootNavigator: true)
                                    .pop();

                                final picked = await showQuickProductsDialog(
                                  context,
                                  products: items,
                                );

                                if (picked == null) return;
                                cubit.addFromProductModel(picked);
                              } catch (e) {
                                if (!context.mounted) return;
                                Navigator.of(context, rootNavigator: true)
                                    .maybePop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Ошибка popular-products: $e')),
                                );
                              }
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class TouchDeleteDialog extends StatelessWidget {
  const TouchDeleteDialog({
    required this.productName,
  });

  final String productName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Container(
                //   width: 58,
                //   height: 58,
                //   decoration: BoxDecoration(
                //     color: const Color(0xFFFFF1EB),
                //     borderRadius: BorderRadius.circular(18),
                //   ),
                //   child: const Icon(
                //     Icons.delete_outline_rounded,
                //     color: Color(0xFFBE3A14),
                //     size: 30,
                //   ),
                // ),
                // const SizedBox(height: 18),
                const Text(
                  'Удалить товар',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Удалить товар "$productName" из корзины?',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Отмена',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: const Color(0xFFBE3A14),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Удалить',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
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
      ),
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

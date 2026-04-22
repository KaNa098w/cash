import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:leemon_app/features/presentation/widgets/quit_products_screen.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_state.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';
import 'package:leemon_app/features/presentation/widgets/conversion_product_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/footer_panels_widget.dart';
import 'package:leemon_app/features/presentation/widgets/live_data_text.dart';
import 'package:leemon_app/features/presentation/widgets/payment_panel.dart';

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final auth = context.watch<AuthTokenProvider>();
        final compact = c.maxWidth < 1200;
        final infoWidth = compact ? 152.0 : 190.0;
        final infoPad = compact ? 12.0 : 16.0;
        final clockSize = compact ? 22.0 : 22.0;
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
                            SvgPicture.asset(
                              'assets/svg/time.svg',
                              width: clockSize,
                              height: clockSize,
                              colorFilter: const ColorFilter.mode(
                                Colors.white54,
                                BlendMode.srcIn,
                              ),
                            ),
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
                          final hasItems = state.items.isNotEmpty;
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
                                  products: items
                                      .where((product) => !product.isUniversal)
                                      .toList(growable: false),
                                );

                                if (!context.mounted) return;
                                if (picked == null) return;
                                await addProductToCartWithConversionFlow(
                                  context,
                                  picked,
                                );
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
                              final productsState =
                                  context.read<ProductsCubit>().state;
                              final products = productsState is ProductsLoaded
                                  ? productsState.products
                                  : const [];
                              dynamic universalProduct;
                              for (final product in products) {
                                if (product.isUniversal) {
                                  universalProduct = product;
                                  break;
                                }
                              }

                              if (universalProduct == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Универсальный продукт недоступен. Выполните синхронизацию.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final amount =
                                  await _showUniversalAmountDialog(context);
                              if (!context.mounted || amount == null) return;
                              cubit.addUniversalProduct(
                                universalProduct,
                                price: amount,
                              );
                            },
                            onPay: hasItems
                                ? () => _showPaymentPanelCenter(context)
                                : null,
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
      barrierColor: Colors.black.withValues(alpha: 0.45),
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
                      w >= 625 ? 573.0 : (w - 32).clamp(280.0, 573.0);

                  return Container(
                    width: panelWidth,
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
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

Future<double?> _showUniversalAmountDialog(BuildContext context) {
  return showDialog<double>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _UniversalAmountDialog(),
  );
}

class _UniversalAmountDialog extends StatefulWidget {
  const _UniversalAmountDialog();

  @override
  State<_UniversalAmountDialog> createState() => _UniversalAmountDialogState();
}

class _UniversalAmountDialogState extends State<_UniversalAmountDialog> {
  String _text = '';

  double get _amount => double.tryParse(_text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _amount > 0;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Введите сумму',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 58,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    _text.isEmpty ? '0' : _text,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AmountKeypad(
                  text: _text,
                  showQuickRows: false,
                  onChanged: (value) => setState(() => _text = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: canConfirm
                            ? () => Navigator.of(context).pop(_amount)
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFFF9B32C),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Добавить ${money(_amount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
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

class TouchDeleteDialog extends StatelessWidget {
  const TouchDeleteDialog({
    super.key,
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

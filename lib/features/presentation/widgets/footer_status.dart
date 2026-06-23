import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
        final infoPad = compact ? 12.0 : 16.0;
        final bottomInset = MediaQuery.of(context).viewPadding.bottom;
        final baseFooterHeight = compact ? 172.0 : 182.0;
        final footerHeight = baseFooterHeight + bottomInset;
        final infoHeight = footerHeight - (infoPad * 2);
        final posName = (auth.posName ?? '').trim();
        final posLabel = auth.posIsTest
            ? '${posName.isEmpty ? 'Касса-1' : posName} · TEST'
            : (posName.isEmpty ? 'Касса-1' : posName);
        final storeName = (auth.storeName ?? '').trim();
        final showTariffNotice = auth.shouldShowTariffExpiryNotice;
        final tariffDaysLeft = auth.tariffDaysUntilExpiry ?? 0;

        return SizedBox(
          height: footerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF2B3440),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(infoPad),
                      child: SizedBox(
                        height: infoHeight,
                        width: infoHeight * (176 / 146),
                        child: FittedBox(
                          fit: BoxFit.fill,
                          child: SizedBox(
                            width: 176,
                            height: 146,
                            child: Container(
                              padding: EdgeInsets.zero,
                              decoration: BoxDecoration(
                                color: const Color(0xFF373D46),
                                borderRadius: BorderRadius.circular(16.6256),
                                border:
                                    Border.all(color: Colors.white, width: 1),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 21,
                                    top: 23,
                                    child: SvgPicture.asset(
                                      'assets/svg/time.svg',
                                      width: 21.5,
                                      height: 21.5,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.white,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 60,
                                    top: 15,
                                    width: 95,
                                    height: 38,
                                    child: StreamBuilder<int>(
                                      stream: Stream.periodic(
                                        const Duration(seconds: 1),
                                        (tick) => tick,
                                      ),
                                      builder: (_, __) {
                                        return FittedBox(
                                          alignment: Alignment.centerLeft,
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            DateFormat('HH:mm')
                                                .format(DateTime.now()),
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 36,
                                              fontWeight: FontWeight.w400,
                                              height: 1,
                                              letterSpacing: 0,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const Positioned(
                                    left: 21,
                                    top: 61,
                                    width: 134,
                                    height: 16,
                                    child: _FooterDateText(),
                                  ),
                                  Positioned(
                                    left: 21,
                                    right: 21,
                                    top: 96,
                                    height: 17,
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        posLabel,
                                        maxLines: 1,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 13.4,
                                          fontWeight: FontWeight.w400,
                                          height: 1,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 21,
                                    right: 21,
                                    top: 113,
                                    height: 17,
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        storeName.isEmpty
                                            ? 'Наименование Магаз'
                                            : storeName,
                                        maxLines: 1,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 13.4,
                                          fontWeight: FontWeight.w400,
                                          height: 1,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
                              final productsState =
                                  context.watch<ProductsCubit>().state;
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
                                  final confirmed =
                                      await _confirmRemoveCartItem(
                                    context,
                                    productName: item.product.name,
                                  );
                                  if (!confirmed) return;
                                  cubit.removeAt(idx);
                                },
                                onPlus: cubit.incrementSelectedQty,
                                onQuick: () async {
                                  final auth =
                                      context.read<AuthTokenProvider>();
                                  final key = auth.posKey?.trim() ?? '';
                                  if (key.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Нет posKey')),
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

                                    final picked =
                                        await showQuickProductsDialog(
                                      context,
                                      products: items
                                          .where(
                                              (product) => !product.isUniversal)
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
                                          content: Text(
                                              'Ошибка popular-products: $e')),
                                    );
                                  }
                                },
                                onCancel: () async {
                                  final ok = await _confirmClearCart(context);
                                  if (ok) cubit.clearAfterPayment();
                                },
                                onPayCard: universalProduct == null
                                    ? null
                                    : () async {
                                        final amount =
                                            await _showUniversalAmountDialog(
                                                context);
                                        if (!context.mounted ||
                                            amount == null) {
                                          return;
                                        }
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
              if (showTariffNotice)
                Positioned(
                  left: compact ? 10 : 12,
                  bottom: bottomInset + 9,
                  child: _TariffExpiryNotice(
                    daysLeft: tariffDaysLeft,
                    maxWidth: (c.maxWidth - 40).clamp(280.0, 454.0),
                  ),
                ),
            ],
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
                      color: Colors.transparent,
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

class _TariffExpiryNotice extends StatefulWidget {
  const _TariffExpiryNotice({
    required this.daysLeft,
    required this.maxWidth,
  });

  final int daysLeft;
  final double maxWidth;

  @override
  State<_TariffExpiryNotice> createState() => _TariffExpiryNoticeState();
}

class _TariffExpiryNoticeState extends State<_TariffExpiryNotice> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final daysText = _formatDays(widget.daysLeft);

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 15, right: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF5558),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Ваш тариф закончится через '),
                      TextSpan(
                        text: daysText,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFFFF33),
                          fontSize: 13.33,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.33,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => setState(() => _visible = false),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(24, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: SvgPicture.string(
                  _tariffNoticeCloseSvg,
                  width: 13,
                  height: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDays(int days) {
    if (days == 1) return '1 день';
    if (days >= 2 && days <= 4) return '$days дня';
    return '$days дней';
  }
}

const _tariffNoticeCloseSvg = '''
<svg width="13" height="13" viewBox="0 0 13 13" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M0.931763 11.3029L6.11743 6.11719M11.3031 0.931519L6.11743 6.11719M6.11743 6.11719L0.931763 0.931519M6.11743 6.11719L11.3031 11.3029" stroke="white" stroke-width="1.86343" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

class _FooterDateText extends StatelessWidget {
  const _FooterDateText();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(minutes: 1), (tick) => tick),
      builder: (_, __) {
        return FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            _capitalizeDate(
                DateFormat('d MMMM | EEEE', 'ru_RU').format(DateTime.now())),
            maxLines: 1,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        );
      },
    );
  }

  String _capitalizeDate(String value) {
    return value.split(' ').map((part) {
      if (part.isEmpty || part == '|') return part;
      return part[0].toUpperCase() + part.substring(1);
    }).join(' ');
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
                Text(
                  'Введите сумму',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
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
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
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
                        child: Text(
                          'Отмена',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
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
                          'Добавить',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
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

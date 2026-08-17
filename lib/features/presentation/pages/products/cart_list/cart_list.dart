import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/product_remote_datasource.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/domain/entities/cart_item.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';
import 'package:leemon_app/features/presentation/widgets/conversion_product_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/footer_status.dart'
    show TouchDeleteDialog;
import 'package:leemon_app/features/presentation/widgets/keypad_widget.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

const double kCartFs = 18;
const double kCartRowHeight = 52;

String _shortProductNameKeepEnd(String name, {int maxChars = 46}) {
  final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= maxChars) return normalized;

  final parts = normalized.split(' ');
  if (parts.length < 2) {
    return '${normalized.substring(0, maxChars - 3)}...';
  }

  final tail = parts.last;
  final prefixBudget = maxChars - 3 - tail.length;
  if (prefixBudget <= 1) {
    final endLen = (maxChars - 3).clamp(1, tail.length);
    return '...${tail.substring(tail.length - endLen)}';
  }

  var prefix = normalized.substring(0, prefixBudget).trimRight();
  final lastSpace = prefix.lastIndexOf(' ');
  if (lastSpace > 8) {
    prefix = prefix.substring(0, lastSpace).trimRight();
  }

  return '$prefix...$tail';
}

class CartList extends StatefulWidget {
  const CartList({super.key});

  @override
  State<CartList> createState() => _CartListState();
}

class _CartListState extends State<CartList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _rowKeyFor(int index) {
    return _rowKeys.putIfAbsent(index, GlobalKey.new);
  }

  Future<void> _openDiscountDialog(
    BuildContext context, {
    required int index,
    required CartItem item,
  }) async {
    context.read<PosCubit>().selectItem(index);
    if (item.product.isUniversal) return;

    final auth = context.read<AuthTokenProvider>();
    if (!auth.allowCustomSalePrices) {
      final cubit = context.read<PosCubit>();
      if (_canApplyAutomaticDiscount(item)) {
        final confirmed = await _confirmApplyAutomaticDiscount(
          context,
          productName: item.product.name,
          discountPercent: item.product.discountPercent,
        );
        if (!context.mounted || !confirmed) return;
        cubit.applyAvailableDiscount(index);
        return;
      }
      if (item.discountApplied && item.product.discountType == 'automatic') {
        final confirmed = await _confirmRemoveAutomaticDiscount(
          context,
          productName: item.product.name,
        );
        if (!context.mounted || !confirmed) return;
        cubit.removeAvailableDiscount(index);
      }
      return;
    }

    final action = await _showDiscountPriceDialog(
      context,
      item: item,
      canCustomPrice: auth.allowCustomSalePrices,
    );
    if (!context.mounted || action == null) return;

    final cubit = context.read<PosCubit>();
    switch (action.type) {
      case _DiscountActionType.applyAutomatic:
        cubit.applyAvailableDiscount(index);
      case _DiscountActionType.removeAutomatic:
        cubit.removeAvailableDiscount(index);
      case _DiscountActionType.setCustomPrice:
        final price = action.price;
        if (price != null) cubit.setPrice(index, price);
      case _DiscountActionType.clearCustomPrice:
        cubit.clearCustomPrice(index);
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(milliseconds: 900));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  PosUser? _activeUser(AuthTokenProvider auth) {
    final userId = (auth.activeUserId ?? '').trim();
    if (userId.isEmpty) return null;
    for (final user in auth.users) {
      if (user.id == userId) return user;
    }
    return null;
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showProductChangedDialog(
    BuildContext context, {
    required ProductModel product,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF7F1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF179D72),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Товар успешно изменён',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _PriceInfoPill(
                  label: product.measurementUnit,
                  value: money(product.sellingPrice),
                  accent: true,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF33CC99),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openProductEditDialog(
    BuildContext context, {
    required int index,
    required CartItem item,
  }) async {
    context.read<PosCubit>().selectItem(index);

    if (item.product.isUniversal) return;

    final productId = item.product.id.trim();
    if (productId.isEmpty) {
      _showSnack(context, 'Не найден ID товара');
      return;
    }

    final online = await _hasInternet();
    if (!context.mounted) return;
    if (!online) {
      _showSnack(
        context,
        'Изменить цену без интернета нельзя. Подключите интернет и попробуйте снова.',
      );
      return;
    }

    final auth = context.read<AuthTokenProvider>();
    final key = (auth.posKey ?? '').trim();
    final deviceId = (auth.deviceId ?? '').trim();
    final user = _activeUser(auth);
    final userId = (user?.id ?? auth.activeUserId ?? '').trim();
    final isDirector =
        user?.roles.any((role) => role.toLowerCase() == 'director') ?? false;

    if (key.isEmpty || deviceId.isEmpty || userId.isEmpty) {
      _showSnack(context, 'Не найдены данные кассы или кассира');
      return;
    }

    final updated = await showDialog<ProductModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ServerPriceDialog(
        item: item,
        isDirector: isDirector,
        onSubmit: ({
          required double sellingPrice,
          required String name,
          required MeasurementUnit measurementUnit,
          required String? refundAccessKey,
        }) async {
          final stillOnline = await _hasInternet();
          if (!stillOnline) {
            throw const _PriceChangeException(
              'Изменить цену без интернета нельзя. Подключите интернет и попробуйте снова.',
            );
          }
          return sl<ProductRemoteDataSource>().updateProduct(
            key: key,
            productId: productId,
            userId: userId,
            deviceId: deviceId,
            sellingPrice: sellingPrice,
            name: name,
            measurementUnit: measurementUnit,
            refundAccessKey: refundAccessKey,
          );
        },
      ),
    );

    if (!context.mounted || updated == null) return;
    context.read<ProductsCubit>().updateProduct(updated);
    context.read<PosCubit>().updateProductFromModel(index, updated);
    await _showProductChangedDialog(context, product: updated);
  }

  void _scrollSelectedItemIntoView(PosState state) {
    final selectedIndex = state.selectedItemIndex;
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= state.items.length) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[selectedIndex]?.currentContext;
      if (rowContext == null) return;

      Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.95,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    String formatQty(double v) {
      return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    }

    String formatQtyByUnit(double v, String unit, {double? conversionValue}) {
      if (ProductModel.isPiecesMeasurementUnit(unit)) {
        return v.round().toString();
      }
      return formatQty(v);
    }

    String formatStockQty(double v, String unit) {
      if (ProductModel.isPiecesMeasurementUnit(unit)) {
        return v.round().toString();
      }
      return formatQty(v);
    }

    String cartQtyLabel(CartItem item) {
      final base = formatQtyByUnit(item.qty, item.product.measurementUnit);
      return '$base ${item.product.measurementUnit}';
    }

    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: kCartFs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const _Header(), // просто подписи сверху
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: BlocConsumer<PosCubit, PosState>(
                  listenWhen: (previous, current) {
                    return previous.selectedItemIndex !=
                            current.selectedItemIndex ||
                        previous.items.length != current.items.length;
                  },
                  listener: (context, state) =>
                      _scrollSelectedItemIntoView(state),
                  builder: (context, state) {
                    final visibleRows =
                        state.items.length < 6 ? 6 : state.items.length;
                    return ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: visibleRows,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i >= state.items.length) {
                          return const _EmptyCartStripe();
                        }
                        final it = state.items[i];
                        final isSelected = state.selectedItemIndex == i;
                        return InkWell(
                          key: _rowKeyFor(i),
                          onTap: () => context.read<PosCubit>().selectItem(i),

                          // ✅ убираем визуальные эффекты нажатия/ховера
                          splashFactory: NoSplash.splashFactory,
                          overlayColor:
                              const WidgetStatePropertyAll(Colors.transparent),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,

                          borderRadius: BorderRadius.circular(14),
                          child: Card(
                            margin: EdgeInsets.zero,
                            elevation: 0,
                            clipBehavior: Clip.antiAlias,
                            color: isSelected
                                ? const Color(0xFFD3D3D3)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: SizedBox(
                              height: kCartRowHeight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // превью
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: ThemeColors.grey,
                                        border: Border.all(
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    const SizedBox(width: 15),

                                    // Наименование + метки
                                    Expanded(
                                      child: _PriceHoldTarget(
                                        onHoldComplete: it.product.isUniversal
                                            ? null
                                            : () => _openProductEditDialog(
                                                  context,
                                                  index: i,
                                                  item: it,
                                                ),
                                        child: Text(
                                          it.product.isUniversal
                                              ? _shortProductNameKeepEnd(
                                                  it.product.name)
                                              : '${_shortProductNameKeepEnd(it.product.name)} (${formatStockQty(it.product.quantity, it.product.measurementUnit)} ${it.product.measurementUnit})',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),

                                    // Цена
                                    SizedBox(
                                      width: 130,
                                      child: _PriceHoldTarget(
                                        onTap: it.product.isUniversal
                                            ? () async {
                                                context
                                                    .read<PosCubit>()
                                                    .selectItem(i);
                                                final price =
                                                    await _showUniversalPriceDialog(
                                                  context,
                                                  initialPrice:
                                                      it.effectiveUnitPrice,
                                                );
                                                if (!context.mounted ||
                                                    price == null) {
                                                  return;
                                                }
                                                context
                                                    .read<PosCubit>()
                                                    .setPrice(i, price);
                                              }
                                            : null,
                                        onHoldComplete: it.product.isUniversal
                                            ? null
                                            : () => _openProductEditDialog(
                                                  context,
                                                  index: i,
                                                  item: it,
                                                ),
                                        child: _PriceCell(it),
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    SizedBox(
                                      width: 170,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: InkWell(
                                          onTap: () {
                                            context
                                                .read<PosCubit>()
                                                .selectItem(i);
                                            if (it.product.hasConversion) {
                                              editConvertedCartItem(
                                                context,
                                                index: i,
                                                item: it,
                                              );
                                              return;
                                            }
                                            _showQtyDialog(
                                              context,
                                              index: i,
                                              initialQty: it.qty,
                                              productName: it.product.name,
                                              currentQtyLabel:
                                                  '${formatStockQty(it.product.quantity, it.product.measurementUnit)} ${it.product.measurementUnit}',
                                            );
                                          },

                                          // Нажатие срабатывает только по самому
                                          // блоку количества, а не по всей колонке.
                                          splashFactory: NoSplash.splashFactory,
                                          overlayColor:
                                              const WidgetStatePropertyAll(
                                                  Colors.transparent),
                                          splashColor: Colors.transparent,
                                          highlightColor: Colors.transparent,
                                          hoverColor: Colors.transparent,

                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Container(
                                            width: 90,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              cartQtyLabel(it),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                height: 1.15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 10),

                                    // Скидка
                                    SizedBox(
                                      width: 60,
                                      child: _DiscountCell(
                                        item: it,
                                        onTap: () => _openDiscountDialog(
                                          context,
                                          index: i,
                                          item: it,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Сумма
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        money(it.sum),
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4,
                                          letterSpacing: 0.27,
                                        ),
                                      ),
                                    ),

                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () =>
                                          context.read<PosCubit>().removeAt(i),
                                      tooltip: 'Удалить',
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<double?> _showUniversalPriceDialog(
  BuildContext context, {
  required double initialPrice,
}) async {
  String initialText = initialPrice.toStringAsFixed(2);
  initialText = initialText
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .replaceAll(RegExp(r'^$'), '0');

  return showDialog<double>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UniversalPriceDialog(initialText: initialText),
  );
}

class _UniversalPriceDialog extends StatefulWidget {
  const _UniversalPriceDialog({required this.initialText});

  final String initialText;

  @override
  State<_UniversalPriceDialog> createState() => _UniversalPriceDialogState();
}

class _UniversalPriceDialogState extends State<_UniversalPriceDialog> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
  }

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
                          'Сохранить ${money(_amount)}',
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

class _Header extends StatelessWidget {
  const _Header();

  Future<void> _applyAllAvailableDiscounts(BuildContext context) async {
    final cubit = context.read<PosCubit>();
    final productsCount = cubit.availableDiscountCount;
    if (productsCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В корзине нет товаров с доступной скидкой'),
        ),
      );
      return;
    }
    final confirmed = await _confirmApplyAllAvailableDiscounts(
      context,
      productsCount: productsCount,
    );
    if (!context.mounted || !confirmed) return;
    cubit.applyAllAvailableDiscounts();
  }

  @override
  Widget build(BuildContext context) {
    Widget cell(
      String t, {
      double w = 100,
      TextAlign align = TextAlign.right,
    }) =>
        SizedBox(
          width: w,
          child: Text(
            t,
            textAlign: align,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: kCartFs,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 65), // место под превью
          const Expanded(
            child: Text(
              'Наименование',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: kCartFs,
              ),
            ),
          ),
          cell('Цена', w: 100),
          const SizedBox(width: 30),
          cell('Количество', w: 170),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => _applyAllAvailableDiscounts(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: cell('Скидка', w: 80),
            ),
          ),
          const SizedBox(width: 25),
          cell('Сумма', w: 140),
          const SizedBox(width: 60),
        ],
      ),
    );
  }
}

class _PriceCell extends StatelessWidget {
  final CartItem item;
  const _PriceCell(this.item);

  @override
  Widget build(BuildContext context) {
    if (item.customUnitPrice != null) {
      return Text(
        money(item.effectiveUnitPrice),
        textAlign: TextAlign.right,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.4,
          letterSpacing: 0.27,
        ),
      );
    }

    final showDiscounted = item.discountApplied &&
        item.product.priceAfterDiscount > 0 &&
        item.product.priceAfterDiscount < item.product.price;

    if (showDiscounted) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(item.product.priceAfterDiscount),
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
              letterSpacing: 0.27,
            ),
          ),
        ],
      );
    }

    return Text(
      money(item.product.price),
      textAlign: TextAlign.right,
      style: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.27,
      ),
    );
  }
}

class _PriceHoldTarget extends StatefulWidget {
  const _PriceHoldTarget({
    required this.child,
    this.onTap,
    this.onHoldComplete,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onHoldComplete;

  @override
  State<_PriceHoldTarget> createState() => _PriceHoldTargetState();
}

class _PriceHoldTargetState extends State<_PriceHoldTarget> {
  Timer? _timer;
  bool _completed = false;

  void _startHold() {
    _timer?.cancel();
    _completed = false;
    if (widget.onHoldComplete == null) return;
    _timer = Timer(const Duration(seconds: 2), () {
      _completed = true;
      widget.onHoldComplete?.call();
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      onTap: () {
        if (_completed) return;
        widget.onTap?.call();
      },
      child: widget.child,
    );
  }
}

class _DiscountCell extends StatelessWidget {
  final CartItem item;
  final VoidCallback? onTap;
  const _DiscountCell({
    required this.item,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dt = item.product.discountType;
    final pct = item.product.discountPercent;
    final hasRealDiscount = _hasConfiguredDiscount(item);
    final pctStr = pct == pct.roundToDouble()
        ? pct.toInt().toString()
        : pct.toStringAsFixed(1);

    if (item.customUnitPrice != null) {
      final manualPct = _formatPercent(item.effectiveDiscountPercent);
      return GestureDetector(
        onTap: onTap,
        child: _singleChip('$manualPct%', filled: true, active: true),
      );
    }

    if (dt == null || dt.isEmpty || dt == 'forbidden' || !hasRealDiscount) {
      return GestureDetector(
        onTap: onTap,
        child: _singleChip('0%', filled: false, active: true),
      );
    }

    if (dt == 'fixed') {
      return GestureDetector(
        onTap: onTap,
        child: _singleChip('$pctStr%', filled: true, active: true),
      );
    }

    if (dt == 'automatic') {
      if (item.discountApplied) {
        return GestureDetector(
          onTap: onTap,
          child: _singleChip('$pctStr%', filled: true, active: true),
        );
      }
      return GestureDetector(
        onTap: onTap,
        child: _singleChip(
          '0%',
          filled: false,
          active: true,
          outlinedActive: true,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: _singleChip('0%', filled: false, active: true),
    );
  }

  bool _hasConfiguredDiscount(CartItem item) {
    return item.product.discountPercent > 0 &&
        item.product.priceAfterDiscount > 0 &&
        item.product.priceAfterDiscount < item.product.price;
  }

  String _formatPercent(double value) {
    if (value <= 0) return '0';
    final rounded = double.parse(value.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toStringAsFixed(1);
  }

  Widget _singleChip(
    String text, {
    required bool filled,
    required bool active,
    bool outlinedActive = false,
  }) {
    const softGreen = Color(0xFF258808);
    const softGreenBg = Color(0xFFCBE9C5);
    const softGreenBorder = Color(0xFFCBE9C5);
    final bg = active && filled ? softGreenBg : const Color(0xFFF3F4F6);
    final border = active && filled
        ? softGreenBorder
        : outlinedActive
            ? softGreen
            : const Color(0xFFE5E7EB);
    final fg = active && filled
        ? softGreen
        : outlinedActive
            ? softGreen
            : const Color(0xFF9CA3AF);

    return Container(
      constraints: const BoxConstraints(minWidth: 50, minHeight: 29.397),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14.3445),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: GoogleFonts.inter(
          fontSize: _chipFontSize(text),
          color: fg,
          fontWeight: FontWeight.w600,
          height: 1.4,
          letterSpacing: text.length > 4 ? 0 : 0.34,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  double _chipFontSize(String text) {
    if (text.length <= 4) return 16;
    if (text.length <= 5) return 14;
    if (text.length <= 6) return 12;
    return 10;
  }
}

bool _canApplyAutomaticDiscount(CartItem item) {
  return item.product.discountType == 'automatic' &&
      !item.discountApplied &&
      item.product.discountPercent > 0 &&
      item.product.priceAfterDiscount > 0 &&
      item.product.priceAfterDiscount < item.product.price;
}

Future<bool> _confirmApplyAutomaticDiscount(
  BuildContext context, {
  required String productName,
  required double discountPercent,
}) async {
  final pctStr = discountPercent == discountPercent.roundToDouble()
      ? discountPercent.toInt().toString()
      : discountPercent.toStringAsFixed(1);

  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _DiscountConfirmDialog(
          title: 'Применить скидку',
          message:
              'Применить возможную скидку $pctStr% для товара "$productName"?',
          confirmLabel: 'Применить',
          confirmColor: const Color(0xFF16A34A),
        ),
      ) ??
      false;
}

Future<bool> _confirmApplyAllAvailableDiscounts(
  BuildContext context, {
  required int productsCount,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _DiscountConfirmDialog(
          title: 'Применить скидки',
          message: 'Применить доступные скидки ко всем подходящим товарам '
              'в корзине? Товаров со скидкой: $productsCount.',
          confirmLabel: 'Да, применить',
          confirmColor: const Color(0xFF16A34A),
        ),
      ) ??
      false;
}

Future<bool> _confirmRemoveAutomaticDiscount(
  BuildContext context, {
  required String productName,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _DiscountConfirmDialog(
          title: 'Убрать скидку',
          message: 'Хотите убрать скидку у товара "$productName"?',
          confirmLabel: 'Убрать',
          confirmColor: const Color(0xFFBE3A14),
        ),
      ) ??
      false;
}

class _DiscountConfirmDialog extends StatelessWidget {
  const _DiscountConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
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
                          'Нет',
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
                          backgroundColor: confirmColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
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

enum _DiscountActionType {
  applyAutomatic,
  removeAutomatic,
  setCustomPrice,
  clearCustomPrice,
}

class _PriceChangeException implements Exception {
  const _PriceChangeException(this.message);

  final String message;
}

typedef _ServerPriceSubmit = Future<ProductModel> Function({
  required double sellingPrice,
  required String name,
  required MeasurementUnit measurementUnit,
  required String? refundAccessKey,
});

class _ServerPriceDialog extends StatefulWidget {
  const _ServerPriceDialog({
    required this.item,
    required this.isDirector,
    required this.onSubmit,
  });

  final CartItem item;
  final bool isDirector;
  final _ServerPriceSubmit onSubmit;

  @override
  State<_ServerPriceDialog> createState() => _ServerPriceDialogState();
}

class _ServerPriceDialogState extends State<_ServerPriceDialog> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();
  OverlayEntry? _nameKeyboardEntry;
  late String _priceText;
  late MeasurementUnit _measurementUnit;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.product.name);
    _priceText = widget.item.product.price.toStringAsFixed(2);
    _measurementUnit = MeasurementUnit.values.firstWhere(
      (unit) => unit.apiValue == widget.item.product.measurementUnit,
      orElse: () => MeasurementUnit.pieces,
    );
  }

  @override
  void dispose() {
    _nameKeyboardEntry?.remove();
    _nameKeyboardEntry = null;
    _nameFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _showNameKeyboard() {
    if (_submitting || _nameKeyboardEntry != null) return;
    _nameFocusNode.requestFocus();
    _nameController.selection = TextSelection.collapsed(
      offset: _nameController.text.length,
    );

    _nameKeyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _nameController,
            onEnter: _hideNameKeyboard,
            onClose: _hideNameKeyboard,
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_nameKeyboardEntry!);
  }

  void _hideNameKeyboard() {
    _nameKeyboardEntry?.remove();
    _nameKeyboardEntry = null;
    _nameFocusNode.unfocus();
  }

  double get _price =>
      double.tryParse(_priceText.replaceAll(',', '.').trim()) ?? 0;

  bool get _canSubmit {
    final normalizedPrice = _priceText.replaceAll(',', '.').trim();
    if (_submitting ||
        !RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalizedPrice) ||
        _price < 0) {
      return false;
    }
    final name = _nameController.text.trim();
    return name.isNotEmpty && name.length <= 255;
  }

  String get _productName {
    final name = widget.item.product.name.trim();
    return name.isEmpty ? widget.item.product.id : name;
  }

  String _errorMessage(Object error) {
    if (error is _PriceChangeException) return error.message;
    if (error is DioException) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      if (status == 422 && body is Map) {
        final errors = body['errors'];
        if (errors is Map) {
          final messages = errors.values
              .whereType<List>()
              .expand((items) => items)
              .map((message) => message.toString())
              .where((message) => message.trim().isNotEmpty)
              .toList(growable: false);
          if (messages.isNotEmpty) return messages.join('\n');
        }
      }
      return switch (status) {
        401 => 'Требуется действующий ключ менеджера',
        403 => body is Map && body['error_code'] == 'SUBSCRIPTION_INACTIVE'
            ? 'Тариф организации неактивен'
            : 'Изменение товара запрещено',
        404 => 'Товар не найден или принадлежит другой организации',
        422 => 'Проверьте заполнение полей',
        _ =>
          'Не удалось изменить товар. Проверьте интернет и попробуйте снова.',
      };
    }
    return 'Не удалось изменить товар. Попробуйте снова.';
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    if (!widget.isDirector) {
      await _scanAccessAndSubmit();
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final updated = await widget.onSubmit(
        sellingPrice: double.parse(_price.toStringAsFixed(2)),
        name: _nameController.text.trim(),
        measurementUnit: _measurementUnit,
        refundAccessKey: null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorMessage(e);
      });
    }
  }

  Future<void> _scanAccessAndSubmit() async {
    ProductModel? updatedProduct;
    Object? retryError;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final granted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RefundAccessDialog(
          title: 'Доступ к изменению цены',
          scanTitle: 'Сканируй штрих-код доступа менеджера',
          onScanned: (barcode) async {
            final accessKey = barcode.trim();
            if (accessKey.isEmpty) return false;

            try {
              updatedProduct = await widget.onSubmit(
                sellingPrice: double.parse(_price.toStringAsFixed(2)),
                name: _nameController.text.trim(),
                measurementUnit: _measurementUnit,
                refundAccessKey: accessKey,
              );
              return true;
            } catch (e) {
              if (e is DioException && e.response?.statusCode == 401) {
                return false;
              }
              retryError = e;
              return true;
            }
          },
        ),
      );

      if (!mounted) return;
      if (retryError != null) throw retryError!;
      if (granted == true && updatedProduct != null) {
        Navigator.of(context).pop(updatedProduct);
        return;
      }

      setState(() {
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = widget.item.effectiveUnitPrice;
    final roleText = widget.isDirector
        ? 'Доступ подтвержден: директор'
        : 'Для изменения товара нужен ключ менеджера';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: constraints.maxHeight,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF7F1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.price_change_rounded,
                            color: Color(0xFF179D72),
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Изменение товара',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      enabled: !_submitting,
                      maxLength: 255,
                      onChanged: (_) => setState(() => _error = null),
                      decoration: InputDecoration(
                        labelText: 'Название',
                        hintText: _productName,
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        suffixIcon: IconButton(
                          onPressed: _submitting ? null : _showNameKeyboard,
                          tooltip: 'Открыть клавиатуру',
                          icon: const Icon(Icons.keyboard_alt_outlined),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MeasurementUnit>(
                      initialValue: _measurementUnit,
                      decoration: InputDecoration(
                        labelText: 'Единица измерения',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: MeasurementUnit.values
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(unit.apiValue),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (unit) {
                              if (unit == null) return;
                              setState(() {
                                _measurementUnit = unit;
                                _error = null;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _PriceInfoPill(
                            label: 'Текущая',
                            value: money(currentPrice),
                            accent: false,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PriceInfoPill(
                            label: 'Новая',
                            value: money(_price),
                            accent: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 58,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF33CC99)),
                      ),
                      child: Text(
                        _priceText.isEmpty ? '0' : _priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AmountKeypad(
                      text: _priceText,
                      showQuickRows: false,
                      onChanged: _submitting
                          ? (_) {}
                          : (value) {
                              setState(() {
                                _priceText = value;
                                _error = null;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: widget.isDirector
                            ? const Color(0xFFEAF7F1)
                            : const Color(0xFFFFF7E6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.isDirector
                              ? const Color(0xFFBCE7D0)
                              : const Color(0xFFF3D19E),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.isDirector
                                ? Icons.verified_user_rounded
                                : Icons.key_rounded,
                            color: widget.isDirector
                                ? const Color(0xFF179D72)
                                : const Color(0xFFB7791F),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              roleText,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD15850)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFD15850),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFD15850),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _submitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: const Text(
                              'Отмена',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _canSubmit ? _submit : null,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: const Color(0xFF33CC99),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFA8DABD),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    widget.isDirector
                                        ? 'Сохранить'
                                        : 'Ввести ключ менеджера',
                                    style: const TextStyle(
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
        ),
      ),
    );
  }
}

class _DiscountAction {
  const _DiscountAction(this.type, {this.price});

  final _DiscountActionType type;
  final double? price;
}

Future<_DiscountAction?> _showDiscountPriceDialog(
  BuildContext context, {
  required CartItem item,
  required bool canCustomPrice,
}) {
  return showDialog<_DiscountAction>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _DiscountPriceDialog(
      item: item,
      canCustomPrice: canCustomPrice,
    ),
  );
}

class _DiscountPriceDialog extends StatefulWidget {
  const _DiscountPriceDialog({
    required this.item,
    required this.canCustomPrice,
  });

  final CartItem item;
  final bool canCustomPrice;

  @override
  State<_DiscountPriceDialog> createState() => _DiscountPriceDialogState();
}

class _DiscountPriceDialogState extends State<_DiscountPriceDialog> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = '0';
  }

  double get _price => double.tryParse(_text.replaceAll(',', '.')) ?? 0;

  String get _productName {
    final name = widget.item.product.name.trim();
    return name.isEmpty ? widget.item.product.id : name;
  }

  String get _manualPriceError {
    if (!widget.canCustomPrice) return 'Ручная цена выключена для магазина';
    if (_price <= 0) return 'Введите цену';
    return '';
  }

  bool get _canSaveManual => _manualPriceError.isEmpty;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasAutomatic = _canApplyAutomaticDiscount(item);
    final canRemoveAutomatic =
        item.discountApplied && item.product.discountType == 'automatic';
    final canClearCustom = item.customUnitPrice != null;
    final pct = item.product.discountPercent;
    final pctStr = pct == pct.roundToDouble()
        ? pct.toInt().toString()
        : pct.toStringAsFixed(1);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      backgroundColor: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Скидка и цена',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  _productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _PriceInfoPill(
                        label: 'Текущая',
                        value: money(item.effectiveUnitPrice),
                        accent: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (hasAutomatic || canRemoveAutomatic || canClearCustom) ...[
                  Row(
                    children: [
                      if (hasAutomatic)
                        Expanded(
                          child: _DiscountDialogButton(
                            label: 'Скидка $pctStr%',
                            icon: Icons.percent_rounded,
                            color: const Color(0xFF16A34A),
                            onPressed: () => Navigator.of(context).pop(
                              const _DiscountAction(
                                  _DiscountActionType.applyAutomatic),
                            ),
                          ),
                        ),
                      if (canRemoveAutomatic) ...[
                        if (hasAutomatic) const SizedBox(width: 10),
                        Expanded(
                          child: _DiscountDialogButton(
                            label: 'Убрать скидку',
                            icon: Icons.undo_rounded,
                            color: const Color(0xFFBE3A14),
                            onPressed: () => Navigator.of(context).pop(
                              const _DiscountAction(
                                  _DiscountActionType.removeAutomatic),
                            ),
                          ),
                        ),
                      ],
                      if (canClearCustom) ...[
                        if (hasAutomatic || canRemoveAutomatic)
                          const SizedBox(width: 10),
                        Expanded(
                          child: _DiscountDialogButton(
                            label: 'Обычная цена',
                            icon: Icons.restart_alt_rounded,
                            color: const Color(0xFF374151),
                            onPressed: () => Navigator.of(context).pop(
                              const _DiscountAction(
                                  _DiscountActionType.clearCustomPrice),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  height: 58,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: widget.canCustomPrice
                        ? const Color(0xFFF3F4F6)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _manualPriceError.isEmpty
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFFFCA5A5),
                    ),
                  ),
                  child: Text(
                    _text.isEmpty ? '0' : _text,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                if (_manualPriceError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _manualPriceError,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                AmountKeypad(
                  text: _text,
                  showQuickRows: false,
                  onChanged: widget.canCustomPrice
                      ? (value) => setState(() => _text = value)
                      : (_) {},
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Отмена',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canSaveManual
                            ? () => Navigator.of(context).pop(
                                  _DiscountAction(
                                    _DiscountActionType.setCustomPrice,
                                    price: _price,
                                  ),
                                )
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: const Color(0xFFF9B32C),
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          disabledForegroundColor: const Color(0xFF9CA3AF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Сохранить ${money(_price)}',
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

class _PriceInfoPill extends StatelessWidget {
  const _PriceInfoPill({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent ? const Color(0xFFBFDBFE) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: accent ? const Color(0xFF1D4ED8) : const Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountDialogButton extends StatelessWidget {
  const _DiscountDialogButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Диалог ввода количества
class _EmptyCartStripe extends StatelessWidget {
  const _EmptyCartStripe();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kCartRowHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

Future<void> _showQtyDialog(
  BuildContext context, {
  required int index,
  required double initialQty,
  required String productName,
  required String currentQtyLabel,
}) async {
  final cubit = context.read<PosCubit>();

  final controller = TextEditingController(
    text: initialQty.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''),
  );
  final focusNode = FocusNode();
  var didSelectInitialText = false;

  String normalize(String t) {
    // убираем ведущие нули, но оставляем "0." корректно
    if (t == '') return '';
    if (t.startsWith('0') && !t.startsWith('0.') && t.length > 1) {
      t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    }
    return t;
  }

  double? parseValue() {
    final text = controller.text.replaceAll(',', '.');
    return double.tryParse(text);
  }

  void selectAll() {
    final text = controller.text;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  int clampOffset(int offset, String text) {
    if (offset < 0) return 0;
    if (offset > text.length) return text.length;
    return offset;
  }

  void setText(
    StateSetter setState,
    String next, {
    int? selectionOffset,
  }) {
    final normalized = normalize(next);
    final offset =
        clampOffset(selectionOffset ?? normalized.length, normalized);
    setState(() {
      controller.text = normalized;
      controller.selection = TextSelection.collapsed(offset: offset);
    });
  }

  TextRange selectionRange() {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) {
      return TextRange(start: text.length, end: text.length);
    }

    final start = clampOffset(selection.start, text);
    final end = clampOffset(selection.end, text);
    return TextRange(
      start: start < end ? start : end,
      end: start < end ? end : start,
    );
  }

  bool isAllTextSelected() {
    final text = controller.text;
    if (text.isEmpty) return false;

    final range = selectionRange();
    return range.start == 0 && range.end == text.length;
  }

  void inputToken(StateSetter setState, String token) {
    var text = controller.text;
    final range = selectionRange();

    if (token == '⌫') {
      if (!range.isCollapsed) {
        setText(
          setState,
          text.replaceRange(range.start, range.end, ''),
          selectionOffset: range.start,
        );
        return;
      }

      if (range.start <= 0) return;
      setText(
        setState,
        text.replaceRange(range.start - 1, range.start, ''),
        selectionOffset: range.start - 1,
      );
      return;
    }

    if (token == ',') token = '.';

    if (token == '.') {
      final selected = text.substring(range.start, range.end);
      final textWithoutSelection =
          text.replaceRange(range.start, range.end, '');
      if (textWithoutSelection.contains('.')) return;
      token = textWithoutSelection.isEmpty && selected.isEmpty ? '0.' : '.';
    }

    if (!RegExp(r'^[0-9.]$').hasMatch(token)) return;

    text = text.replaceRange(range.start, range.end, token);
    if (text.startsWith('.') || text.startsWith(',')) {
      text = '0$text';
    }

    setText(setState, text, selectionOffset: text.length);
  }

  Future<void> submit(BuildContext dialogCtx) async {
    final value = parseValue();
    if (value == null || value < 0) return;

    if (value <= 0) {
      showDialog<bool>(
        context: dialogCtx,
        builder: (_) => TouchDeleteDialog(
          productName: cubit.state.items[index].product.name,
        ),
      ).then((confirmed) {
        if (confirmed != true) return;
        cubit.setQty(index, value);
        if (!dialogCtx.mounted) return;
        Navigator.of(dialogCtx).pop();
      });
      return;
    }

    final updated = await setCartItemQuantityWithMarking(
      dialogCtx,
      index: index,
      quantity: value,
    );
    if (!updated || !dialogCtx.mounted) return;
    Navigator.of(dialogCtx).pop();
  }

  void handleKey(
    KeyEvent event,
    StateSetter setState,
    BuildContext dialogCtx,
  ) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      submit(dialogCtx);
      return;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(dialogCtx).pop();
      return;
    }
    if (key == LogicalKeyboardKey.backspace) {
      inputToken(setState, '⌫');
      return;
    }

    final character = event.character ?? key.keyLabel;
    if (RegExp(r'^[0-9]$').hasMatch(character)) {
      inputToken(setState, character);
      return;
    }
    if (character == '.' || character == ',') {
      inputToken(setState, character);
    }
  }

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        final colorScheme = theme.colorScheme;

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: kCartFs),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                if (!didSelectInitialText) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!focusNode.hasFocus) {
                      focusNode.requestFocus();
                    }
                    selectAll();
                    didSelectInitialText = true;
                    if (ctx.mounted) {
                      setState(() {});
                    }
                  });
                }

                return KeyboardListener(
                  focusNode: focusNode,
                  autofocus: true,
                  onKeyEvent: (event) => handleKey(event, setState, dialogCtx),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 430,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // заголовок + крестик
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Изменить количество',
                                  style: TextStyle(
                                    fontSize: kCartFs,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F7F8),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 18,
                                      color: Color(0xFF456B5A),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Остаток на складе: $currentQtyLabel',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF374151),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // "экран" с текущим значением
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color:
                                    colorScheme.primary.withValues(alpha: 0.4),
                                width: 1.2,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.center,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isAllTextSelected()
                                      ? colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    controller.text.isEmpty
                                        ? '0'
                                        : controller.text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: isAllTextSelected()
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // сам цифровой блок – переиспользуем твой _Keypad
                          Keypad(
                            keyHeight: 54,
                            fontSize: 20,
                            onTap: (token) {
                              inputToken(setState, token);
                              focusNode.requestFocus();
                            },
                          ),

                          const SizedBox(height: 12),

                          // кнопки действий
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    fixedSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Отмена',
                                    style: TextStyle(
                                      fontSize: kCartFs,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final value = parseValue();
                                    if (value != null && value >= 0) {
                                      if (value <= 0) {
                                        showDialog<bool>(
                                          context: dialogCtx,
                                          builder: (_) => TouchDeleteDialog(
                                            productName: cubit.state
                                                .items[index].product.name,
                                          ),
                                        ).then((confirmed) {
                                          if (confirmed != true) return;
                                          cubit.setQty(index, value);
                                          if (!dialogCtx.mounted) return;
                                          Navigator.of(dialogCtx).pop();
                                        });
                                        return;
                                      }
                                      final updated =
                                          await setCartItemQuantityWithMarking(
                                        dialogCtx,
                                        index: index,
                                        quantity: value,
                                      );
                                      if (!updated || !dialogCtx.mounted) {
                                        return;
                                      }
                                      Navigator.of(dialogCtx).pop();
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    fixedSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    backgroundColor: ThemeColors.green1,
                                  ),
                                  child: const Text(
                                    'Готово',
                                    style: TextStyle(
                                      fontSize: kCartFs,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
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
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
    focusNode.dispose();
  }
}

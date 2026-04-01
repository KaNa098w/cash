import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/footer_status.dart'
    show TouchDeleteDialog;
import 'package:leemon_app/features/presentation/widgets/keypad_widget.dart';
import 'package:leemon_app/features/presentation/widgets/payment_panel.dart';

const double kCartFs = 18;

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

class CartList extends StatelessWidget {
  const CartList({super.key});

  @override
  Widget build(BuildContext context) {
    String formatQty(double v) {
      return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    }

    double displayQty(double v, double? conversionValue, String unit) {
      if (conversionValue != null && conversionValue > 0) {
        return v * conversionValue;
      }
      return v;
    }

    String formatQtyByUnit(double v, String unit, {double? conversionValue}) {
      final shown = displayQty(v, conversionValue, unit);
      if (ProductModel.isPiecesMeasurementUnit(unit)) {
        return shown.round().toString();
      }
      return formatQty(shown);
    }

    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: kCartFs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const _Header(), // просто подписи сверху
            const SizedBox(height: 8),
            Expanded(
              child: BlocBuilder<PosCubit, PosState>(
                builder: (context, state) {
                  return ListView.builder(
                    itemCount: state.items.length,
                    itemBuilder: (context, i) {
                      final it = state.items[i];
                      final isSelected = state.selectedItemIndex == i;
                      return InkWell(
                        onTap: () => context.read<PosCubit>().selectItem(i),

                        // ✅ убираем визуальные эффекты нажатия/ховера
                        splashFactory: NoSplash.splashFactory,
                        overlayColor:
                            MaterialStatePropertyAll(Colors.transparent),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        hoverColor: Colors.transparent,

                        borderRadius: BorderRadius.circular(14),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          color: isSelected
                              ? const Color(0xFFD3D3D3)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
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
                                const SizedBox(width: 20),

                                // Наименование + метки
                                Expanded(
                                  child: Text(
                                    '${_shortProductNameKeepEnd(it.product.name)} (${formatQtyByUnit(it.product.quantity, it.product.measurementUnit, conversionValue: it.product.conversionValue)} ${it.product.measurementUnit})',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                                // Цена
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    money(it.product.price),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: kCartFs),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                SizedBox(
                                  width: 120,
                                  child: InkWell(
                                    onTap: () {
                                      context.read<PosCubit>().selectItem(i);
                                      _showQtyDialog(
                                        context,
                                        index: i,
                                        initialQty: it.qty,
                                      );
                                    },

                                    // убираем эффекты как и в строке
                                    splashFactory: NoSplash.splashFactory,
                                    overlayColor:
                                        const MaterialStatePropertyAll(
                                            Colors.transparent),
                                    splashColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                    hoverColor: Colors.transparent,

                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                            // тот же фон что и у выбранной карточки
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${formatQtyByUnit(it.qty, it.product.measurementUnit, conversionValue: it.product.conversionValue)} ${it.product.measurementUnit}',
                                        textAlign: TextAlign.center,
                                        style:
                                            const TextStyle(fontSize: kCartFs),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 40),

                                // Скидка
                                SizedBox(
                                  width: 70,
                                  child: _DiscountChip(
                                    it.discount.toStringAsFixed(0),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Сумма
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    money(it.sum),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: kCartFs,
                                      fontWeight: FontWeight.w600,
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
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

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
          const SizedBox(width: 40), // место под превью
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
          const SizedBox(width: 25),
          cell('Количество', w: 120),
          const SizedBox(width: 25),
          cell('Скидка', w: 70),
          const SizedBox(width: 25),
          cell('Сумма', w: 140),
          const SizedBox(width: 60),
        ],
      ),
    );
  }
}

class _DiscountChip extends StatelessWidget {
  final String text;
  const _DiscountChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD1F2D7)),
      ),
      child: Text(
        '$text%',
        style: const TextStyle(
          fontSize: kCartFs,
          color: Color(0xFF16A34A),
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Диалог ввода количества
Future<void> _showQtyDialog(
  BuildContext context, {
  required int index,
  required double initialQty,
}) async {
  final cubit = context.read<PosCubit>();

  final controller = TextEditingController(
    text: initialQty.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''),
  );

  String _normalize(String t) {
    // убираем ведущие нули, но оставляем "0." корректно
    if (t == '') return '';
    if (t.startsWith('0') && !t.startsWith('0.') && t.length > 1) {
      t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    }
    return t;
  }

  double? _parseValue() {
    final text = controller.text.replaceAll(',', '.');
    return double.tryParse(text);
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      final theme = Theme.of(dialogCtx);
      final colorScheme = theme.colorScheme;

      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: kCartFs),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 380,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                      const SizedBox(height: 8),

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
                            color: colorScheme.primary.withOpacity(0.4),
                            width: 1.2,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            controller.text.isEmpty ? '0' : controller.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: kCartFs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // сам цифровой блок – переиспользуем твой _Keypad
                      Keypad(
                        onTap: (token) {
                          var t = controller.text;

                          if (token == '⌫') {
                            if (t.isNotEmpty) {
                              t = t.substring(0, t.length - 1);
                            }
                            t = _normalize(t);
                            setState(() {
                              controller.text = t;
                            });
                            return;
                          }

                          if (token == '.') {
                            if (!t.contains('.')) {
                              t = t.isEmpty ? '0.' : '$t.';
                            }
                          } else {
                            // цифра
                            t = t == '0' ? token : '$t$token';
                          }

                          t = _normalize(t);

                          setState(() {
                            controller.text = t;
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      // кнопки действий
                      Row(
                        children: [
                          Expanded(
                            child: FlatGrey(
                              text: 'Отмена',
                              onTap: () => Navigator.of(dialogCtx).pop(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final value = _parseValue();
                                if (value != null && value >= 0) {
                                  if (value <= 0) {
                                    showDialog<bool>(
                                      context: dialogCtx,
                                      builder: (_) => TouchDeleteDialog(
                                        productName:
                                            cubit.state.items[index].product.name,
                                      ),
                                    ).then((confirmed) {
                                      if (confirmed != true) return;
                                      cubit.setQty(index, value);
                                      Navigator.of(dialogCtx).pop();
                                    });
                                    return;
                                  }
                                  cubit.setQty(index, value);
                                  Navigator.of(dialogCtx).pop();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
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
              );
            },
          ),
        ),
      );
    },
  );
}

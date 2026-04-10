import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/footer_status.dart'
    show TouchDeleteDialog;
import 'package:leemon_app/features/presentation/widgets/keypad_widget.dart';

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
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: BlocBuilder<PosCubit, PosState>(
                  builder: (context, state) {
                    final visibleRows =
                        state.items.length < 6 ? 6 : state.items.length;
                    return ListView.separated(
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
                                          productName: it.product.name,
                                          currentQtyLabel:
                                              '${formatQtyByUnit(it.product.quantity, it.product.measurementUnit, conversionValue: it.product.conversionValue)} ${it.product.measurementUnit}',
                                        );
                                      },

                                      // убираем эффекты как и в строке
                                      splashFactory: NoSplash.splashFactory,
                                      overlayColor:
                                          const WidgetStatePropertyAll(
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
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${formatQtyByUnit(it.qty, it.product.measurementUnit, conversionValue: it.product.conversionValue)} ${it.product.measurementUnit}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: kCartFs),
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

  void submit(BuildContext dialogCtx) {
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

    cubit.setQty(index, value);
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
                                  onPressed: () {
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
                                      cubit.setQty(index, value);
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

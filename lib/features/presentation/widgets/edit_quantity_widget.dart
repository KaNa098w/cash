import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';
import 'package:leemon_app/features/presentation/widgets/dialog_primary_button.dart';
import 'package:leemon_app/features/presentation/widgets/footer_status.dart'
    show TouchDeleteDialog;

Future<void> editSelectedQty(BuildContext context) async {
  final cubit = context.read<PosCubit>();
  final state = cubit.state;
  final idx = state.selectedItemIndex;

  if (idx == null || idx < 0 || idx >= state.items.length) return;

  final item = state.items[idx];
  final unit = item.product.measurementUnit;
  final isPieces = ProductModel.isPiecesMeasurementUnit(unit);
  final conversionValue = item.product.conversionValue;

  String formatQty(num v) {
    final shown = (conversionValue != null && conversionValue > 0)
        ? v * conversionValue
        : v.toDouble();
    if (isPieces) return v.round().toString();
    var s = shown.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    return s.isEmpty ? '0' : s;
  }

  final controller = TextEditingController(text: formatQty(item.qty));
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;

        final isMobile = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS);

        double? parseQty(String raw) {
          final t = raw.trim().replaceAll(',', '.');
          if (t.isEmpty) return 0;
          final parsed = double.tryParse(t);
          if (parsed == null) return null;
          if (isPieces && parsed % 1 != 0) return null;
          return parsed;
        }

        void setControllerText(StateSetter setState, String next) {
          // Мягкая нормализация: запятую в точку
          final v = next.replaceAll(',', '.');
          setState(() {
            controller.text = v;
            controller.selection =
                TextSelection.collapsed(offset: controller.text.length);
          });
        }

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                final value = parseQty(controller.text);
                final isValid = value != null && value >= 0;
                final errorText = !isValid
                    ? isPieces
                        ? 'Для товара в штуках вводите только целое число'
                        : 'Введите корректное число (≥ 0)'
                    : null;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Material(
                    color: cs.surface,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Изменить количество',
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Закрыть',
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Optional: информация по позиции (если у модели есть название)
                            // Подстрой под свою модель item (name/title/sku и т.д.)
                            _ItemHintCard(
                              title: item.product.name,
                              subtitle: 'Текущее: ${formatQty(item.qty)} $unit',
                            ),

                            const SizedBox(height: 12),

                            // Большое отображение + ручной ввод (на desktop можно печатать)
                            _QtyDisplayCard(
                              controller: controller,
                              readOnly:
                                  isMobile, // на мобиле не открываем системную клаву
                              allowDecimal: !isPieces,
                              errorText: errorText,
                              onClear: () => setControllerText(setState, '0'),
                              onBackspace: () {
                                final t = controller.text;
                                if (t.isEmpty) return;
                                setControllerText(
                                    setState, t.substring(0, t.length - 1));
                              },
                            ),

                            const SizedBox(height: 12),

                            // Keypad
                            AmountKeypad(
                              text: controller.text,
                              allowDecimal: !isPieces,
                              showQuickRows: true,
                              // Для qty обычно лучше небольшие шаги (а не +200/+500)
                              rows: const [
                                ['+1', '+5', '+10'],
                                ['+20', '+50', '+100'],
                              ],
                              onChanged: (next) =>
                                  setControllerText(setState, next),
                            ),

                            const SizedBox(height: 14),

                            // Actions
                            Row(
                              children: [
                                Expanded(
                                  child: DialogSecondaryButton(
                                    label: 'Отмена',
                                    onPressed: () => Navigator.of(ctx).pop(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DialogPrimaryButton(
                                    label: 'Сохранить',
                                    enabled: isValid,
                                    onPressed: () async {
                                      final v = parseQty(controller.text) ?? 0;
                                      final normalized = isPieces
                                          ? v.roundToDouble()
                                          : (v * 100).round() / 100;

                                      if (normalized <= 0) {
                                        final confirmed =
                                            await showDialog<bool>(
                                                  context: ctx,
                                                  builder: (_) =>
                                                      TouchDeleteDialog(
                                                    productName:
                                                        item.product.name,
                                                  ),
                                                ) ??
                                                false;
                                        if (!confirmed) return;
                                      }

                                      cubit.setQty(idx, normalized);
                                      Navigator.of(ctx).pop();
                                    },
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
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

class _ItemHintCard extends StatelessWidget {
  const _ItemHintCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _QtyDisplayCard extends StatelessWidget {
  const _QtyDisplayCard({
    required this.controller,
    required this.readOnly,
    required this.allowDecimal,
    required this.errorText,
    required this.onClear,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final bool readOnly;
  final bool allowDecimal;
  final String? errorText;
  final VoidCallback onClear;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: errorText != null
              ? cs.error.withOpacity(0.55)
              : cs.outlineVariant.withOpacity(0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: readOnly,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: allowDecimal),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      allowDecimal
                          ? RegExp(r'^[0-9]*[.,]?[0-9]*$')
                          : RegExp(r'^[0-9]*$'),
                    ),
                  ],
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0',
                    hintTextDirection: TextDirection.ltr,
                    hintStyle:
                        Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              color: cs.onSurfaceVariant.withOpacity(0.6),
                            ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Очистить',
                onPressed: onClear,
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                tooltip: 'Удалить символ',
                onPressed: onBackspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.error),
            ),
          ],
          if (readOnly) ...[
            const SizedBox(height: 6),
            Text(
              'Ввод через клавиатуру ниже',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

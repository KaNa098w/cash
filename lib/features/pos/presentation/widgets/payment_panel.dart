import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import '../../../../core/utils/money.dart';
import '../state/pos_cubit.dart';
import '../../domain/entities/payment.dart';

class PaymentPanel extends StatelessWidget {
  const PaymentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    const darkText = Color(0xFF111827);
    const subText = Color(0xFF6B7280);
    const blue = Color(0xFF3B82F6);
    const red = Color(0xFFF87171);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: BlocBuilder<PosCubit, PosState>(
          builder: (context, state) {
            final cubit = context.read<PosCubit>();
            final total = cubit.total;
            final discountSum = cubit.discountSum;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Заголовок + большая синяя сумма
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Итого',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: darkText,
                                  ),
                                ),
                                Text(
                                  '${money(total)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: blue,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _lineKV('Без скидок', money(total + discountSum),
                                subText),
                            const SizedBox(height: 4),
                            _lineKV('Скидка', money(discountSum), subText),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Две цветные кнопки оплаты
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        text: 'Наличный',
                        color: blue,
                        icon: Icons.account_balance_wallet_outlined,
                        selected: state.paymentKind == PaymentKind.cash,
                        onTap: () => cubit.setPaymentKind(PaymentKind.cash),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceButton(
                        text: 'Безналичный',
                        color: red,
                        icon: Icons.credit_card_outlined,
                        selected: state.paymentKind == PaymentKind.card,
                        onTap: () => cubit.setPaymentKind(PaymentKind.card),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Серые «пилюли»
                Row(
                  children: [
                    Expanded(
                      child: _Pill(text: 'Без сдачи / Перечисл', onTap: () {}),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Pill(
                        text: 'В долг',
                        onTap: () => cubit.setPaymentKind(PaymentKind.credit),
                        selected: state.paymentKind == PaymentKind.credit,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _LabeledField(
                  label: 'Наличный расчет',
                  hintText: '',
                  onChanged: (v) => cubit.setReceived(double.tryParse(
                        v.replaceAll(',', '.'),
                      ) ??
                      0),
                ),

                const SizedBox(height: 12),

                // Сдача
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Сдача', style: TextStyle(fontSize: 16)),
                    Text(
                      '${money(cubit.change.clamp(0, double.infinity))}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Клавиатура 3x4 серые кнопки
                _Keypad(
                  onTap: (token) {
                    if (token == '⌫') {
                      final s = state.received.toStringAsFixed(2);
                      final next =
                          s.isNotEmpty ? s.substring(0, s.length - 1) : '';
                      cubit.setReceived(double.tryParse(next) ?? 0);
                      return;
                    }
                    final raw = state.received == 0
                        ? token
                        : '${state.received.toStringAsFixed(2)}$token';
                    final cleaned = raw.replaceAll('..', '.');
                    cubit.setReceived(
                        double.tryParse(cleaned) ?? state.received);
                  },
                ),

                const SizedBox(height: 8),

                // Быстрые суммы
                _QuickRows(
                  rows: const [
                    ['+200', '+500', '+1 000'],
                    ['+2 000', '+5 000', '+10 000'],
                  ],
                  onTap: (v) {
                    final inc = int.parse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                    cubit.setReceived((state.received) + inc);
                  },
                ),

                const SizedBox(height: 8),
                Spacer(),

                // Нижний ряд: Количества, -, +
                Row(
                  children: [
                    Expanded(
                        child: _FlatGrey(text: 'Количество', onTap: () {})),
                    const SizedBox(width: 8),
                    _SquareGrey(text: '–', onTap: () {}),
                    const SizedBox(width: 8),
                    _SquareGrey(text: '+', onTap: () {}),
                  ],
                ),

                const SizedBox(height: 10),

                // Отмена / ОПЛАТА
                Row(
                  children: [
                    Expanded(
                      child: _FlatGrey(
                        text: 'Отмена',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 49,
                        width: 200,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.green1,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            // TODO: оплатить
                          },
                          child: const Text(
                            'ОПЛАТА',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: .5,
                                fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _lineKV(String k, String v, Color sub) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k,
            style: TextStyle(
              color: sub,
              fontSize: 10,
            )),
        Text(v,
            style: TextStyle(
                color: sub, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ===== UI атомы под макет =====

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.text,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : color.withOpacity(.18);
    final fg = selected ? Colors.white : color;
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: fg),
        label: Text(
          text,
          style:
              TextStyle(fontWeight: FontWeight.w400, color: fg, fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.onTap, this.selected = false});

  final String text;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF9CA3AF) : const Color(0xFFD1D5DB);
    final fg = selected ? Colors.white : const Color(0xFF111827);
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11)),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.onChanged,
    this.hintText,
  });

  final String label;
  final String? hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF3B82F6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
              color: blue,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 6),
        TextField(
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: blue, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: blue, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onTap});

  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    const keyGrey = Color(0xFF999999);
    const moneyGrey = Color(0xFFD9D9D9);

    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', '⌫'],
    ];

    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (int i = 0; i < r.length; i++) ...[
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => onTap(r[i]),
                        style: TextButton.styleFrom(
                          backgroundColor: keyGrey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          r[i],
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i != r.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _QuickRows extends StatelessWidget {
  const _QuickRows({required this.rows, required this.onTap});

  final List<List<String>> rows;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(
              bottom: 8,
            ),
            child: Row(
              children: [
                for (int i = 0; i < r.length; i++) ...[
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => onTap(r[i]),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9D9D9),
                          side: BorderSide(color: Colors.transparent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          r[i],
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i != r.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FlatGrey extends StatelessWidget {
  const _FlatGrey({
    required this.text,
    required this.onTap,
    this.width = 100,
    this.height = 44,
  });

  final String text;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(Size(width, height)),
          fixedSize: MaterialStateProperty.all(Size(width, height)),
          padding: MaterialStateProperty.all(EdgeInsets.zero),
          backgroundColor: MaterialStateProperty.all(const Color(0xFFD1D5DB)),
          foregroundColor: MaterialStateProperty.all(const Color(0xFF111827)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SquareGrey extends StatelessWidget {
  const _SquareGrey({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 44,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFD1D5DB),
          foregroundColor: const Color(0xFF111827),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w300, fontSize: 18)),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pos_desktop_clean/core/print/print_service.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import 'package:printing/printing.dart';
import '../../../../core/utils/money.dart';
import '../state/pos_cubit.dart';
import '../../domain/entities/payment.dart';

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key});

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  final _cashCtrl = TextEditingController();

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  void _applyTextToState(BuildContext context, String text) {
    final cubit = context.read<PosCubit>();
    final normalized = text.replaceAll(',', '.');
    final value = double.tryParse(normalized) ?? 0;
    cubit.setReceived(value);
  }

  void _setText(BuildContext context, String text) {
    _cashCtrl.text = text;
    _cashCtrl.selection = TextSelection.collapsed(offset: text.length);
    _applyTextToState(context, text);
  }

  String _fmt(double v) {
    // Без разделителей, удобнее для редактирования
    // Обрезаем лишние нули в дробной части
    final s = v.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  final _printService = PrintService();

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

  @override
  Widget build(BuildContext context) {
    const darkText = Color(0xFF111827);
    const subText = Color(0xFF6B7280);
    const blue = Color(0xFF3B82F6);
    const red = Color(0xFFF87171);

    final kind = context.select((PosCubit c) => c.state.paymentKind);
    final fieldLabel = switch (kind) {
      PaymentKind.cash => 'Наличный расчет',
      PaymentKind.card => 'Безналичный расчет',
      PaymentKind.credit => 'В долг',
    };

    final fieldColor = switch (kind) {
      PaymentKind.cash => const Color(0xFF3B82F6), // blue
      PaymentKind.card => const Color(0xFFF87171), // red
      PaymentKind.credit => const Color(0xFF9CA3AF), // grey
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: BlocConsumer<PosCubit, PosState>(
          listenWhen: (prev, curr) => prev.received != curr.received,
          listener: (context, state) {
            // если значение поменялось НЕ из поля — синхронизируем поле
            final text = _fmt(state.received);
            if (_cashCtrl.text != text) {
              _setText(context, text);
            }
          },
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
                                  money(total),
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
                        svgAsset: 'assets/svg/card.svg',
                        selected: state.paymentKind == PaymentKind.cash,
                        onTap: () => cubit.setPaymentKind(PaymentKind.cash),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceButton(
                        text: 'Безналичный',
                        color: red,
                        svgAsset: 'assets/svg/card_icon.svg',
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
                        child:
                            _Pill(text: 'Без сдачи / Перечисл', onTap: () {})),
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

                // Поле "Наличный расчет" — управляемое
                _LabeledField(
                  label: fieldLabel,
                  color: fieldColor,
                  controller: _cashCtrl,
                  hintText: '',
                  onChanged: (v) => _applyTextToState(context, v),
                ),

                const SizedBox(height: 12),

                // Сдача
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Сдача', style: TextStyle(fontSize: 16)),
                    Text(
                      money(cubit.change.clamp(0, double.infinity)),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Клавиатура: работает по ТЕКСТУ поля
                _Keypad(
                  onTap: (token) {
                    var t = _cashCtrl.text;
                    if (token == '⌫') {
                      if (t.isNotEmpty) t = t.substring(0, t.length - 1);
                      _setText(context, t);
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
                    // нормализуем ведущие нули
                    t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
                    _setText(context, t);
                  },
                ),

                const SizedBox(height: 8),

                // Быстрые суммы: плюсуем к текущему значению в поле
                _QuickRows(
                  rows: const [
                    ['+200', '+500', '+1 000'],
                    ['+2 000', '+5 000', '+10 000'],
                  ],
                  onTap: (v) {
                    final inc = int.parse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                    final curr =
                        double.tryParse(_cashCtrl.text.replaceAll(',', '.')) ??
                            0;
                    final next = curr + inc;
                    _setText(context, _fmt(next));
                  },
                ),

                const SizedBox(height: 8),
                const Spacer(),

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
                            backgroundColor: ThemeColors.green1,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final cubit = context.read<PosCubit>();
                            await _printService.print80mmSilently(
                                () => _buildReceipt80mm(cubit));
                          },
                          child: const Text(
                            'ОПЛАТА',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: .5,
                              fontSize: 11,
                            ),
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
        Text(k, style: TextStyle(color: sub, fontSize: 10)),
        Text(v,
            style: TextStyle(
                color: sub, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.text,
    required this.color,
    required this.svgAsset, // путь к SVG-иконке в assets
    this.iconSize = 14,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final Color color;
  final String svgAsset;
  final double iconSize;
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
        icon: SvgPicture.asset(
          svgAsset,
          width: iconSize,
          height: iconSize,
          // Перекраска под состояние:
          colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
        ),
        label: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w400,
            color: fg,
            fontSize: 12,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
    required this.color, // <— NEW
    this.hintText,
    this.controller,
  });

  final String label;
  final String? hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Color color; // <— NEW

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        hintText: hintText,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        labelStyle: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onTap});
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    const keyGrey = Color(0xFF999999);
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
                              fontSize: 11, fontWeight: FontWeight.w400),
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
            padding: const EdgeInsets.only(bottom: 8),
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
                          side: const BorderSide(color: Colors.transparent),
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
  const _FlatGrey(
      {required this.text,
      required this.onTap,
      this.width = 100,
      this.height = 44});
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

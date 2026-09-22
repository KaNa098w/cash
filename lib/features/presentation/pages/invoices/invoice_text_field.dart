import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/onscreen_keyboar_widget.dart';
import 'invoice_design.dart';

enum InvoiceInputKind { text, digits, phone }

/// Touch entry keeps the edited value visible above the on-screen keyboard.
class InvoiceTextField extends StatelessWidget {
  const InvoiceTextField(
      {super.key,
      required this.controller,
      required this.label,
      this.enabled = true,
      this.inputKind = InvoiceInputKind.text,
      this.validator,
      this.maxLines = 1,
      this.onChanged});
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final InvoiceInputKind inputKind;
  final String? Function(String?)? validator;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TouchEditor(
          label: label,
          value: controller.text,
          maxLines: maxLines,
          inputKind: inputKind),
    );
    if (result != null && context.mounted) {
      controller.value = TextEditingValue(
          text: result,
          selection: TextSelection.collapsed(offset: result.length));
      onChanged?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        readOnly: true,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(fontSize: 17),
        onTap: () => _edit(context),
        decoration: InputDecoration(
            labelText: label,
            suffixIcon: IconButton(
                tooltip: 'Клавиатура: $label',
                onPressed: enabled ? () => _edit(context) : null,
                constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                icon: const Icon(Icons.keyboard_alt_outlined))),
      );
}

class _TouchEditor extends StatefulWidget {
  const _TouchEditor(
      {required this.label,
      required this.value,
      required this.maxLines,
      required this.inputKind});
  final String label;
  final String value;
  final InvoiceInputKind inputKind;
  final int maxLines;
  @override
  State<_TouchEditor> createState() => _TouchEditorState();
}

class _TouchEditorState extends State<_TouchEditor> {
  late final _controller = TextEditingController(
      text: widget.inputKind == InvoiceInputKind.phone
          ? invoicePhoneDigits(widget.value)
          : widget.value);
  bool get _numeric => widget.inputKind != InvoiceInputKind.text;
  int get _limit => widget.inputKind == InvoiceInputKind.phone ? 10 : 12;

  void _key(String key) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    var start = selection.start;
    final end = selection.end;
    if (key == '⌫' && start == end) {
      if (start == 0) return;
      start--;
    }
    final text = value.text.replaceRange(start, end, key == '⌫' ? '' : key);
    if (text.length > _limit) return;
    _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
            offset: start + (key == '⌫' ? 0 : key.length)));
  }

  Widget _numberPad() => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['Очистить', '0', '⌫']
        ])
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                for (final key in row)
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: OutlinedButton(
                              onPressed: () => key == 'Очистить'
                                  ? _controller.clear()
                                  : _key(key),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 60),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              child: Text(key,
                                  style: TextStyle(
                                      fontSize:
                                          key == 'Очистить' ? 14 : 26))))),
              ])),
      ]));
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(
      context,
      widget.inputKind == InvoiceInputKind.phone
          ? formatInvoicePhone(_controller.text)
          : _controller.text);
  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _numeric ? 540 : 960),
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text(widget.label,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700))),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена')),
                    const SizedBox(width: 12),
                    FilledButton(
                        onPressed: _done,
                        style: FilledButton.styleFrom(
                            backgroundColor: invoiceBlue,
                            minimumSize: const Size(100, 52)),
                        child: const Text('Готово'))
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.none,
                      inputFormatters: _numeric
                          ? [
                              if (widget.inputKind == InvoiceInputKind.phone)
                                TextInputFormatter.withFunction(
                                    (oldValue, newValue) {
                                  if (newValue.text.startsWith('+') ||
                                      newValue.text
                                              .replaceAll(RegExp(r'\D'), '')
                                              .length ==
                                          11) {
                                    final digits =
                                        invoicePhoneDigits(newValue.text);
                                    return TextEditingValue(
                                        text: digits,
                                        selection: TextSelection.collapsed(
                                            offset: digits.length));
                                  }
                                  return newValue;
                                }),
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(_limit),
                            ]
                          : null,
                      maxLines: widget.maxLines,
                      style: const TextStyle(fontSize: 22),
                      decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          prefixText: widget.inputKind == InvoiceInputKind.phone
                              ? '+7 '
                              : null),
                      onSubmitted: (_) => _done()),
                  if (widget.inputKind == InvoiceInputKind.phone)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (_, value, __) => Text(
                                value.text.isEmpty
                                    ? '+7 (XXX) XXX-XX-XX'
                                    : formatInvoicePhone(value.text),
                                style: const TextStyle(
                                    fontSize: 22, color: invoiceBlue)))),
                ])),
            if (_numeric)
              _numberPad()
            else
              OnScreenKeyboardSheet(
                  controllerGetter: () => _controller,
                  onEnter: _done,
                  onClose: _done),
          ])),
        ),
      );
}

String invoicePhoneDigits(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if ((value.startsWith('+7') ||
          (digits.length == 11 &&
              (digits.startsWith('7') || digits.startsWith('8')))) &&
      digits.isNotEmpty) {
    digits = digits.substring(1);
  }
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

String formatInvoicePhone(String value) {
  final digits = invoicePhoneDigits(value);
  if (digits.isEmpty) return '';
  final buffer = StringBuffer('+7 (');
  for (var i = 0; i < digits.length; i++) {
    if (i == 3) buffer.write(') ');
    if (i == 6 || i == 8) buffer.write('-');
    buffer.write(digits[i]);
  }
  if (digits.length == 3) buffer.write(')');
  return buffer.toString();
}

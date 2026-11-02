import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'supplies_controller.dart';

const supplyInk = Color(0xFF18283E);
const supplyMuted = Color(0xFF708095);
const supplyGreen = Color(0xFF15966A);
const supplyBackground = Color(0xFFF3F6FA);
String supplyMoney(num n) => '${NumberFormat('#,##0.00', 'ru').format(n)} ₸';
String supplyDisplayDay(String value) {
  final day = DateTime.tryParse(value);
  return day == null
      ? value
      : '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
}

String supplyQuantity(num n) =>
    n.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

Future<bool> ensureSupplyAccess(
    BuildContext context, SuppliesController controller) async {
  if (controller.canWrite) return true;
  final key = await supplyTextDialog(context,
      title: 'Ключ управляющего магазина', secret: true);
  if (key == null) return false;
  controller.setManagerKey(key);
  return true;
}

class SupplyPendingBanner extends StatelessWidget {
  const SupplyPendingBanner(
      {super.key,
      required this.controller,
      required this.refresh,
      this.allowReview = false});
  final SuppliesController controller;
  final VoidCallback refresh;
  final bool allowReview;
  @override
  Widget build(BuildContext context) {
    final pending = controller.pending;
    if (pending == null) return const SizedBox.shrink();
    return SupplyMessage(
        pending['confirmed'] == true
            ? 'Операция «${pending['label']}» принята сервером. Обновите данные для получения результата. Повторная запись заблокирована.'
            : 'Результат операции «${pending['label']}» неизвестен. Проверьте документы, поставщиков и оплаты перед повтором. Автоматического повтора нет.',
        error: true,
        action: Wrap(spacing: 12, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: controller.busy ? null : refresh,
              child: const Text('Обновить с сервера')),
          if (allowReview && pending['confirmed'] != true)
            TextButton(
                onPressed: controller.busy || !controller.pendingReviewed
                    ? null
                    : () async {
                        if (await supplyConfirm(context, 'Результат проверен?',
                            'Убедитесь по списку приёмок и оплатам, что произошло с предыдущим запросом. Если документ или оплата уже созданы, откройте их, не создавайте повторно.',
                            button: 'Я проверил результат')) {
                          await controller.acknowledgeReviewedOperation();
                        }
                      },
                child: const Text('Результат проверен')),
        ]));
  }
}

ThemeData supplyTheme(BuildContext context) => Theme.of(context).copyWith(
      scaffoldBackgroundColor: supplyBackground,
      colorScheme: ColorScheme.fromSeed(seedColor: supplyGreen),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDCE4ED))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDCE4ED)))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54),
              backgroundColor: supplyGreen,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                  fontFamily: 'NotoSans',
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 54),
              foregroundColor: supplyInk,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
    );

class SupplyStatus extends StatelessWidget {
  const SupplyStatus({super.key, required this.completed});
  final bool completed;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color:
                completed ? const Color(0xFFE0F3EB) : const Color(0xFFFFF0D7),
            borderRadius: BorderRadius.circular(10)),
        child: Text(completed ? 'Проведена' : 'Черновик',
            style: TextStyle(
                color: completed ? supplyGreen : const Color(0xFF98651B),
                fontWeight: FontWeight.w700)),
      );
}

class SupplyMessage extends StatelessWidget {
  const SupplyMessage(this.text, {super.key, this.error = false, this.action});
  final String text;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: error ? const Color(0xFFFFEBE8) : const Color(0xFFE8F0FA),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(error ? Icons.info_outline : Icons.shield_outlined,
                color: error ? Colors.deepOrange : supplyMuted),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(color: supplyInk, height: 1.4))),
          ]),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: action!),
        ]),
      );
}

class SupplySelect extends StatelessWidget {
  const SupplySelect(
      {super.key,
      required this.label,
      required this.items,
      required this.value,
      required this.onChanged,
      this.allowEmpty = false});
  final String label;
  final List<SupplyReference> items;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final bool allowEmpty;
  @override
  Widget build(BuildContext context) {
    final selected = items.any((v) => v.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$selected'),
      initialValue: selected,
      isExpanded: true,
      itemHeight: 56,
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowEmpty) const DropdownMenuItem(value: '', child: Text('Все')),
        ...items.map((v) => DropdownMenuItem(
            value: v.id, child: Text(v.name, overflow: TextOverflow.ellipsis)))
      ],
      onChanged: onChanged,
    );
  }
}

class SupplyDialog extends StatelessWidget {
  const SupplyDialog(
      {super.key,
      required this.title,
      required this.content,
      this.actions = const [],
      this.subtitle,
      this.icon = Icons.inventory_2_outlined,
      this.width = 600,
      this.canClose = true});
  final Widget title, content;
  final List<Widget> actions;
  final String? subtitle;
  final IconData icon;
  final double width;
  final bool canClose;
  @override
  Widget build(BuildContext context) => Theme(
      data: supplyTheme(context),
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
            width: width,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                      color: supplyInk,
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                      child: Row(children: [
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(14)),
                            child: Icon(icon,
                                color: const Color(0xFF79DBB4), size: 28)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              DefaultTextStyle(
                                  style: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                  child: title),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(subtitle!,
                                    style: const TextStyle(
                                        color: Color(0xFFBCC8D8), fontSize: 13))
                              ],
                            ])),
                        IconButton(
                            tooltip: 'Закрыть окно',
                            onPressed: canClose
                                ? () => Navigator.maybePop(context)
                                : null,
                            icon: Icon(Icons.close_rounded,
                                color: canClose ? Colors.white : supplyMuted),
                            constraints: const BoxConstraints(
                                minWidth: 52, minHeight: 52)),
                      ])),
                  Flexible(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20), child: content)),
                  if (actions.isNotEmpty)
                    Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                            color: supplyBackground,
                            border: Border(
                                top: BorderSide(color: Color(0xFFE0E7EF)))),
                        child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 10,
                            children: actions)),
                ])),
      ));
}

Future<bool> supplyConfirm(BuildContext context, String title, String message,
        {String button = 'Подтвердить'}) async =>
    await showDialog<bool>(
        context: context,
        builder: (_) => SupplyDialog(
                title: Text(title),
                content: SizedBox(width: 440, child: Text(message)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(button))
                ])) ??
    false;

Future<String?> supplyTextDialog(BuildContext context,
        {required String title,
        String initial = '',
        bool secret = false,
        bool numeric = false,
        bool allowEmpty = false,
        int maxLength = 128}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _SupplyTextDialog(
            title: title,
            initial: initial,
            secret: secret,
            numeric: numeric,
            allowEmpty: allowEmpty,
            maxLength: maxLength));

class _SupplyTextDialog extends StatefulWidget {
  const _SupplyTextDialog(
      {required this.title,
      required this.initial,
      required this.secret,
      required this.numeric,
      required this.allowEmpty,
      required this.maxLength});
  final String title, initial;
  final bool secret;
  final bool numeric, allowEmpty;
  final int maxLength;
  @override
  State<_SupplyTextDialog> createState() => _SupplyTextDialogState();
}

class _SupplyTextDialogState extends State<_SupplyTextDialog> {
  late final _text = TextEditingController(text: widget.initial);
  bool _keyboard = true;
  @override
  void initState() {
    super.initState();
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    _text.addListener(_entryChanged);
  }

  void _entryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.removeListener(_entryChanged);
    _text.dispose();
    super.dispose();
  }

  void _done() {
    if (widget.allowEmpty || _text.text.trim().isNotEmpty) {
      Navigator.pop(context, _text.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => SupplyDialog(
        title: Text(widget.title),
        width: widget.numeric ? 500 : 940,
        subtitle: widget.numeric
            ? 'Введите цифры на экране или используйте сканер'
            : 'Ввод с клавиатуры или на сенсорном экране',
        icon: widget.secret
            ? Icons.lock_outline
            : widget.numeric
                ? Icons.qr_code_rounded
                : Icons.keyboard_outlined,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const ValueKey('supply-touch-input'),
              controller: _text,
              autofocus: true,
              keyboardType: TextInputType.none,
              obscureText: widget.secret,
              style: TextStyle(
                  fontSize: widget.numeric ? 27 : 20,
                  fontWeight: FontWeight.w600),
              inputFormatters: [
                if (widget.numeric) FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.maxLength)
              ],
              onSubmitted: (_) => _done(),
              decoration: InputDecoration(
                  labelText: widget.secret ? 'Ключ управляющего' : 'Значение',
                  suffixIcon: IconButton(
                      tooltip: 'Экранная клавиатура',
                      icon: const Icon(Icons.keyboard_outlined),
                      onPressed: () =>
                          setState(() => _keyboard = !_keyboard)))),
          if (widget.secret)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Ключ проверяется сервером при записи и не сохраняется на кассе.',
                    style: TextStyle(color: supplyMuted))),
          const SizedBox(height: 16),
          if (_keyboard && widget.numeric) ...[
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['Очистить', '0', '⌫']
            ])
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    for (final key in row)
                      Expanded(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: OutlinedButton(
                                  key: ValueKey('supply-code-$key'),
                                  onPressed: () => _codeKey(key),
                                  style: OutlinedButton.styleFrom(
                                      minimumSize: Size(
                                          0,
                                          MediaQuery.sizeOf(context).height <
                                                  680
                                              ? 48
                                              : 56),
                                      padding: EdgeInsets.zero,
                                      backgroundColor: supplyBackground,
                                      side: const BorderSide(
                                          color: Color(0xFFDEE6EE))),
                                  child: key == '⌫'
                                      ? const Icon(Icons.backspace_outlined,
                                          size: 24)
                                      : Text(key,
                                          style: TextStyle(
                                              fontSize:
                                                  key == 'Очистить' ? 13 : 25,
                                              fontWeight: FontWeight.w700))))),
                  ])),
          ] else if (_keyboard)
            OnScreenKeyboardSheet(
                controllerGetter: () => _text,
                onEnter: _done,
                onClose: () => setState(() => _keyboard = false)),
        ]),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: widget.allowEmpty || _text.text.trim().isNotEmpty
                  ? _done
                  : null,
              child: const Text('Готово'))
        ],
      );

  void _codeKey(String key) {
    if (key == 'Очистить') {
      _text.clear();
      return;
    }
    final value = _text.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    var start = selection.start;
    if (key == '⌫' && selection.isCollapsed && start > 0) start--;
    final next =
        value.text.replaceRange(start, selection.end, key == '⌫' ? '' : key);
    if (next.length > widget.maxLength) return;
    _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
            offset: start + (key == '⌫' ? 0 : key.length)));
  }
}

Future<double?> supplyNumberDialog(BuildContext context,
        {required String title,
        required double value,
        bool quantity = false}) =>
    showDialog<double>(
        context: context,
        builder: (_) => _SupplyNumberDialog(
            title: title, value: value, quantity: quantity));

class _SupplyNumberDialog extends StatefulWidget {
  const _SupplyNumberDialog(
      {required this.title, required this.value, required this.quantity});
  final String title;
  final double value;
  final bool quantity;
  @override
  State<_SupplyNumberDialog> createState() => _SupplyNumberDialogState();
}

class _SupplyNumberDialogState extends State<_SupplyNumberDialog> {
  late String _value = widget.value.toStringAsFixed(widget.quantity ? 3 : 2);
  bool _replace = true;
  double? get parsed => double.tryParse(_value);
  @override
  Widget build(BuildContext context) => SupplyDialog(
        width: 460,
        icon: Icons.calculate_outlined,
        title: Text(widget.title),
        content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: supplyBackground,
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(_value.isEmpty ? '0' : _value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: supplyInk))),
              TextButton(
                  onPressed: () => setState(() {
                        _value = '';
                        _replace = false;
                      }),
                  child: const Text('Очистить')),
              AmountKeypad(
                  text: _replace ? '' : _value,
                  showQuickRows: false,
                  maxLength: 14,
                  keyColor: supplyBackground,
                  keyTextColor: supplyInk,
                  keyHeight: MediaQuery.sizeOf(context).height < 680 ? 48 : 52,
                  useBackspaceIcon: true,
                  onChanged: (v) {
                    if (RegExp(widget.quantity
                            ? r'^\d*(\.\d{0,3})?$'
                            : r'^\d*(\.\d{0,2})?$')
                        .hasMatch(v)) {
                      setState(() {
                        _value = v;
                        _replace = false;
                      });
                    }
                  }),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: parsed != null &&
                      parsed!.isFinite &&
                      (widget.quantity ? parsed! > 0 : parsed! >= 0)
                  ? () => Navigator.pop(context, parsed)
                  : null,
              child: const Text('Готово'))
        ],
      );
}

class SupplyNoteField extends StatelessWidget {
  const SupplyNoteField(
      {super.key,
      required this.controller,
      required this.label,
      this.enabled = true,
      this.onChanged});
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => SupplyTouchField(
      controller: controller,
      label: label,
      enabled: enabled,
      onChanged: onChanged);
}

class SupplyTouchField extends StatelessWidget {
  const SupplyTouchField(
      {super.key,
      required this.controller,
      required this.label,
      this.enabled = true,
      this.numeric = false,
      this.maxLength = 128,
      this.validator,
      this.onChanged});
  final TextEditingController controller;
  final String label;
  final bool enabled, numeric;
  final int maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.none,
        validator: validator,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 18),
        inputFormatters: [
          if (numeric) FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLength)
        ],
        decoration: InputDecoration(
            labelText: label,
            suffixIcon: IconButton(
                tooltip: 'Ввести: $label',
                constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                onPressed: !enabled
                    ? null
                    : () async {
                        final value = await supplyTextDialog(context,
                            title: label,
                            initial: controller.text,
                            numeric: numeric,
                            allowEmpty: true,
                            maxLength: maxLength);
                        if (value != null && context.mounted) {
                          controller.value = TextEditingValue(
                              text: value,
                              selection: TextSelection.collapsed(
                                  offset: value.length));
                          onChanged?.call(value);
                        }
                      },
                icon: const Icon(Icons.keyboard_alt_outlined))),
      );
}

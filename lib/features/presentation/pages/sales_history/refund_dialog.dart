import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/onscreen_keyboar_widget.dart';

class RefundDialogResult {
  final int totalAmount;
  final String reason;
  final String? note;

  RefundDialogResult({
    required this.totalAmount,
    required this.reason,
    this.note,
  });
}

class RefundDialog extends StatefulWidget {
  const RefundDialog({super.key, required this.sale});

  final SaleModel sale;

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  final _amountFocus = FocusNode();
  final _reasonFocus = FocusNode();
  final _noteFocus = FocusNode();

  TextEditingController? _activeCtrl;
  bool _kbOpened = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.sale.totalAmount.toString();
    _reasonCtrl.text = 'Возврат';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _noteCtrl.dispose();

    _amountFocus.dispose();
    _reasonFocus.dispose();
    _noteFocus.dispose();

    super.dispose();
  }

  TextEditingController _getActiveCtrl() => _activeCtrl ?? _amountCtrl;

  Future<void> _openKeyboard(TextEditingController ctrl, FocusNode fn) async {
    _activeCtrl = ctrl;

    FocusManager.instance.primaryFocus?.unfocus();
    fn.requestFocus();

    if (_kbOpened) return;
    _kbOpened = true;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return OnScreenKeyboardSheet(
          controllerGetter: _getActiveCtrl,
          onEnter: () => Navigator.of(ctx).pop(),
          onClose: () => Navigator.of(ctx).pop(),
        );
      },
    );

    _kbOpened = false;
    _activeCtrl = null;
  }

  int _toIntMoney(String s) {
    final t = s.trim().replaceAll(',', '.');
    final n = num.tryParse(t);
    return (n ?? 0).round();
  }

  void _submit() {
    final amount = _toIntMoney(_amountCtrl.text);
    final reason = _reasonCtrl.text.trim();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сумма возврата должна быть > 0')),
      );
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажи причину возврата')),
      );
      return;
    }

    Navigator.of(context).pop(
      RefundDialogResult(totalAmount: amount, reason: reason, note: note),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController ctrl,
    required FocusNode focus,
    int maxLines = 1,
    String? hint,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      readOnly: true,
      showCursor: true,
      maxLines: maxLines,
      onTap: () => _openKeyboard(ctrl, focus),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkNo = widget.sale.number.trim().isEmpty
        ? widget.sale.localId
        : widget.sale.number;

    return AlertDialog(
      title: const Text('Возврат'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(
              label: 'Сумма возврата',
              ctrl: _amountCtrl,
              focus: _amountFocus,
              hint: 'Например: 1200',
            ),
            const SizedBox(height: 10),
            _field(
              label: 'Причина',
              ctrl: _reasonCtrl,
              focus: _reasonFocus,
              hint: 'Например: Брак',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Чек: $checkNo',
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Оформить возврат'),
        ),
      ],
    );
  }
}

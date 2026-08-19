import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leemon_app/core/marking/gs1_datamatrix_validator.dart';
import 'package:leemon_app/core/models/sale_model.dart';

Future<String?> showRefundMarkCodeDialog(
  BuildContext context, {
  required SaleItemModel item,
  required Set<String> availableCodes,
  required Set<String> currentCodes,
  required int requiredCount,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RefundMarkCodeDialog(
      item: item,
      availableCodes: availableCodes,
      currentCodes: currentCodes,
      requiredCount: requiredCount,
    ),
  );
}

class _RefundMarkCodeDialog extends StatefulWidget {
  const _RefundMarkCodeDialog({
    required this.item,
    required this.availableCodes,
    required this.currentCodes,
    required this.requiredCount,
  });

  final SaleItemModel item;
  final Set<String> availableCodes;
  final Set<String> currentCodes;
  final int requiredCount;

  @override
  State<_RefundMarkCodeDialog> createState() => _RefundMarkCodeDialogState();
}

class _RefundMarkCodeDialogState extends State<_RefundMarkCodeDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    if (event.physicalKey == PhysicalKeyboardKey.backspace) {
      if (_controller.text.isNotEmpty) {
        final text = _controller.text.substring(0, _controller.text.length - 1);
        _setText(text);
      }
      return KeyEventResult.handled;
    }
    final character = MarkingKeyboardInputFormatter.englishCharacter(event);
    if (character == null) return KeyEventResult.ignored;
    _setText('${_controller.text}$character');
    return KeyEventResult.handled;
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _reject(String message) {
    setState(() => _error = message);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _submit() {
    // Keep the exact scanner payload, including AIM and ASCII 29 separators.
    final rawCode = _controller.text;
    if (rawCode.isEmpty || rawCode.length > 512) {
      _reject('Код маркировки пустой или слишком длинный.');
      return;
    }
    final expectedGtin = (widget.item.markingGtin ?? '').trim().isNotEmpty
        ? widget.item.markingGtin
        : (widget.item.markingNtin ?? '').trim().isNotEmpty
            ? widget.item.markingNtin
            : null;
    final validation = Gs1DataMatrixValidator.validate(
      rawCode,
      expectedGtin: expectedGtin,
    );
    if (!validation.isValid) {
      _reject(validation.message ?? 'Код маркировки не распознан.');
      return;
    }
    if (widget.currentCodes.contains(rawCode)) {
      _reject('Этот код маркировки уже добавлен в возврат.');
      return;
    }
    if (!widget.availableCodes.contains(rawCode)) {
      _reject(
        'Этот код отсутствует в исходном чеке или уже был возвращён.',
      );
      return;
    }
    Navigator.of(context).pop(rawCode);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      title: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Color(0xFF15966A),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Маркировка для возврата',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.displayProductName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Кодов: ${widget.currentCodes.length} / ${widget.requiredCount}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                obscureText: true,
                obscuringCharacter: '•',
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                onTapOutside: (_) => _focusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'Код маркировки',
                  hintText: 'Наведите сканер на код с упаковки',
                  errorText: _error,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(
                    Icons.center_focus_strong_rounded,
                    color: Color(0xFF15966A),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF22B982),
                      width: 2,
                    ),
                  ),
                ),
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
      ],
    );
  }
}

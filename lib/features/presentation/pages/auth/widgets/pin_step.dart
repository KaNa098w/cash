import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';

class PinStep extends StatefulWidget {
  final ThemeData theme;
  final PosUser user;
  final String? errorText;
  final VoidCallback onBack;
  final VoidCallback onChangeKey;
  final ValueChanged<String> onVerify;

  const PinStep({
    super.key,
    required this.theme,
    required this.user,
    required this.onBack,
    required this.onChangeKey,
    required this.onVerify,
    this.errorText,
  });

  @override
  State<PinStep> createState() => _PinStepState();
}

class _PinStepState extends State<PinStep> {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pinFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _setPin(String v) {
    _pinController.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    setState(() {});
  }

  void _submit() => widget.onVerify(_pinController.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
                onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                widget.user.name,
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // TextButton(onPressed: widget.onChangeKey, child: const Text('Сменить ключ')),
          ],
        ),
        const SizedBox(height: 6),
        Text('Введи PIN пользователя',
            style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 16),
        TextField(
          controller: _pinController,
          focusNode: _pinFocusNode,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'PIN',
            hintText: 'Например: 1050',
            errorText: widget.errorText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          onTap: () => _pinFocusNode.requestFocus(),
          onChanged: (value) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submit,
            child: const Text('Продолжить',
                style:
                    TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ),
        ),
        const SizedBox(height: 16),
        AmountKeypad(
          text: _pinController.text,
          onChanged: (value) {
            _setPin(value);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _pinFocusNode.requestFocus();
            });
          },
          allowDecimal: false,
          maxLength: 4,
          showQuickRows: false,
        ),
        const SizedBox(height: 12),
        Text('© ${DateTime.now().year} POS Desktop',
            style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}

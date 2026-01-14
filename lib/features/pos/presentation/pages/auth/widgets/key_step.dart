import 'package:flutter/material.dart';

class KeyStep extends StatelessWidget {
  final ThemeData theme;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitted;
  final bool loading;
  final VoidCallback? onSubmit;
  final String? hint;

  const KeyStep({
    super.key,
    required this.theme,
    required this.controller,
    required this.focusNode,
    required this.submitted,
    required this.loading,
    required this.onSubmit,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final showError = submitted && controller.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Подключение кассы',
          style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Введи ключ кассы. Затем выбери пользователя и введи PIN.',
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint!, style: theme.textTheme.bodySmall!.copyWith(color: Colors.black45)),
        ],
        const SizedBox(height: 22),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: !loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => loading ? null : onSubmit?.call(),
          decoration: InputDecoration(
            labelText: 'Ключ кассы',
            hintText: 'Введите ключ вашей кассы',
            errorText: showError ? 'Ключ обязателен' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: loading ? null : onSubmit,
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Продолжить',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
          ),
        ),
        const Spacer(),
        Text(
          '© ${DateTime.now().year} POS Desktop',
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../state/auth_cubit.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.loading});
  final bool loading;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _remember = true;
  bool _showPassword = false;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<AuthCubit>().signIn(_login.text, _password.text, rememberMe: _remember);
    final st = context.read<AuthCubit>().state;
    if (st is AuthAuthenticated && mounted) context.go('/pos');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    InputDecoration deco(String label, {Widget? suffix}) => InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          suffixIcon: suffix,
        );

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Логин
            TextFormField(
              controller: _login,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: deco('Логин или e-mail'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите логин' : null,
            ),
            const SizedBox(height: 14),

            // Пароль
            TextFormField(
              controller: _password,
              autofillHints: const [AutofillHints.password],
              obscureText: !_showPassword,
              onFieldSubmitted: (_) => _submit(),
              decoration: deco(
                'Пароль',
                suffix: IconButton(
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              validator: (v) => (v == null || v.length < 4) ? 'Минимум 4 символа' : null,
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: widget.loading ? null : (v) => setState(() => _remember = v ?? true),
                ),
                const Text('Запомнить меня'),
                const Spacer(),
                TextButton(
                  onPressed: widget.loading ? null : () {},
                  child: const Text('Забыли пароль?'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: widget.loading ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: widget.loading
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text('Войти'),
              ),
            ),

            const SizedBox(height: 10),

            // Подсказка
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Демо: любой логин, пароль ≥ 4 символов', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

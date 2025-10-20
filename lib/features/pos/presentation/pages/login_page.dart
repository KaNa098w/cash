import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../state/auth_cubit.dart';
import '../widgets/login_header.dart';
import '../widgets/login_form.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.1, 0.5, 0.9],
            colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF), Color(0xFFF1F5F9)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 620),
            child: Card(
              elevation: 0,
              color: Colors.white.withOpacity(0.9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  // Иллюстрация / брендовая панель
                  Expanded(
                    child: _LeftBrandPane(),
                  ),
                  const VerticalDivider(width: 1),
                  // Форма
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                      child: BlocConsumer<AuthCubit, AuthState>(
                        listener: (context, state) {
                          if (state is AuthFailure) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(state.message)),
                            );
                          }
                        },
                        builder: (context, state) {
                          final loading = state is AuthLoading;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LoginHeader(),
                              const SizedBox(height: 24),
                              LoginForm(loading: loading),
                              const Spacer(),
                              Text(
                                '© ${DateTime.now().year} POS Desktop',
                                style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftBrandPane extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Лого-заглушка
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.95),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text('POS', style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          Text(
            'Касса\nDesktop',
            style: theme.textTheme.displaySmall!.copyWith(
              color: Colors.white,
              height: 1.05,
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 2))],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Быстро. Стабильно. Оффлайн/онлайн.',
            style: theme.textTheme.titleMedium!.copyWith(color: Colors.white70),
          ),
          const Spacer(),
          const _MiniFeatures(),
        ],
      ),
    );
  }
}

class _MiniFeatures extends StatelessWidget {
  const _MiniFeatures();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white.withOpacity(.9));
    Widget pill(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(t, style: style),
        );
    return Wrap(
      children: [
        pill('Горячие клавиши'),
        pill('Работа без интернета'),
        pill('Импорт/Экспорт'),
        pill('Синхронизация'),
      ],
    );
  }
}

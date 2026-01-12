import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';

import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_state.dart';

import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _keyController = TextEditingController();
  final _keyFocus = FocusNode();
  bool _keySubmitted = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AuthTokenProvider>();
      _keyController.text = provider.posKey ?? '';
      context.read<AuthCubit>().bootstrapFromCache();
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _submitKey() {
    final key = _keyController.text.trim();
    setState(() => _keySubmitted = true);

    if (key.isEmpty) {
      _keyFocus.requestFocus();
      return;
    }

    context.read<AuthCubit>().provisionByKey(key);
  }

  void _retryProductsLoad() {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) return;

    context.read<ProductsCubit>().loadFirstPage(key: key, forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<AuthTokenProvider>();

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
                  const Expanded(child: _LeftBrandPane()),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                      child: MultiBlocListener(
                        listeners: [
                          BlocListener<AuthCubit, AuthState>(
                            listener: (context, state) {
                              if (state is AuthFailure) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(state.message)),
                                );
                              }

                              if (state is AuthSuccess) {
                                final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
                                if (key.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('posKey пустой, не могу загрузить товары')),
                                  );
                                  return;
                                }

                                context.read<ProductsCubit>().loadFirstPage(
                                      key: key,
                                      forceRefresh: true,
                                    );
                              }
                            },
                          ),

                          BlocListener<ProductsCubit, ProductsState>(
                            listener: (context, state) {
                              if (state is ProductsLoaded) {
                                context.go('/pos');
                              }

                              if (state is ProductsError) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка загрузки товаров: ${state.message}')),
                                );
                              }
                            },
                          ),
                        ],
                        child: BlocBuilder<AuthCubit, AuthState>(
                          builder: (context, authState) {
                            final productsState = context.watch<ProductsCubit>().state;
                            final isLoadingAuth = authState is AuthLoading;

                            // ✅ после AuthSuccess грузим товары
                            if (authState is AuthSuccess) {
                              if (productsState is ProductsLoading || productsState is ProductsInitial) {
                                return _LoadingStep(
                                  theme: theme,
                                  title: 'Подготовка кассы',
                                  subtitle: 'Загружаем товары...',
                                );
                              }

                              if (productsState is ProductsError) {
                                return _ProductsErrorStep(
                                  theme: theme,
                                  message: productsState.message,
                                  onRetry: _retryProductsLoad,
                                );
                              }

                              return const SizedBox.shrink();
                            }

                            // ✅ запрос на open-session
                            if (authState is AuthOpeningSession) {
                              return _LoadingStep(
                                theme: theme,
                                title: 'Подготовка кассы',
                                subtitle: 'Открываем смену...',
                              );
                            }

                            // STEP: KEY
                            if (authState is AuthInitial || authState is AuthLoading) {
                              return _KeyStep(
                                theme: theme,
                                controller: _keyController,
                                focusNode: _keyFocus,
                                submitted: _keySubmitted,
                                loading: isLoadingAuth,
                                onSubmit: isLoadingAuth ? null : _submitKey,
                                hint: provider.deviceId == null ? null : 'Device ID: ${provider.deviceId}',
                              );
                            }

                            // STEP: USERS
                            if (authState is AuthProvisioned) {
                              return _UsersStep(
                                theme: theme,
                                provision: authState.provision,
                                onChangeKey: () => context.read<AuthCubit>().resetAll(),
                                onSelect: (u) => context.read<AuthCubit>().selectUser(authState.provision, u),
                              );
                            }

                            // STEP: PIN
                            if (authState is AuthPinStep) {
                              return _PinStep(
                                theme: theme,
                                user: authState.user,
                                errorText: authState.errorText,
                                onBack: () => context.read<AuthCubit>().backToUsers(authState.provision),
                                onVerify: (pin) => context.read<AuthCubit>().verifyPin(
                                      provision: authState.provision,
                                      user: authState.user,
                                      inputPin: pin,
                                    ),
                                onChangeKey: () => context.read<AuthCubit>().resetAll(),
                              );
                            }

                            // ✅ STEP: OPENING CASH INPUT
                            if (authState is AuthOpeningCashStep) {
                              return _OpeningCashStep(
                                theme: theme,
                                user: authState.user,
                                onBack: () => context.read<AuthCubit>().selectUser(
                                      authState.provision,
                                      authState.user,
                                    ),
                                onSubmit: (amount) => context.read<AuthCubit>().openSessionWithCash(
                                      provision: authState.provision,
                                      user: authState.user,
                                      openingCashAmount: amount,
                                    ),
                              );
                            }

                            return const SizedBox.shrink();
                          },
                        ),
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

// -------------------- STEP: KEY --------------------

class _KeyStep extends StatelessWidget {
  final ThemeData theme;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitted;
  final bool loading;
  final VoidCallback? onSubmit;
  final String? hint;

  const _KeyStep({
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

// -------------------- STEP: USERS --------------------

class _UsersStep extends StatelessWidget {
  final ThemeData theme;
  final PosProvisionResponse provision;
  final VoidCallback onChangeKey;
  final ValueChanged<PosUser> onSelect;

  const _UsersStep({
    required this.theme,
    required this.provision,
    required this.onChangeKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final users = provision.users;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Касса: ${provision.name}',
                style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(onPressed: onChangeKey, child: const Text('Сменить ключ')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Выбери пользователя для входа:',
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (users.isEmpty)
          Text('Пользователи не найдены',
              style: theme.textTheme.bodyMedium!.copyWith(color: Colors.redAccent))
        else
          Expanded(
            child: ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final u = users[i];
                return _UserTile(user: u, onTap: () => onSelect(u));
              },
            ),
          ),
        const SizedBox(height: 10),
        Text(
          '© ${DateTime.now().year} POS Desktop',
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  final PosUser user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = user.name.isNotEmpty ? user.name.trim().characters.first : 'U';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x22000000)),
          color: Colors.white,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFEFF6FF),
              child: Text(letter,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF3B82F6))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    user.emailAddress.isEmpty ? '—' : user.emailAddress,
                    style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

// -------------------- STEP: PIN --------------------

class _PinStep extends StatefulWidget {
  final ThemeData theme;
  final PosUser user;
  final String? errorText;
  final VoidCallback onBack;
  final VoidCallback onChangeKey;
  final ValueChanged<String> onVerify;

  const _PinStep({
    required this.theme,
    required this.user,
    required this.onBack,
    required this.onChangeKey,
    required this.onVerify,
    this.errorText,
  });

  @override
  State<_PinStep> createState() => _PinStepState();
}

class _PinStepState extends State<_PinStep> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                widget.user.name,
                style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: widget.onChangeKey, child: const Text('Сменить ключ')),
          ],
        ),
        const SizedBox(height: 6),
        Text('Введи PIN пользователя', style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 16),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          obscureText: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'PIN',
            hintText: 'Например: 1050',
            errorText: widget.errorText,
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
            onPressed: _submit,
            child: const Text('Продолжить', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ),
        ),
        const Spacer(),
        Text('© ${DateTime.now().year} POS Desktop', style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}

// -------------------- STEP: OPENING CASH --------------------

class _OpeningCashStep extends StatefulWidget {
  final ThemeData theme;
  final PosUser user;
  final VoidCallback onBack;
  final ValueChanged<num> onSubmit;

  const _OpeningCashStep({
    required this.theme,
    required this.user,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  State<_OpeningCashStep> createState() => _OpeningCashStepState();
}

class _OpeningCashStepState extends State<_OpeningCashStep> {
  final _cashController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  num _parseAmount(String v) {
    // поддержим "1000", "1 000", "1,000", "1000.50"
    final clean = v.trim().replaceAll(' ', '').replaceAll(',', '.');
    return num.tryParse(clean) ?? 0;
  }

  void _submit() {
    setState(() => _submitted = true);
    final amount = _parseAmount(_cashController.text);

    if (amount < 0) return;
    widget.onSubmit(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final amount = _parseAmount(_cashController.text);
    final showError = _submitted && amount < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                widget.user.name,
                style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Сумма открытия смены', style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 16),
        TextField(
          controller: _cashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Сумма',
            hintText: 'Например: 10000',
            errorText: showError ? 'Сумма не может быть отрицательной' : null,
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
            onPressed: _submit,
            child: const Text('Открыть смену', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ),
        ),
        const Spacer(),
        Text('© ${DateTime.now().year} POS Desktop', style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}

// -------------------- LOADING --------------------

class _LoadingStep extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String subtitle;

  const _LoadingStep({
    required this.theme,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 18),
        const Center(child: CircularProgressIndicator()),
        const Spacer(),
        Text('© ${DateTime.now().year} POS Desktop', style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}

// -------------------- PRODUCTS ERROR --------------------

class _ProductsErrorStep extends StatelessWidget {
  final ThemeData theme;
  final String message;
  final VoidCallback onRetry;

  const _ProductsErrorStep({
    required this.theme,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Не удалось загрузить товары',
            style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(message, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.redAccent)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Повторить', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        const Spacer(),
        Text('© ${DateTime.now().year} POS Desktop', style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}

// -------------------- LEFT PANE --------------------

class _LeftBrandPane extends StatelessWidget {
  const _LeftBrandPane();

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
          Text('Быстро. Стабильно. Оффлайн/онлайн.',
              style: theme.textTheme.titleMedium!.copyWith(color: Colors.white70)),
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
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: Colors.white.withOpacity(.9),
        );

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

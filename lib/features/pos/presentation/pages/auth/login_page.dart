import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_state.dart';

import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_state.dart';

import 'widgets/login_steps.dart';

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
    // AuthTokenProvider().clearProvisioned();

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

  void _ensureProductsLoadedAndGoPos() {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('posKey пустой, не могу загрузить товары')),
      );
      return;
    }

    final productsState = context.read<ProductsCubit>().state;
    if (productsState is ProductsLoaded) {
      context.go('/pos');
      return;
    }

    context.read<ProductsCubit>().loadFirstPage(key: key, forceRefresh: false);
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
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 750),
            child: Card(
              elevation: 0,
              color: Colors.white.withOpacity(0.9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  // const Expanded(child: LeftBrandPane()),
                  // const VerticalDivider(width: 1),
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

                              // ✅ после успешного открытия смены — грузим товары
                              if (state is AuthSuccess) {
                                _ensureProductsLoadedAndGoPos();
                              }

                              // ✅ после unlock (смена уже открыта) — НЕ спрашиваем сумму
                              if (state is AuthUnlocked) {
                                _ensureProductsLoadedAndGoPos();
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
                                  SnackBar(
                                    content: Text('Ошибка загрузки товаров: ${state.message}'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                        child: BlocBuilder<AuthCubit, AuthState>(
                          builder: (context, authState) {
                            final productsState = context.watch<ProductsCubit>().state;
                            final isLoadingAuth = authState is AuthLoading;

                            // ✅ если уже пошли в загрузку товаров (после AuthSuccess / AuthUnlocked)
                            if (authState is AuthSuccess || authState is AuthUnlocked) {
                              if (productsState is ProductsLoading ||
                                  productsState is ProductsInitial) {
                                return LoadingStep(
                                  theme: theme,
                                  title: 'Подготовка кассы',
                                  subtitle: 'Загружаем товары...',
                                );
                              }

                              if (productsState is ProductsError) {
                                return ProductsErrorStep(
                                  theme: theme,
                                  message: productsState.message,
                                  onRetry: _retryProductsLoad,
                                );
                              }

                              // ProductsLoaded поймает listener и сделает go('/pos')
                              return const SizedBox.shrink();
                            }

                            // ✅ запрос на open-session
                            if (authState is AuthOpeningSession) {
                              return LoadingStep(
                                theme: theme,
                                title: 'Подготовка кассы',
                                subtitle: 'Открываем смену...',
                              );
                            }

                            // STEP: KEY
                            if (authState is AuthInitial || authState is AuthLoading) {
                              return KeyStep(
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
                              return UsersStep(
                                theme: theme,
                                provision: authState.provision,
                                onChangeKey: () => context.read<AuthCubit>().resetAll(),
                                onSelect: (u) => context
                                    .read<AuthCubit>()
                                    .selectUser(authState.provision, u),
                              );
                            }

                            // STEP: PIN
                            if (authState is AuthPinStep) {
                              return PinStep(
                                theme: theme,
                                user: authState.user,
                                errorText: authState.errorText,
                                onBack: () => context
                                    .read<AuthCubit>()
                                    .backToUsers(authState.provision),
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
                              return OpeningCashStep(
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

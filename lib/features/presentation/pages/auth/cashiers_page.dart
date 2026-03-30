import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/cachier_login_page_widget.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/login_steps.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_state.dart';

class CashiersPage extends StatefulWidget {
  const CashiersPage({super.key});

  @override
  State<CashiersPage> createState() => _CashiersPageState();
}

class _CashiersPageState extends State<CashiersPage> {
  Future<void> _wipeAllLocalData() async {
    await sl<PosSyncService>().clearAllLocalData();

    await context.read<ProductsCubit>().reset();
    await context.read<AuthCubit>().resetAll();

    if (!mounted) return;
    context.go('/login');
  }

  void _goToPosIfReady() {
    final productsState = context.read<ProductsCubit>().state;
    if (productsState is ProductsLoaded) {
      context.go('/pos');
      return;
    }

    // Products are normally already loaded when we reach the cashiers page
    // from POS. If not, fall back to the full login flow.
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthTokenProvider>();

    return Scaffold(
      body: BlocConsumer<AuthCubit, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthFailure ||
            curr is AuthSuccess ||
            curr is AuthUnlocked ||
            curr is AuthInitial,
        listener: (context, state) {
          if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
            return;
          }

          if (state is AuthSuccess || state is AuthUnlocked) {
            _goToPosIfReady();
            return;
          }

          if (state is AuthInitial) {
            context.go('/login');
          }
        },
        builder: (context, authState) {
          final provision = switch (authState) {
            AuthProvisioned(:final provision) => provision,
            AuthPinStep(:final provision) => provision,
            _ => provider.cachedProvision,
          };

          if (provision == null) {
            return Builder(
              builder: (context) {
                unawaited(
                  Future<void>.microtask(() {
                    if (!context.mounted) return;
                    context.go('/login');
                  }),
                );
                return LoadingStep(
                  theme: Theme.of(context),
                  title: 'Подготавливаем кассиров',
                  subtitle: 'Переходим на нужный экран...',
                );
              },
            );
          }

          final selectedUser =
              authState is AuthPinStep ? authState.user : null;
          final errorText =
              authState is AuthPinStep ? authState.errorText : null;

          return CashierLoginStep(
            provision: provision,
            selectedUser: selectedUser,
            errorText: errorText,
            onSelectUser: (u) => context.read<AuthCubit>().selectUser(provision, u),
            onSubmitPin: (u, pin) => context.read<AuthCubit>().verifyPin(
                  provision: provision,
                  user: u,
                  inputPin: pin,
                ),
            onCancel: () => context.read<AuthCubit>().backToUsers(provision),
            onWipeAllData: _wipeAllLocalData,
          );
        },
      ),
    );
  }
}

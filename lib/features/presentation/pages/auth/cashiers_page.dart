import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/pos_pricing_plan_status.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/service/pos_diagnostics_service.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/auth_error_alert_dialog.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/cachier_login_page_widget.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/login_steps.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_state.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

class CashiersPage extends StatefulWidget {
  const CashiersPage({super.key});

  @override
  State<CashiersPage> createState() => _CashiersPageState();
}

class _CashiersPageState extends State<CashiersPage> {
  bool _resolvingShiftOwner = false;
  bool _shiftOwnerLookupFinished = false;
  String? _resolvedShiftUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveShiftOwner();
    });
  }

  Future<void> _resolveShiftOwner() async {
    if (!mounted || _resolvingShiftOwner) return;

    final provider = context.read<AuthTokenProvider>();
    final shiftId = provider.shiftId?.trim() ?? '';
    if (shiftId.isEmpty) {
      _shiftOwnerLookupFinished = true;
      return;
    }

    final savedUserId = (provider.shiftUserId?.trim().isNotEmpty == true)
        ? provider.shiftUserId!.trim()
        : (provider.activeUserId ?? '').trim();
    if (savedUserId.isNotEmpty) {
      _resolvedShiftUserId = savedUserId;
      await provider.setShiftUserId(savedUserId);
      _shiftOwnerLookupFinished = true;
      if (mounted) setState(() {});
      return;
    }

    setState(() => _resolvingShiftOwner = true);
    try {
      final sessions = await sl<PosSyncService>().loadSessions();
      String restoredUserId = '';
      for (final session in sessions) {
        if (session.matches(shiftId)) {
          restoredUserId = session.userId.trim();
          break;
        }
      }

      if (restoredUserId.isNotEmpty) {
        await provider.setShiftUserId(restoredUserId);
        _resolvedShiftUserId = restoredUserId;
      }
    } finally {
      if (mounted) {
        setState(() {
          _resolvingShiftOwner = false;
          _shiftOwnerLookupFinished = true;
        });
      }
    }
  }

  PosProvisionResponse _filterProvisionForOpenShift(
    AuthTokenProvider provider,
    PosProvisionResponse provision,
  ) {
    if (!provider.hasShiftId) return provision;

    final shiftUserId = (provider.shiftUserId?.trim().isNotEmpty == true)
        ? provider.shiftUserId!.trim()
        : (_resolvedShiftUserId?.trim().isNotEmpty == true)
            ? _resolvedShiftUserId!.trim()
            : (provider.activeUserId ?? '').trim();
    if (shiftUserId.isEmpty) return provision;

    final users =
        provision.users.where((user) => user.id == shiftUserId).toList();
    if (users.isEmpty) return provision;

    return PosProvisionResponse(
      id: provision.id,
      name: provision.name,
      number: provision.number,
      key: provision.key,
      accountId: provision.accountId,
      storeId: provision.storeId,
      storeName: provision.storeName,
      allowCustomSalePrices: provision.allowCustomSalePrices,
      allowBelowCostSalePrices: provision.allowBelowCostSalePrices,
      allowRefundsWithoutSale: provision.allowRefundsWithoutSale,
      organizationId: provision.organizationId,
      users: users,
      createdAt: provision.createdAt,
      updatedAt: provision.updatedAt,
    );
  }

  Future<void> _wipeAllLocalData() async {
    final posCubit = context.read<PosCubit>();
    final productsCubit = context.read<ProductsCubit>();
    final authCubit = context.read<AuthCubit>();

    await sl<PosSyncService>().clearAllLocalData();

    await posCubit.resetAllLocalState();
    await productsCubit.reset();
    await authCubit.resetAll();

    if (!mounted) return;
    context.go('/login');
  }

  void _goToPosIfReady() {
    final productsState = context.read<ProductsCubit>().state;
    if (productsState is ProductsLoaded) {
      context.read<PosCubit>().showSales();
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
            sl<PosDiagnosticsService>().recordError(state.message);
            showAuthErrorAlertDialog(
              context,
              message: state.message,
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
          final rawProvision = switch (authState) {
            AuthProvisioned(:final provision) => provision,
            AuthPinStep(:final provision) => provision,
            _ => provider.cachedProvision,
          };

          if (rawProvision == null) {
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

          if (authState is AuthPricingBlocked) {
            return _CashierPricingBlockedView(
              status: authState.status,
              onBack: () =>
                  context.read<AuthCubit>().backToUsers(authState.provision),
            );
          }

          final hasShift = provider.hasShiftId;
          final knownShiftUserId =
              (provider.shiftUserId?.trim().isNotEmpty == true)
                  ? provider.shiftUserId!.trim()
                  : (_resolvedShiftUserId?.trim().isNotEmpty == true)
                      ? _resolvedShiftUserId!.trim()
                      : (provider.activeUserId ?? '').trim();
          if (hasShift &&
              knownShiftUserId.isEmpty &&
              (_resolvingShiftOwner || !_shiftOwnerLookupFinished)) {
            return LoadingStep(
              theme: Theme.of(context),
              title: 'Подготавливаем кассира',
              subtitle: 'Восстанавливаем кассира открытой смены...',
            );
          }

          final provision =
              _filterProvisionForOpenShift(provider, rawProvision);
          final selectedUser = authState is AuthPinStep
              ? authState.user
              : _selectedCachedUser(provider, provision);
          final errorText =
              authState is AuthPinStep ? authState.errorText : null;

          return CashierLoginStep(
            provision: provision,
            selectedUser: selectedUser,
            errorText: errorText,
            onSelectUser: (u) =>
                context.read<AuthCubit>().selectUser(provision, u),
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

  PosUser? _selectedCachedUser(
    AuthTokenProvider provider,
    PosProvisionResponse provision,
  ) {
    final activeUserId = (provider.activeUserId ?? '').trim();
    if (activeUserId.isEmpty) return null;

    for (final user in provision.users) {
      if (user.id == activeUserId) return user;
    }
    return null;
  }
}

class _CashierPricingBlockedView extends StatelessWidget {
  const _CashierPricingBlockedView({
    required this.status,
    required this.onBack,
  });

  final PosPricingPlanStatus status;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planName = (status.pricingPlan?.name ?? '').toString().trim();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFECEC),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    color: Color(0xFFD45F4F),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Доступ к кассе заблокирован',
                  style: theme.textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  planName.isEmpty
                      ? 'Тариф не активен или срок оплаты закончился. Оплатите тариф, чтобы продолжить работу.'
                      : 'Тариф "$planName" не активен или срок оплаты закончился. Оплатите тариф, чтобы продолжить работу.',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const _CashierPricingBlockedInfoRow(
                    label: 'Связаться с менеджером',
                    value: '+7 775 205 11 00',
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: onBack,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD45F4F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Назад к кассирам',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CashierPricingBlockedInfoRow extends StatelessWidget {
  const _CashierPricingBlockedInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

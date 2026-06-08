import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';

import 'package:leemon_app/features/presentation/pages/auth/cashiers_page.dart';
import 'package:leemon_app/features/presentation/pages/auth/login_page.dart';
import 'package:leemon_app/features/presentation/pages/debts/debts_page.dart';
import 'package:leemon_app/features/presentation/pages/pos_page.dart';
import 'package:leemon_app/features/presentation/pages/refund_without_sale/refund_without_sale_page.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/sales_history_page.dart';
import 'package:leemon_app/features/presentation/widgets/close_shift_bottom.dart';

class _GoRouterAuthRefresh extends ChangeNotifier {
  _GoRouterAuthRefresh(Stream stream, Listenable authTokenProvider) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
    _authTokenProvider = authTokenProvider;
    _authTokenProvider.addListener(notifyListeners);
  }
  late final StreamSubscription _sub;
  late final Listenable _authTokenProvider;
  @override
  void dispose() {
    _sub.cancel();
    _authTokenProvider.removeListener(notifyListeners);
    super.dispose();
  }
}

GoRouter createRouter(BuildContext context) {
  final auth = context.read<AuthCubit>();
  final authTokenProvider = context.read<AuthTokenProvider>();

  bool isAuthed(AuthState s) =>
      s is AuthSuccess ||
      s is AuthUnlocked ||
      (authTokenProvider.hasActiveUserId && authTokenProvider.hasShiftId);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _GoRouterAuthRefresh(auth.stream, authTokenProvider),
    redirect: (ctx, state) {
      final authed = isAuthed(auth.state);
      final onLogin = state.matchedLocation == '/login';
      final onCashiers = state.matchedLocation == '/cashiers';
      final onCloseShift = state.matchedLocation == '/close-shift';

      // ✅ если НЕ авторизован — не пускаем никуда кроме /login, /cashiers и /close-shift
      // /close-shift должен дожить до экрана успеха после закрытия смены.
      if (!authed && !onLogin && !onCashiers && !onCloseShift) return '/login';

      // ✅ важное: НЕ редиректим автоматически /login -> /pos,
      // переход делает LoginPage после загрузки товаров / после unlock.
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/cashiers', builder: (_, __) => const CashiersPage()),
      GoRoute(path: '/pos', builder: (_, __) => const PosPage()),
      GoRoute(
        path: '/refund-without-sale',
        builder: (_, __) => const RefundWithoutSalePage(),
      ),
      GoRoute(path: '/history', builder: (_, __) => const SalesHistoryPage()),
      GoRoute(path: '/debts', builder: (_, __) => const DebtsPage()),
      GoRoute(
        path: '/close-shift',
        builder: (_, __) => const CloseShiftPage(),
      ),
    ],
  );
}

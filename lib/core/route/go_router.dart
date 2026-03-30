import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';

import 'package:leemon_app/features/presentation/pages/auth/cashiers_page.dart';
import 'package:leemon_app/features/presentation/pages/auth/login_page.dart';
import 'package:leemon_app/features/presentation/pages/pos_page.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/sales_history_page.dart';
import 'package:leemon_app/features/presentation/widgets/close_shift_bottom.dart';

class _GoRouterAuthRefresh extends ChangeNotifier {
  _GoRouterAuthRefresh(Stream stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter createRouter(BuildContext context) {
  final auth = context.read<AuthCubit>();

  bool isAuthed(AuthState s) => s is AuthSuccess || s is AuthUnlocked;

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _GoRouterAuthRefresh(auth.stream),
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
      GoRoute(path: '/history', builder: (_, __) => const SalesHistoryPage()),
      GoRoute(
        path: '/close-shift',
        builder: (_, __) => const CloseShiftPage(),
      ),
    ],
  );
}

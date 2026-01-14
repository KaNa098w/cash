import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_state.dart';

import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/login_page.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/pos_page.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/sales_history/sales_history_page.dart';

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

      // ✅ если НЕ авторизован — не пускаем никуда кроме /login
      if (!authed && !onLogin) return '/login';

      // ✅ важное: НЕ редиректим автоматически /login -> /pos,
      // переход делает LoginPage после загрузки товаров / после unlock.
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/pos', builder: (_, __) => const PosPage()),
      GoRoute(path: '/history', builder: (_, __) => const SalesHistoryPage()),
    ],
  );
}

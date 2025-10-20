// lib/core/go_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:pos_desktop_clean/features/pos/presentation/pages/login_page.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/pos_page.dart';
import 'package:pos_desktop_clean/features/pos/presentation/state/auth_cubit.dart';

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
  final auth = context.read<AuthCubit>(); // будет доступен из MultiBlocProvider
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _GoRouterAuthRefresh(auth.stream),
    redirect: (ctx, state) {
      final authed = auth.state is AuthAuthenticated;
      final loggingIn = state.matchedLocation == '/login'; // ok для go_router ^14
      if (!authed && !loggingIn) return '/login';
      if (authed && loggingIn) return '/pos';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/pos', builder: (_, __) => const PosPage()),
    ],
  );
}

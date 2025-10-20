// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/di/service_locator.dart';
import 'core/go_router.dart';

import 'features/pos/presentation/state/pos_cubit.dart';
import 'features/pos/presentation/state/auth_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop-инициализация окна
  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await ServiceLocator.instance.init();
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<PosCubit>()..seedDemo()),
        BlocProvider(create: (_) => sl<AuthCubit>()),
      ],
      child: Builder(
        builder: (context) {
          final GoRouter router = createRouter(context);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'POS',
            theme: PosTheme.light(),
            routerConfig: router,
          );
        },
      ),
    );
  }
}

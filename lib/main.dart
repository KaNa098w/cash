// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart'; // ⬅️ добавь

import 'core/theme.dart';
import 'core/di/service_locator.dart';
import 'core/go_router.dart';

import 'features/pos/presentation/state/pos_cubit.dart';
import 'features/pos/presentation/state/auth_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (isDesktop) {
    await windowManager.ensureInitialized();

    const options = WindowOptions(backgroundColor: Colors.transparent);

    await windowManager.waitUntilReadyToShow(options, () async {
      if (Platform.isMacOS) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
      await windowManager.setResizable(false);
      await windowManager.setMinimizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setPreventClose(true);
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(_KioskWindowListener());
  }

  await ServiceLocator.instance.init();
  runApp(const PosApp());
}

class _KioskWindowListener with WindowListener {
  @override
  void onWindowRestore() async {
    await windowManager.setMinimizable(false);
    await windowManager.setFullScreen(true);
    await windowManager.focus();
  }
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

            // ⬇️ ВКЛЮЧАЕМ экранную клавиатуру для всего приложения
            builder: OnscreenKeyboard.builder(
              // ширина панели клавиатуры (например, половина экрана)
              width: (ctx) => MediaQuery.sizeOf(ctx).width * 0.5,
              // при желании можно задать высоту:
              // height: (ctx) => MediaQuery.sizeOf(ctx).height * 0.4,
              // смещение от низа (в пикселях), если нужно:
              // bottom: (ctx) => 0,
            ),
          );
        },
      ),
    );
  }
}

// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:leemon_app/core/di/api/device_id_store.dart';
import 'package:leemon_app/features/domain/repositories/auth_repository.dart';
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/di/api/app_config.dart';
import 'core/di/api/service_locator.dart';
import 'core/route/go_router.dart';

import 'core/provider/auth_provider.dart';
import 'features/domain/repositories/pos_repository.dart';
import 'features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await initializeDateFormatting('ru');
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  _KioskWindowListener? kioskListener;

  final prefs = await SharedPreferences.getInstance();
  final savedEnv = prefs.getString('app_environment');
  final defaultEnv = isDesktop ? AppEnvironment.prod : AppEnvironment.dev;
  final initialEnv = switch (savedEnv) {
    'dev' => AppEnvironment.dev,
    'prod' => AppEnvironment.prod,
    _ => defaultEnv,
  };

  if (isDesktop) {
    await windowManager.ensureInitialized();
    AppConfig.init(env: initialEnv);

    const options = WindowOptions(backgroundColor: Colors.transparent);

    await windowManager.waitUntilReadyToShow(options, () async {
      if (Platform.isMacOS) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }

      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setMinimizable(true);
    });

    await initDependencies();
    kioskListener = _KioskWindowListener();
    windowManager.addListener(kioskListener);
  } else {
    AppConfig.init(env: initialEnv);
    await initDependencies();
  }

  final authProvider = AuthTokenProvider();
  await authProvider.init();
  sl<DeviceIdStore>().deviceId = authProvider.deviceId;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthTokenProvider>.value(value: authProvider),
        BlocProvider<PosCubit>(
          create: (_) => PosCubit(sl<PosRepository>()),
        ),
        BlocProvider<AuthCubit>(
          create: (ctx) => AuthCubit(
            authRepository: sl<AuthRepository>(),
            sessionRepository: sl<SessionRepository>(),
            tokenProvider: ctx.read<AuthTokenProvider>(),
          ),
        ),
        BlocProvider<ProductsCubit>(
          create: (_) => ProductsCubit(sl<ProductRepository>()),
        ),
      ],
      child: const PosApp(),
    ),
  );

  if (isDesktop && kioskListener != null) {
    unawaited(_stabilizeDesktopWindow(kioskListener));
  }
}

Future<void> _stabilizeDesktopWindow(_KioskWindowListener kioskListener) async {
  // Let the native window and first Flutter frame settle before toggling
  // fullscreen. This avoids a first-launch race on Windows where the taskbar
  // icon can disappear and the window may appear to close.
  await Future.delayed(const Duration(milliseconds: 700));
  await kioskListener.ensureKioskMode();
}

class _KioskWindowListener with WindowListener {
  bool _restoring = false;
  DateTime? _lastRunAt;

  Future<void> ensureKioskMode() async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    if (_restoring) return;

    final now = DateTime.now();
    final lastRunAt = _lastRunAt;
    if (lastRunAt != null &&
        now.difference(lastRunAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastRunAt = now;

    _restoring = true;

    try {
      await Future.delayed(const Duration(milliseconds: 80));

      await windowManager.show();
      await windowManager.focus();

      if (!await windowManager.isFullScreen()) {
        await windowManager
            .setFullScreen(true)
            .timeout(const Duration(seconds: 2));
      }

      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setMinimizable(true);
    } catch (_) {
      // Avoid freezing startup if fullscreen transition gets stuck on OS side.
    } finally {
      _restoring = false;
    }
  }

  @override
  void onWindowRestore() {
    unawaited(ensureKioskMode());
  }

  @override
  void onWindowLeaveFullScreen() {
    unawaited(ensureKioskMode());
  }
}

class PosApp extends StatefulWidget {
  const PosApp({super.key});

  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createRouter(context); // ✅ один раз
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'POS',
      routerConfig: _router,
    );
  }
}

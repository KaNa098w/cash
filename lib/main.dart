// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/di/api/device_id_store.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/auth_repository.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/product_repository.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/di/api/app_config.dart';
import 'core/di/api/service_locator.dart';
import 'core/route/go_router.dart';

import 'core/provider/auth_provider.dart';
import 'features/pos/domain/repositories/pos_repository.dart';
import 'features/pos/presentation/state/pos_cubit.dart';
import 'features/pos/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    AppConfig.init(env: AppEnvironment.dev);

    const options = WindowOptions(backgroundColor: Colors.transparent);

    await windowManager.waitUntilReadyToShow(options, () async {
      if (Platform.isMacOS) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
    });

    await initDependencies();
    windowManager.addListener(_KioskWindowListener());
  } else {
    AppConfig.init(env: AppEnvironment.dev);
    await initDependencies();
  }

  // ✅ ВАЖНО: создаём и инициализируем до runApp
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
}

class _KioskWindowListener with WindowListener {
  @override
  void onWindowRestore() async {}
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = createRouter(context);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'POS',
      routerConfig: router,
    );
  }
}

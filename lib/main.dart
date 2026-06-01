// lib/main.dart
import 'dart:async';
import 'dart:io'
    show
        Directory,
        File,
        FileLock,
        FileMode,
        FileSystemException,
        Platform,
        RandomAccessFile;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:leemon_app/core/di/api/device_id_store.dart';
import 'package:leemon_app/core/service/customer_display_service.dart';
import 'package:leemon_app/features/domain/repositories/auth_repository.dart';
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
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

RandomAccessFile? _singleInstanceLock;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop && !Platform.isWindows && !await _acquireSingleInstanceLock()) {
    return;
  }

  await Hive.initFlutter();
  await initializeDateFormatting('ru');
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
    await windowManager.ensureInitialized().timeout(const Duration(seconds: 3));
    AppConfig.init(env: initialEnv);
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
    unawaited(_showDesktopWindow(kioskListener));
  }

  unawaited(_initializeLocalSync());
}

Future<bool> _acquireSingleInstanceLock() async {
  final lockFile = File('${Directory.systemTemp.path}/leemon_pos_app.lock');

  try {
    _singleInstanceLock = await lockFile.open(mode: FileMode.write);
    await _singleInstanceLock!.lock(FileLock.exclusive);
    return true;
  } on FileSystemException {
    await _singleInstanceLock?.close();
    _singleInstanceLock = null;
    return false;
  }
}

Future<void> _showDesktopWindow(_KioskWindowListener kioskListener) async {
  const options = WindowOptions(backgroundColor: Colors.transparent);

  Future<void> showAndFocus() async {
    if (Platform.isMacOS) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setMinimumSize(const Size(1200, 800));
      await windowManager.center();
    }

    if (!Platform.isMacOS) {
      await windowManager
          .setFullScreen(true)
          .timeout(const Duration(seconds: 2));
    }

    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    await windowManager.setMinimizable(true);
  }

  try {
    await windowManager
        .waitUntilReadyToShow(options, showAndFocus)
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // If the plugin never reports readiness, still show the already-created
    // native window so startup cannot leave only a background process.
    await showAndFocus();
  }

  // Let the native window and first Flutter frame settle before toggling
  // fullscreen. This avoids a first-launch race on Windows where the taskbar
  // icon can disappear and the window may appear to close.
  await Future.delayed(const Duration(milliseconds: 250));
  await kioskListener.ensureKioskMode();
}

Future<void> _initializeLocalSync() async {
  try {
    await sl<PosSyncService>().initialize().timeout(const Duration(seconds: 8));
  } catch (_) {
    // The UI must still open if the local sync database is temporarily locked
    // or slow. Sync will be initialized lazily on the next sync operation.
  }
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

      if (!Platform.isMacOS && !await windowManager.isFullScreen()) {
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
  final _customerDisplay = CustomerDisplayService();
  StreamSubscription<void>? _productsSyncSub;
  StreamSubscription<PosState>? _posStateSub;
  num? _lastCustomerDisplayTotal;

  @override
  void initState() {
    super.initState();
    _router = createRouter(context);
    _productsSyncSub = sl<PosSyncService>().onProductsChanged.listen((_) {
      if (!mounted) return;
      context.read<ProductsCubit>().loadFirstPage(key: '');
    });
    final posCubit = context.read<PosCubit>();
    _sendTotalToCustomerDisplay(posCubit.state);
    _posStateSub = posCubit.stream.listen(_sendTotalToCustomerDisplay);
  }

  @override
  void dispose() {
    _productsSyncSub?.cancel();
    _posStateSub?.cancel();
    super.dispose();
  }

  void _sendTotalToCustomerDisplay(PosState state) {
    final total = state.items.fold<num>(0, (sum, item) => sum + item.sum);
    if (_lastCustomerDisplayTotal == total) return;
    _lastCustomerDisplayTotal = total;
    _customerDisplay.showTotal(total);
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.light();

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'POS',
      routerConfig: _router,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
        primaryTextTheme:
            GoogleFonts.interTextTheme(baseTheme.primaryTextTheme),
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
    );
  }
}

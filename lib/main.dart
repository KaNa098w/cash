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
import 'package:leemon_app/core/service/device_window_mode_service.dart';
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
  final savedDeviceMode = DeviceWindowMode.fromValue(
    prefs.getString(deviceWindowModePrefsKey),
  );
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
    kioskListener =
        _KioskWindowListener(savedDeviceMode ?? DeviceWindowMode.monoblock);
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
      child: const _PosApp(),
    ),
  );

  if (isDesktop && kioskListener != null) {
    unawaited(_showDesktopWindow(kioskListener.mode));
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

Future<void> _showDesktopWindow(DeviceWindowMode? savedMode) async {
  const options = WindowOptions(backgroundColor: Colors.transparent);
  final startupMode = savedMode ?? DeviceWindowMode.monoblock;

  Future<void> showAndFocus() async {
    if (Platform.isMacOS) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }

    await DeviceWindowModeService.apply(startupMode);
    await windowManager.show();
    await windowManager.focus();
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

  // Keep the saved screen mode on restart. Fresh installs still open as
  // monoblock until the cashier changes the mode from the in-app menu.
  await Future.delayed(const Duration(milliseconds: 250));
  await DeviceWindowModeService.apply(startupMode);
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
  _KioskWindowListener(this.mode);

  DeviceWindowMode? mode;
  bool _restoring = false;
  DateTime? _lastRunAt;

  void updateMode(DeviceWindowMode nextMode) {
    mode = nextMode;
  }

  Future<void> ensureWindowMode() async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    final savedMode = await DeviceWindowModeService.load();
    if (savedMode != null) {
      mode = savedMode;
    }
    final currentMode = mode;
    if (currentMode == null) return;
    if (currentMode == DeviceWindowMode.laptop) return;
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
      await DeviceWindowModeService.apply(currentMode);
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // Avoid freezing startup if fullscreen transition gets stuck on OS side.
    } finally {
      _restoring = false;
    }
  }

  @override
  void onWindowRestore() {
    unawaited(ensureWindowMode());
  }

  @override
  void onWindowLeaveFullScreen() {
    unawaited(ensureWindowMode());
  }
}

class _PosApp extends StatefulWidget {
  const _PosApp();

  @override
  State<_PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<_PosApp> {
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

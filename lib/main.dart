// lib/main.dart
import 'dart:async';
import 'dart:convert' show jsonDecode, utf8;
import 'dart:io'
    show
        Directory,
        exit,
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
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:leemon_app/core/di/api/device_id_store.dart';
import 'package:leemon_app/core/service/customer_display_service.dart';
import 'package:leemon_app/core/service/device_window_mode_service.dart';
import 'package:leemon_app/core/service/pos_diagnostics_service.dart';
import 'package:leemon_app/features/domain/repositories/auth_repository.dart';
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:path_provider/path_provider.dart';
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
final List<Map<String, dynamic>> _startupLocalStorageIssues = [];
final _AppShutdownCoordinator _shutdownCoordinator = _AppShutdownCoordinator();
bool _appUiStarted = false;
bool _startupFailureUiShown = false;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(_recordStartupError(details.exception, details.stack));
    };
    await _bootstrapApp();
  }, (error, stackTrace) {
    unawaited(_recordStartupError(error, stackTrace));
    // Never replace an already running cash register with the startup failure
    // screen because of an uncaught background Future. The error is persisted
    // to diagnostics and the current UI remains usable.
    if (_appUiStarted || _startupFailureUiShown) return;
    _startupFailureUiShown = true;
    runApp(_StartupFailureApp(error: error));
  });
}

Future<void> _bootstrapApp() async {
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop && !Platform.isWindows && !await _acquireSingleInstanceLock()) {
    return;
  }

  try {
    // Hive currently has no runtime consumers. Its failure must not prevent the
    // POS, SQLite storage and offline queue from starting.
    await Hive.initFlutter();
  } catch (error, stackTrace) {
    await _recordStartupError(error, stackTrace);
  }
  try {
    await initializeDateFormatting('ru');
  } catch (error, stackTrace) {
    // Intl can fall back to basic formatting; this is not a reason to stop POS.
    await _recordStartupError(error, stackTrace);
  }
  _KioskWindowListener? kioskListener;

  final prefs = await _loadSharedPreferencesWithRecovery();
  final savedEnv = prefs?.getString('app_environment');
  final savedDeviceMode = DeviceWindowMode.fromValue(
    prefs?.getString(deviceWindowModePrefsKey),
  );
  final defaultEnv = isDesktop ? AppEnvironment.prod : AppEnvironment.dev;
  final initialEnv = switch (savedEnv) {
    'dev' => AppEnvironment.dev,
    'prod' => AppEnvironment.prod,
    _ => defaultEnv,
  };

  if (isDesktop) {
    var windowManagerReady = false;
    try {
      await windowManager
          .ensureInitialized()
          .timeout(const Duration(seconds: 3));
      windowManagerReady = true;
      await windowManager.setPreventClose(true);
    } catch (error, stackTrace) {
      // A window-management plugin failure should not replace the application
      // if Flutter can still create and display its native window.
      await _recordStartupError(error, stackTrace);
    }
    AppConfig.init(env: initialEnv);
    await initDependencies();
    _publishStartupLocalStorageIssues();
    if (windowManagerReady) {
      kioskListener = _KioskWindowListener(
        savedDeviceMode ?? DeviceWindowMode.monoblock,
        shutdownCoordinator: _shutdownCoordinator,
      );
      windowManager.addListener(kioskListener);
    }
  } else {
    AppConfig.init(env: initialEnv);
    await initDependencies();
    _publishStartupLocalStorageIssues();
  }

  final authProvider = AuthTokenProvider();
  try {
    await authProvider.init();
  } catch (error, stackTrace) {
    // Continue to the key/login screen with an empty in-memory provider. A
    // local preferences failure must not prevent the cashier UI from opening.
    await _recordStartupError(error, stackTrace);
  }
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
  _appUiStarted = true;

  if (isDesktop && kioskListener != null) {
    unawaited(_showDesktopWindow(kioskListener.mode));
  }

  unawaited(_initializeLocalSync());
}

Future<SharedPreferences?> _loadSharedPreferencesWithRecovery() async {
  try {
    return await SharedPreferences.getInstance();
  } on FormatException catch (error, stackTrace) {
    await _recordStartupError(error, stackTrace);
    final recovered = await _quarantineCorruptedSharedPreferences();
    if (recovered) {
      try {
        return await SharedPreferences.getInstance();
      } catch (retryError, retryStackTrace) {
        await _recordStartupError(retryError, retryStackTrace);
      }
    }
    return null;
  } catch (error, stackTrace) {
    await _recordStartupError(error, stackTrace);
    return null;
  }
}

Future<bool> _quarantineCorruptedSharedPreferences() async {
  if (kIsWeb || !Platform.isWindows) return false;

  try {
    final supportDir = await getApplicationSupportDirectory();
    final prefsFile = File('${supportDir.path}/shared_preferences.json');
    if (!await prefsFile.exists()) return false;

    final description = await _describeFileForStartupLog(prefsFile);
    final backupFile = File(
      '${prefsFile.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}.bak',
    );
    await prefsFile.rename(backupFile.path);
    _startupLocalStorageIssues.add({
      'at': DateTime.now().toIso8601String(),
      'type': 'corrupted_shared_preferences',
      'file': prefsFile.path,
      'quarantined_to': backupFile.path,
      'description': description,
      'action': 'ignored_corrupted_json_and_started_with_clean_preferences',
    });
    await _recordStartupError(
      'Corrupted SharedPreferences moved to ${backupFile.path}. $description',
      StackTrace.current,
    );
    return true;
  } catch (error, stackTrace) {
    await _recordStartupError(error, stackTrace);
    return false;
  }
}

void _publishStartupLocalStorageIssues() {
  if (_startupLocalStorageIssues.isEmpty) return;
  if (!sl.isRegistered<PosDiagnosticsService>()) return;
  final diagnostics = sl<PosDiagnosticsService>();
  for (final issue in _startupLocalStorageIssues) {
    diagnostics.recordLocalStorageIssue(issue);
  }
}

Future<String> _describeFileForStartupLog(File file) async {
  try {
    final bytes = await file.openRead(0, 64).fold<List<int>>(
      <int>[],
      (previous, chunk) => previous..addAll(chunk),
    );
    final size = await file.length();
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
    final preview = utf8.decode(bytes, allowMalformed: true);
    return 'size=$size firstBytesHex="$hex" preview="$preview"';
  } catch (error) {
    return 'Could not describe corrupted file: $error';
  }
}

Future<void> _recordStartupError(Object error, StackTrace? stackTrace) async {
  if (kIsWeb) return;
  try {
    final logFile = File('${Directory.systemTemp.path}/leemon_pos_startup.log');
    await logFile.writeAsString(
      '[${DateTime.now().toIso8601String()}] $error\n$stackTrace\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _StartupFailurePage(error: error),
    );
  }
}

class _StartupFailurePage extends StatefulWidget {
  const _StartupFailurePage({required this.error});

  final Object error;

  @override
  State<_StartupFailurePage> createState() => _StartupFailurePageState();
}

class _StartupFailurePageState extends State<_StartupFailurePage> {
  String? _posKey;
  bool _loadingKey = true;
  bool _copiedKey = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPosKey());
  }

  Future<void> _loadPosKey() async {
    final key = await _readStoredPosKeyForRecovery();
    if (!mounted) return;
    setState(() {
      _posKey = key;
      _loadingKey = false;
    });
  }

  Future<void> _copyKey() async {
    final key = _posKey;
    if (key == null || key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) return;
    setState(() => _copiedKey = true);
  }

  @override
  Widget build(BuildContext context) {
    final keyAvailable = (_posKey ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 44,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Не удалось запустить кассу',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Если ошибка повторится, отправьте файл лога из временной папки Windows: leemon_pos_startup.log. Локальные данные кассы не очищаются автоматически.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                    const SizedBox(height: 18),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ключ кассы',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF374151),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_loadingKey)
                              const Text(
                                'Ищем сохраненный ключ...',
                                style: TextStyle(color: Color(0xFF6B7280)),
                              )
                            else if (keyAvailable)
                              SelectableText(
                                _posKey!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              )
                            else
                              const Text(
                                'Ключ не найден в локальных данных.',
                                style: TextStyle(color: Color(0xFF6B7280)),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: keyAvailable ? _copyKey : null,
                                  icon: const Icon(Icons.copy_rounded),
                                  label: Text(_copiedKey
                                      ? 'Ключ скопирован'
                                      : 'Копировать ключ'),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    keyAvailable && !_copiedKey
                                        ? 'Сохраните ключ, чтобы можно было повторно привязать кассу.'
                                        : 'Ключ сохранен в буфере обмена.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      widget.error.toString(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _readStoredPosKeyForRecovery() async {
  if (kIsWeb) return null;

  try {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('posKey')?.trim();
    if (key != null && key.isNotEmpty) return key;
  } catch (_) {}

  try {
    final supportDir = await getApplicationSupportDirectory();
    final candidates = <File>[
      File('${supportDir.path}/shared_preferences.json'),
      ...supportDir.listSync().whereType<File>().where((file) {
        final name = file.uri.pathSegments.last;
        return name.startsWith('shared_preferences.json.corrupt') &&
            name.endsWith('.bak');
      }).toList()
        ..sort((a, b) => b.path.compareTo(a.path)),
    ];

    for (final file in candidates) {
      if (!await file.exists()) continue;
      final key = _extractPosKeyFromPreferencesText(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
      );
      if (key != null && key.isNotEmpty) return key;
    }
  } catch (_) {}

  return null;
}

String? _extractPosKeyFromPreferencesText(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final value = decoded['flutter.posKey'] ?? decoded['posKey'];
      final key = value?.toString().trim();
      if (key != null && key.isNotEmpty) return key;
    }
  } catch (_) {}

  for (final pattern in const [
    r'"flutter\.posKey"\s*:\s*"([^"]+)"',
    r'"posKey"\s*:\s*"([^"]+)"',
  ]) {
    final match = RegExp(pattern).firstMatch(text);
    final key = match?.group(1)?.trim();
    if (key != null && key.isNotEmpty) return key;
  }

  return null;
}

class _AppShutdownCoordinator {
  final List<Future<void> Function()> _callbacks = [];
  bool _isClosing = false;

  void addCallback(Future<void> Function() callback) {
    _callbacks.add(callback);
  }

  void removeCallback(Future<void> Function() callback) {
    _callbacks.remove(callback);
  }

  Future<void> closeApp() async {
    if (_isClosing) return;
    _isClosing = true;

    try {
      await _runCallbacks().timeout(const Duration(seconds: 2));
    } catch (error, stackTrace) {
      await _recordStartupError(error, stackTrace);
    } finally {
      try {
        await windowManager.setPreventClose(false);
      } catch (_) {}
      try {
        await windowManager.destroy();
      } catch (_) {
        exit(0);
      }
    }
  }

  Future<void> _runCallbacks() async {
    for (final callback in List<Future<void> Function()>.from(_callbacks)) {
      try {
        await callback().timeout(const Duration(milliseconds: 900));
      } catch (error, stackTrace) {
        await _recordStartupError(error, stackTrace);
      }
    }

    if (sl.isRegistered<PosSyncService>()) {
      try {
        final sync = sl<PosSyncService>();
        sync.stopBackgroundLoops();
        await sync.dispose().timeout(const Duration(milliseconds: 900));
      } catch (error, stackTrace) {
        await _recordStartupError(error, stackTrace);
      }
    }
  }
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
  _KioskWindowListener(
    this.mode, {
    required this.shutdownCoordinator,
  });

  DeviceWindowMode? mode;
  final _AppShutdownCoordinator shutdownCoordinator;
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
  void onWindowClose() {
    unawaited(shutdownCoordinator.closeApp());
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
  late final Future<void> Function() _shutdownCallback;
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
    _shutdownCallback = () async {
      await posCubit.flushPendingState();
    };
    _shutdownCoordinator.addCallback(_shutdownCallback);
  }

  @override
  void dispose() {
    _shutdownCoordinator.removeCallback(_shutdownCallback);
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

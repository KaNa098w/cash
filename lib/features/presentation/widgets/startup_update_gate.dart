import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:leemon_app/core/di/api/app_version.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/app_update_response.dart';
import 'package:leemon_app/features/data/datasources/app_update_remote_datasource.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

const String _startupAppUpdateChannel =
    String.fromEnvironment('APP_UPDATE_CHANNEL', defaultValue: 'stable');
const String _startupPreferredUpdatePackageType =
    String.fromEnvironment('APP_UPDATE_PACKAGE_TYPE', defaultValue: 'zip');
const String _startupAppExeName = 'Leemon.exe';
const String _startupUpdaterExeName = 'Leemon.Updater.exe';

enum _StartupUpdateStage {
  idle,
  checking,
  available,
  downloading,
  applying,
  failed,
}

class StartupUpdateGate extends StatefulWidget {
  const StartupUpdateGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends State<StartupUpdateGate> {
  _StartupUpdateStage _stage = _StartupUpdateStage.idle;
  AppUpdateResponse? _latest;
  double _progress = 0;
  String _statusText = '';
  String? _error;
  bool _started = false;

  bool get _supportsAutoUpdate => !kIsWeb && Platform.isWindows && !kDebugMode;

  bool get _showOverlay =>
      _stage == _StartupUpdateStage.available ||
      _stage == _StartupUpdateStage.downloading ||
      _stage == _StartupUpdateStage.applying ||
      _stage == _StartupUpdateStage.failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdatesOnStartup());
    });
  }

  Future<void> _checkForUpdatesOnStartup() async {
    if (_started || !_supportsAutoUpdate) return;
    _started = true;

    setState(() {
      _stage = _StartupUpdateStage.checking;
      _error = null;
    });

    try {
      final updateApi = sl<AppUpdateRemoteDataSource>();
      final latest = await updateApi.fetchLatest(
        channel: _startupAppUpdateChannel,
        currentVersion: kAppVersion,
        packageType: _startupPreferredUpdatePackageType,
      );

      if (!mounted) return;

      if (latest.updateAvailable &&
          _compareVersionStrings(latest.latestVersion, kAppVersion) > 0) {
        setState(() {
          _latest = latest;
          _stage = _StartupUpdateStage.available;
          _statusText = 'Найдена новая версия ${latest.latestVersion}';
        });
        await Future.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        await _downloadAndInstall();
        return;
      }

      if (!mounted) return;
      setState(() {
        _stage = _StartupUpdateStage.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _StartupUpdateStage.idle;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final latest = _latest;
    if (latest == null) return;

    setState(() {
      _stage = _StartupUpdateStage.downloading;
      _progress = 0.04;
      _statusText = 'Подготавливаем обновление...';
      _error = null;
    });

    try {
      final file = await _downloadUpdatePackage(
        latest,
        onProgress: (value, text) {
          if (!mounted) return;
          setState(() {
            _progress = value;
            _statusText = text;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _stage = _StartupUpdateStage.applying;
        _progress = 0.96;
        _statusText = 'Устанавливаем обновление и перезапускаем приложение...';
      });

      await _installAndRestartApp(file, latest);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _StartupUpdateStage.failed;
        _error = e.toString();
        _statusText = 'Не удалось установить обновление';
      });
    }
  }

  Future<File> _downloadUpdatePackage(
    AppUpdateResponse latest, {
    required void Function(double value, String text) onProgress,
  }) async {
    final dio = sl<Dio>();
    final directory = await getTemporaryDirectory();
    final safeVersion =
        latest.latestVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final packageType = latest.packageType.trim().toLowerCase();
    final extension = switch (packageType) {
      'zip' => 'zip',
      'exe' => 'exe',
      _ => packageType.isEmpty ? 'bin' : packageType,
    };
    final targetPath = path.join(
      directory.path,
      'leemon_startup_update_$safeVersion.$extension',
    );
    final target = File(targetPath);

    if (await target.exists()) {
      await target.delete();
    }

    onProgress(0.08, 'Скачиваем обновление...');

    await dio.download(
      latest.downloadUrl,
      target.path,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final ratio = received / total;
        final progress = 0.08 + (ratio.clamp(0.0, 1.0) * 0.82);
        onProgress(
          progress,
          'Скачиваем обновление... ${(ratio * 100).round()}%',
        );
      },
    );

    onProgress(0.92, 'Проверяем целостность файла...');

    final actualSize = await target.length();
    if (latest.fileSize > 0 && actualSize != latest.fileSize) {
      throw Exception('Размер скачанного файла не совпадает с серверным.');
    }

    if (latest.checksumSha256.isNotEmpty) {
      final bytes = await target.readAsBytes();
      final actual = sha256.convert(bytes).toString().toLowerCase();
      if (actual != latest.checksumSha256.toLowerCase()) {
        throw Exception('Контрольная сумма файла обновления не совпала.');
      }
    }

    return target;
  }

  Future<void> _installAndRestartApp(
    File file,
    AppUpdateResponse latest,
  ) async {
    if (!file.existsSync()) {
      throw Exception('Файл обновления не найден на диске.');
    }

    if (!Platform.isWindows) {
      throw Exception(
          'Автообновление сейчас поддерживается только на Windows.');
    }

    final packageType = latest.packageType.trim().toLowerCase();
    if (packageType == 'zip') {
      await _runZipUpdater(file);
      return;
    }
    if (packageType == 'exe') {
      await _runSilentInstaller(file);
      return;
    }

    throw Exception(
        'Неподдерживаемый тип пакета обновления: ${latest.packageType}');
  }

  Future<void> _runZipUpdater(File packageFile) async {
    final updaterFile = _resolveUpdaterExecutable();
    if (!await updaterFile.exists()) {
      throw Exception(
        'Updater не найден: ${updaterFile.path}. Установите сборку с updater.',
      );
    }

    final targetDir = File(Platform.resolvedExecutable).parent.path;
    await Process.start(
      updaterFile.path,
      [
        '--zip',
        packageFile.path,
        '--target-dir',
        targetDir,
        '--app-exe',
        _startupAppExeName,
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: updaterFile.parent.path,
    );

    await Future.delayed(const Duration(milliseconds: 450));
    await _exitAppFully();
  }

  Future<void> _runSilentInstaller(File installerFile) async {
    await Process.start(
      installerFile.path,
      const [
        '/SP-',
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
      ],
      mode: ProcessStartMode.detached,
    );

    await Future.delayed(const Duration(milliseconds: 450));
    await _exitAppFully();
  }

  File _resolveUpdaterExecutable() {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return File(path.join(appDir, 'updater', _startupUpdaterExeName));
  }

  Future<void> _exitAppFully() async {
    if (kIsWeb) return;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;

    try {
      final wasFullScreen = await windowManager.isFullScreen();
      if (wasFullScreen) {
        await windowManager.setFullScreen(false);
        await Future.delayed(const Duration(milliseconds: 80));
      }
      await windowManager.close();
      await Future.delayed(const Duration(milliseconds: 2500));
      exit(0);
    } catch (_) {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final latest = _latest;
    final theme = Theme.of(context);

    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFFF4EFE6),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF7F1E6),
                Color(0xFFE6EEF8),
                Color(0xFFF7F8FB),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -120,
                left: -70,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2563EB).withOpacity(0.08),
                  ),
                ),
              ),
              Positioned(
                right: -90,
                bottom: -120,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F766E).withOpacity(0.08),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.fromLTRB(32, 30, 32, 28),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 38,
                          offset: const Offset(0, 22),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF2563EB),
                                    Color(0xFF0EA5E9),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.system_update_alt_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _stage == _StartupUpdateStage.failed
                                        ? 'Не удалось обновить приложение'
                                        : 'Доступно новое обновление',
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _stage == _StartupUpdateStage.failed
                                        ? 'Можно продолжить работу на текущей версии.'
                                        : 'Подождите чуть-чуть, приложение само обновится.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: const Color(0xFF4B5563),
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (latest != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                _VersionBadge(
                                  label: 'Сейчас',
                                  value: kAppVersion,
                                  valueColor: const Color(0xFF475569),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                _VersionBadge(
                                  label: 'Обновление',
                                  value: latest.latestVersion,
                                  valueColor: const Color(0xFF2563EB),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 14,
                            value: _stage == _StartupUpdateStage.failed
                                ? null
                                : _progress.clamp(0.0, 1.0),
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusText.isEmpty
                              ? 'Подготовка обновления...'
                              : _statusText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        if (latest?.releaseNotes.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Что нового',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  latest!.releaseNotes.trim(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_stage == _StartupUpdateStage.failed &&
                            _error != null) ...[
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _stage = _StartupUpdateStage.idle;
                                  _error = null;
                                });
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF111827),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Продолжить без обновления'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

int _compareVersionStrings(String newest, String installed) {
  final newParts = _normalizeVersion(newest);
  final installedParts = _normalizeVersion(installed);
  final len = newParts.length > installedParts.length
      ? newParts.length
      : installedParts.length;

  for (int i = 0; i < len; i++) {
    final n = i < newParts.length ? newParts[i] : 0;
    final c = i < installedParts.length ? installedParts[i] : 0;
    if (n > c) return 1;
    if (n < c) return -1;
  }

  return 0;
}

List<int> _normalizeVersion(String value) {
  final base = value.split('+').first;
  final parts = base.split('.');
  return parts
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
      .toList();
}

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

const String _appUpdateChannel =
    String.fromEnvironment('APP_UPDATE_CHANNEL', defaultValue: 'stable');
const String _preferredUpdatePackageType =
    String.fromEnvironment('APP_UPDATE_PACKAGE_TYPE', defaultValue: 'zip');
const String _appExeName = 'Leemon.exe';
const String _updaterExeName = 'Leemon.Updater.exe';

Future<void> checkForAppUpdateAfterCashierLogin(BuildContext context) async {
  if (kIsWeb || !Platform.isWindows || kDebugMode) return;

  try {
    final updateApi = sl<AppUpdateRemoteDataSource>();
    final latest = await updateApi.fetchLatest(
      channel: _appUpdateChannel,
      currentVersion: kAppVersion,
      packageType: _preferredUpdatePackageType,
    );

    if (!context.mounted) return;
    if (!latest.updateAvailable) return;
    if (_compareVersionStrings(latest.latestVersion, kAppVersion) <= 0) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !latest.isMandatory,
      builder: (_) => _UpdateAvailableDialog(latest: latest),
    );
  } catch (_) {
    // Silent by design: cashier login must not be blocked by update/network issues.
  }
}

class _UpdateAvailableDialog extends StatefulWidget {
  const _UpdateAvailableDialog({required this.latest});

  final AppUpdateResponse latest;

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  bool _installing = false;
  double _progress = 0;
  String _status = 'Подготовка обновления...';
  String? _error;

  Future<void> _install() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _progress = 0.04;
      _status = 'Подготовка обновления...';
      _error = null;
    });

    try {
      final file = await _downloadUpdatePackage(
        widget.latest,
        onProgress: (value, text) {
          if (!mounted) return;
          setState(() {
            _progress = value;
            _status = text;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _progress = 0.96;
        _status = 'Устанавливаем обновление...';
      });

      await _installAndRestartApp(file, widget.latest);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.latest;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Доступно обновление',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Касса уже открыта. Можно обновить приложение сейчас или позже.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _VersionPill(
                    label: 'Сейчас',
                    version: kAppVersion,
                    color: const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 10),
                  _VersionPill(
                    label: 'Новая',
                    version: latest.latestVersion,
                    color: const Color(0xFF2563EB),
                  ),
                ],
              ),
              if (latest.releaseNotes.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    latest.releaseNotes.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
              ],
              if (_installing) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 12,
                    value: _progress.clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _status,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB91C1C),
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!latest.isMandatory)
                    TextButton(
                      onPressed: _installing
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Позже'),
                    ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _installing ? null : _install,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                    child: Text(_installing ? 'Обновляем...' : 'Обновить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.label,
    required this.version,
    required this.color,
  });

  final String label;
  final String version;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              version,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
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

  final target = File(
    path.join(directory.path, 'leemon_update_$safeVersion.$extension'),
  );

  if (await target.exists()) {
    await target.delete();
  }

  await dio.download(
    latest.downloadUrl,
    target.path,
    onReceiveProgress: (received, total) {
      if (total <= 0) return;
      final ratio = received / total;
      onProgress(
        0.08 + (ratio.clamp(0.0, 1.0) * 0.82),
        'Скачивание: ${(ratio * 100).round()}%',
      );
    },
  );

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

Future<void> _installAndRestartApp(File file, AppUpdateResponse latest) async {
  if (!file.existsSync()) {
    throw Exception('Файл обновления не найден на диске.');
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
    'Неподдерживаемый тип пакета обновления: ${latest.packageType}',
  );
}

Future<void> _runZipUpdater(File packageFile) async {
  final updaterFile = _resolveUpdaterExecutable();
  if (!await updaterFile.exists()) {
    throw Exception('Updater не найден: ${updaterFile.path}');
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
      _appExeName,
    ],
    mode: ProcessStartMode.detached,
    workingDirectory: updaterFile.parent.path,
  );

  await Future.delayed(const Duration(milliseconds: 350));
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

  await Future.delayed(const Duration(milliseconds: 350));
  await _exitAppFully();
}

File _resolveUpdaterExecutable() {
  final appDir = File(Platform.resolvedExecutable).parent.path;
  return File(path.join(appDir, 'updater', _updaterExeName));
}

Future<void> _exitAppFully() async {
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
  return base
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
      .toList();
}

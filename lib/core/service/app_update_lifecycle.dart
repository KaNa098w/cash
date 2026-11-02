import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:leemon_app/core/di/api/app_version.dart';

/// Handoff is acknowledged only after the helper has validated the archive.
/// The running register must stay open if staging or permissions fail.
class AppUpdateLifecycle {
  static String? _startupToken;
  static bool _recovered = false;
  static bool get launchedByUpdater => _startupToken != null;
  static bool _handoffInProgress = false;

  static Future<void> finishHandoff(Future<void> Function() close) async {
    // The basket has already been flushed before handoff. A hung window plugin
    // must not leave the updater waiting forever for this process to exit.
    await close().timeout(const Duration(seconds: 8), onTimeout: () => exit(0));
  }

  static File resolveUpdater(String appDirectory, String executableName) {
    // The root copy is also delivered by the legacy helper, which skipped the
    // entire updater/ folder. This lets existing registers adopt the new helper.
    final root = File(path.join(appDirectory, executableName));
    return root.existsSync()
        ? root
        : File(path.join(appDirectory, 'updater', executableName));
  }

  static void configureStartup(List<String> arguments) {
    final index = arguments.indexOf('--leemon-update-token');
    final token =
        index >= 0 && index + 1 < arguments.length ? arguments[index + 1] : '';
    _startupToken = RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(token) ? token : null;
    _recovered = arguments.contains('--leemon-update-recovered');
  }

  static Future<void> confirmStartup() async {
    final token = _startupToken;
    if (token == null || _recovered) return;
    final directory = Directory(
        path.join(Directory.systemTemp.path, 'leemon_updater_$token'));
    if (!await directory.exists()) return;
    final marker = File(path.join(directory.path, 'healthy.tmp'));
    await marker.writeAsString(jsonEncode({'version': kAppVersion}),
        flush: true);
    await marker.rename(path.join(directory.path, 'healthy'));
  }

  static Future<bool> shouldSkipAutomatic(String version,
      {String? appDirectory}) async {
    if (launchedByUpdater) return true;
    try {
      final file = File(path.join(
          appDirectory ?? File(Platform.resolvedExecutable).parent.path,
          '.leemon-update',
          'last-failure.json'));
      if (!await file.exists()) return false;
      final data = jsonDecode(await file.readAsString());
      return data is Map && data['version'] == version;
    } catch (_) {
      return false;
    }
  }

  static Future<void> prepareZipUpdate({
    required File packageFile,
    required File updaterFile,
    required String targetDirectory,
    required String appExeName,
    required String version,
    Future<void> Function()? beforeShutdown,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (_handoffInProgress) {
      throw StateError('Обновление уже подготавливается.');
    }
    _handoffInProgress = true;
    try {
      if (!await updaterFile.exists()) {
        throw StateError(
            'Не найден модуль обновления. Установите актуальный установщик кассы.');
      }
      final token = const Uuid().v4().replaceAll('-', '');
      final directory = await Directory(
              path.join(Directory.systemTemp.path, 'leemon_updater_$token'))
          .create(recursive: true);
      final helper = await updaterFile
          .copy(path.join(directory.path, 'Leemon.Updater.exe'));
      await Process.start(
          helper.path,
          [
            '--zip',
            packageFile.path,
            '--target-dir',
            targetDirectory,
            '--app-exe',
            appExeName,
            '--version',
            version,
            '--token',
            token,
          ],
          mode: ProcessStartMode.detached,
          workingDirectory: directory.path);
      final clock = Stopwatch()..start();
      final ready = File(path.join(directory.path, 'ready'));
      final error = File(path.join(directory.path, 'error'));
      while (clock.elapsed < timeout) {
        if (await error.exists()) {
          throw StateError(
              'Обновление не подготовлено: ${await error.readAsString()}');
        }
        if (await ready.exists()) {
          await beforeShutdown?.call();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw TimeoutException(
          'Обновлятор не подтвердил готовность. Касса остаётся открытой. Возможно, требуется обновить установщик.');
    } finally {
      _handoffInProgress = false;
    }
  }
}

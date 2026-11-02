import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:leemon_app/core/service/app_update_lifecycle.dart';
import 'package:leemon_app/core/di/api/app_version.dart';

void main() {
  setUp(() => AppUpdateLifecycle.configureStartup([]));
  tearDown(() => AppUpdateLifecycle.configureStartup([]));

  test('root helper permits migration from legacy updater folder exclusion',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('leemon_update_test_');
    addTearDown(() => directory.delete(recursive: true));
    final legacy =
        await Directory(path.join(directory.path, 'updater')).create();
    await File(path.join(legacy.path, 'Leemon.Updater.exe'))
        .writeAsString('legacy');
    expect(
        AppUpdateLifecycle.resolveUpdater(directory.path, 'Leemon.Updater.exe')
            .path,
        path.join(legacy.path, 'Leemon.Updater.exe'));
    final root = await File(path.join(directory.path, 'Leemon.Updater.exe'))
        .writeAsString('new');
    expect(
        AppUpdateLifecycle.resolveUpdater(directory.path, 'Leemon.Updater.exe')
            .path,
        root.path);
  });

  test(
      'a failed release is skipped automatically without blocking newer releases',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('leemon_update_test_');
    addTearDown(() => directory.delete(recursive: true));
    final state =
        await Directory(path.join(directory.path, '.leemon-update')).create();
    await File(path.join(state.path, 'last-failure.json'))
        .writeAsString(jsonEncode({'version': '2.0.0'}));
    expect(
        await AppUpdateLifecycle.shouldSkipAutomatic('2.0.0',
            appDirectory: directory.path),
        isTrue);
    expect(
        await AppUpdateLifecycle.shouldSkipAutomatic('2.0.1',
            appDirectory: directory.path),
        isFalse);
  });

  test('startup acknowledgment is written only for a valid trial launch',
      () async {
    final token = const Uuid().v4().replaceAll('-', '');
    final directory = await Directory(
            path.join(Directory.systemTemp.path, 'leemon_updater_$token'))
        .create();
    addTearDown(() => directory.delete(recursive: true));
    final healthy = File(path.join(directory.path, 'healthy'));
    AppUpdateLifecycle.configureStartup(
        ['--leemon-update-token', '../invalid']);
    await AppUpdateLifecycle.confirmStartup();
    expect(await healthy.exists(), isFalse);
    AppUpdateLifecycle.configureStartup(
        ['--leemon-update-token', token, '--leemon-update-recovered']);
    await AppUpdateLifecycle.confirmStartup();
    expect(await healthy.exists(), isFalse);
    expect(await AppUpdateLifecycle.shouldSkipAutomatic('2.0.0'), isTrue);
    AppUpdateLifecycle.configureStartup(['--leemon-update-token', token]);
    await AppUpdateLifecycle.confirmStartup();
    expect(jsonDecode(await healthy.readAsString()), {'version': kAppVersion});
  });

  test('missing helper fails before shutdown and allows another attempt',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('leemon_update_test_');
    addTearDown(() => directory.delete(recursive: true));
    var shutdownCalled = false;
    for (var i = 0; i < 2; i++) {
      await expectLater(
          AppUpdateLifecycle.prepareZipUpdate(
            packageFile: File(path.join(directory.path, 'release.zip')),
            updaterFile: File(path.join(directory.path, 'missing.exe')),
            targetDirectory: directory.path,
            appExeName: 'Leemon.exe',
            version: '2.0.0',
            beforeShutdown: () async => shutdownCalled = true,
          ),
          throwsStateError);
    }
    expect(shutdownCalled, isFalse);
  });
}

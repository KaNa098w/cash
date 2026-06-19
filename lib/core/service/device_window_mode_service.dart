import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const deviceWindowModePrefsKey = 'device_window_mode';

enum DeviceWindowMode {
  monoblock,
  laptop;

  String get value => switch (this) {
        DeviceWindowMode.monoblock => 'monoblock',
        DeviceWindowMode.laptop => 'laptop',
      };

  static DeviceWindowMode? fromValue(String? raw) {
    return switch ((raw ?? '').trim()) {
      'monoblock' => DeviceWindowMode.monoblock,
      'laptop' => DeviceWindowMode.laptop,
      _ => null,
    };
  }
}

class DeviceWindowModeService {
  const DeviceWindowModeService._();

  static Future<DeviceWindowMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DeviceWindowMode.fromValue(
        prefs.getString(deviceWindowModePrefsKey));
  }

  static Future<void> save(DeviceWindowMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(deviceWindowModePrefsKey, mode.value);
  }

  static Future<void> apply(DeviceWindowMode mode) async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    await windowManager.setMinimizable(true);

    switch (mode) {
      case DeviceWindowMode.monoblock:
        await windowManager.setResizable(false);
        await windowManager.setMaximizable(false);
        if (!Platform.isMacOS && !await windowManager.isFullScreen()) {
          await windowManager
              .setFullScreen(true)
              .timeout(const Duration(seconds: 2));
        }
        break;
      case DeviceWindowMode.laptop:
        if (!Platform.isMacOS && await windowManager.isFullScreen()) {
          await windowManager
              .setFullScreen(false)
              .timeout(const Duration(seconds: 2));
        }
        await windowManager.setMinimumSize(const Size(900, 650));
        await windowManager.setSize(const Size(1200, 800));
        await windowManager.center();
        await windowManager.setResizable(true);
        await windowManager.setMaximizable(true);
        break;
    }
  }
}

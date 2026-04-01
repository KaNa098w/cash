import 'package:leemon_app/core/service/app_build_info.dart';

/// Текущая версия приложения.
/// Берется из единого источника, чтобы экран обновления и сборка не расходились.
const String kAppVersion = AppBuildInfo.appVersion;

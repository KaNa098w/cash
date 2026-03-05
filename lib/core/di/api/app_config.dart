// lib/core/app_config.dart

enum AppEnvironment { dev, prod }

class AppConfig {
  AppConfig._internal({
    required this.baseUrl,
    required this.environment,
  });

  static late AppConfig _instance;

  /// Текущий инстанс конфига
  static AppConfig get I => _instance;

  /// Инициализация в main()
  static void init({AppEnvironment env = AppEnvironment.dev}) {
    switch (env) {
      case AppEnvironment.dev:
        _instance = AppConfig._internal(
          baseUrl: 'https://stage.leemon.kz/api',
          environment: env,
        );
        break;
      case AppEnvironment.prod:
        _instance = AppConfig._internal(
          baseUrl:
              'https://leemon.kz/api', // потом поменяешь, если будет другой
          environment: env,
        );
        break;
    }
  }

  final String baseUrl;
  final AppEnvironment environment;

  bool get isDev => environment == AppEnvironment.dev;
  bool get isProd => environment == AppEnvironment.prod;
}

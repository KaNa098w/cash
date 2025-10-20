abstract class AuthRepository {
  /// Возвращает accessToken при успехе
  Future<String> signIn({required String login, required String password});

  /// Простейший in-memory флаг (для демо)
  bool get isAuthorized;
  void clear();
}

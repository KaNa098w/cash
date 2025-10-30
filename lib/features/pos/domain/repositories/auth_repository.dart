import 'dart:async';
import 'package:pos_desktop_clean/features/pos/data/repositories/auth_repository.dart';

import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  String? _token;

  @override
  Future<String> signIn(
      {required String login, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // демо-логика
    if (login.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('Введите логин и пароль');
    }
    if (password.length < 4) throw Exception('Слишком короткий пароль');
    _token = 'demo_token_${DateTime.now().millisecondsSinceEpoch}';
    return _token!;
  }

  @override
  bool get isAuthorized => _token != null;

  @override
  void clear() => _token = null;
}

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:pos_desktop_clean/features/pos/data/repositories/auth_repository.dart';
import '../../domain/repositories/auth_repository.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}
final class AuthInitial extends AuthState {}
final class AuthLoading extends AuthState {}
final class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message);
  @override
  List<Object?> get props => [message];
}
final class AuthAuthenticated extends AuthState {
  final String token;
  const AuthAuthenticated(this.token);
  @override
  List<Object?> get props => [token];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repo) : super(AuthInitial());
  final AuthRepository _repo;

  Future<void> signIn(String login, String password, {bool rememberMe = false}) async {
    emit(AuthLoading());
    try {
      final token = await _repo.signIn(login: login, password: password);
      emit(AuthAuthenticated(token));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceFirst('Exception: ', '')));
    }
  }

  void signOut() {
    _repo.clear();
    emit(AuthInitial());
  }
}

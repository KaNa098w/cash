import 'package:equatable/equatable.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthProvisioned extends AuthState {
  final PosProvisionResponse provision;
  const AuthProvisioned(this.provision);

  @override
  List<Object?> get props => [provision];
}

class AuthPinStep extends AuthState {
  final PosProvisionResponse provision;
  final PosUser user;
  final String? errorText;

  const AuthPinStep({
    required this.provision,
    required this.user,
    this.errorText,
  });

  @override
  List<Object?> get props => [provision, user, errorText];
}

class AuthOpeningCashStep extends AuthState {
  final PosProvisionResponse provision;
  final PosUser user;

  const AuthOpeningCashStep({
    required this.provision,
    required this.user,
  });

  @override
  List<Object?> get props => [provision, user];
}

class AuthOpeningSession extends AuthState {
  final PosProvisionResponse provision;
  final PosUser user;
  final num openingCashAmount;

  const AuthOpeningSession({
    required this.provision,
    required this.user,
    required this.openingCashAmount,
  });

  @override
  List<Object?> get props => [provision, user, openingCashAmount];
}

class AuthClosingSession extends AuthState {
  final num closingCashAmount;

  const AuthClosingSession({
    required this.closingCashAmount,
  });

  @override
  List<Object?> get props => [closingCashAmount];
}

class AuthSuccess extends AuthState {
  const AuthSuccess();
}

/// ✅ событие: смена успешно закрыта (для шторки)
class AuthShiftClosed extends AuthState {
  const AuthShiftClosed();
}

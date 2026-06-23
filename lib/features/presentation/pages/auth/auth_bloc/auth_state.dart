import 'package:equatable/equatable.dart';
import 'package:leemon_app/core/models/pos_pricing_plan_status.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';

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

  const AuthOpeningSession({
    required this.provision,
    required this.user,
  });

  @override
  List<Object?> get props => [provision, user];
}

class AuthPricingBlocked extends AuthState {
  final PosProvisionResponse provision;
  final PosUser user;
  final PosPricingPlanStatus status;

  const AuthPricingBlocked({
    required this.provision,
    required this.user,
    required this.status,
  });

  @override
  List<Object?> get props => [provision, user, status];
}

/// ✅ Смена уже открыта, просто разблокировали кассира (без открытия смены)
class AuthUnlocked extends AuthState {
  final PosProvisionResponse provision;
  final PosUser user;

  const AuthUnlocked({required this.provision, required this.user});

  @override
  List<Object?> get props => [provision, user];
}

class AuthClosingSession extends AuthState {
  final num closingCashAmount;
  final String title;
  final String message;

  const AuthClosingSession({
    required this.closingCashAmount,
    required this.title,
    required this.message,
  });

  @override
  List<Object?> get props => [closingCashAmount, title, message];
}

/// ✅ “Готово к входу в POS” (после успешного открытия смены)
class AuthSuccess extends AuthState {
  const AuthSuccess();
}

/// ✅ событие: смена успешно закрыта (для шторки)
class AuthShiftClosed extends AuthState {
  const AuthShiftClosed();
}

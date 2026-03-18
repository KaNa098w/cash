import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/domain/repositories/auth_repository.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';

import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required AuthRepository authRepository,
    required SessionRepository sessionRepository,
    required AuthTokenProvider tokenProvider,
  })  : _authRepository = authRepository,
        _sessionRepository = sessionRepository,
        _tokenProvider = tokenProvider,
        super(_resolveInitialState(tokenProvider));

  final AuthRepository _authRepository;
  final SessionRepository _sessionRepository;
  final AuthTokenProvider _tokenProvider;

  static AuthState _resolveInitialState(AuthTokenProvider tokenProvider) {
    final cached = tokenProvider.cachedProvision;
    if (cached != null) return AuthProvisioned(cached);
    return const AuthInitial();
  }

  void bootstrapFromCache() {
    final cached = _tokenProvider.cachedProvision;
    if (cached == null) return;
    emit(AuthProvisioned(cached));
  }

  Future<void> lockToCashiers() async {
    final cached = _tokenProvider.cachedProvision;
    final activeUserId = _tokenProvider.activeUserId?.trim() ?? '';

    await _tokenProvider.clearActiveUserId();

    if (cached != null) {
      final lockedUsers = activeUserId.isEmpty
          ? cached.users
          : cached.users.where((user) => user.id == activeUserId).toList();

      emit(AuthProvisioned(
        PosProvisionResponse(
          id: cached.id,
          name: cached.name,
          key: cached.key,
          accountId: cached.accountId,
          storeId: cached.storeId,
          storeName: cached.storeName,
          organizationId: cached.organizationId,
          users: lockedUsers.isNotEmpty ? lockedUsers : cached.users,
          createdAt: cached.createdAt,
          updatedAt: cached.updatedAt,
        ),
      ));
    } else {
      emit(const AuthInitial());
    }
  }

  Future<void> provisionByKey(String key) async {
    emit(const AuthLoading());
    try {
      final cleanKey = key.trim();
      if (cleanKey.isEmpty) throw Exception('Ключ пустой');

      await _tokenProvider.setPosKey(cleanKey);

      var deviceId = _tokenProvider.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        await _tokenProvider.init();
        deviceId = _tokenProvider.deviceId;
      }
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('deviceId отсутствует');
      }

      final resp = await _authRepository.provisionPos(
        key: cleanKey,
        deviceId: deviceId,
      );

      await _tokenProvider.setProvisioned(resp);
      emit(AuthProvisioned(resp));
    } on DioException catch (e) {
      emit(AuthFailure('Dio ${e.response?.statusCode}: ${e.response?.data}'));
      emit(const AuthInitial());
    } catch (e) {
      emit(AuthFailure('Ошибка подключения кассы: $e'));
      emit(const AuthInitial());
    }
  }

  void selectUser(PosProvisionResponse provision, PosUser user) {
    emit(AuthPinStep(provision: provision, user: user));
  }

  void backToUsers(PosProvisionResponse provision) {
    emit(AuthProvisioned(provision));
  }

  Future<void> verifyPin({
    required PosProvisionResponse provision,
    required PosUser user,
    required String inputPin,
  }) async {
    final pin = inputPin.trim();
    if (pin.isEmpty) {
      emit(AuthPinStep(
        provision: provision,
        user: user,
        errorText: 'Введите PIN',
      ));
      return;
    }

    final expectedHash = user.pinHash;

    var ok = false;
    if (expectedHash != null && expectedHash.isNotEmpty) {
      final actualHash = _tokenProvider.hashPin(pin);
      ok = actualHash == expectedHash;
    } else {
      ok = user.pinCode.isNotEmpty && pin == user.pinCode;
    }

    if (!ok) {
      emit(AuthPinStep(
        provision: provision,
        user: user,
        errorText: 'Неверный PIN',
      ));
      return;
    }

    await _tokenProvider.setActiveUserId(user.id);
    await _tokenProvider.setActiveUserName(user.name);

    if (_tokenProvider.hasShiftId) {
      emit(AuthUnlocked(provision: provision, user: user));
      return;
    }

    emit(AuthOpeningCashStep(provision: provision, user: user));
  }

  Future<void> openSessionWithCash({
    required PosProvisionResponse provision,
    required PosUser user,
  }) async {
    try {
      emit(AuthOpeningSession(
        provision: provision,
        user: user,
      ));

      final key = _tokenProvider.posKey?.trim() ?? '';
      if (key.isEmpty) throw Exception('posKey пустой');

      final deviceId = _tokenProvider.deviceId?.trim() ?? '';
      if (deviceId.isEmpty) throw Exception('deviceId отсутствует');

      final sessionId = await _sessionRepository.openSession(
        key: key,
        deviceId: deviceId,
        userId: user.id,
      );

      await _tokenProvider.setShiftId(sessionId);
      await _tokenProvider.setActiveUserId(user.id);

      emit(const AuthSuccess());
    } on DioException catch (e) {
      emit(AuthFailure(
        'Не удалось открыть смену: Dio ${e.response?.statusCode}: ${e.response?.data}',
      ));
      emit(AuthOpeningCashStep(provision: provision, user: user));
    } catch (e) {
      emit(AuthFailure('Не удалось открыть смену: $e'));
      emit(AuthOpeningCashStep(provision: provision, user: user));
    }
  }

  Future<void> closeSessionWithCash({
    required num closingCashAmount,
  }) async {
    try {
      final key = _tokenProvider.posKey?.trim() ?? '';
      if (key.isEmpty) throw Exception('posKey пустой');

      final deviceId = _tokenProvider.deviceId?.trim() ?? '';
      if (deviceId.isEmpty) throw Exception('deviceId отсутствует');

      final sessionId = _tokenProvider.shiftId?.trim() ?? '';
      if (sessionId.isEmpty) {
        throw Exception('sessionId отсутствует: нечего закрывать');
      }

      final userId = _tokenProvider.activeUserId?.trim() ?? '';
      if (userId.isEmpty) {
        throw Exception('activeUserId отсутствует: не определен кассир');
      }

      emit(AuthClosingSession(closingCashAmount: closingCashAmount));

      await _sessionRepository.closeSession(
        key: key,
        deviceId: deviceId,
        sessionId: sessionId,
        userId: userId,
        closingCashAmount: closingCashAmount,
      );

      await _tokenProvider.clearShiftId();
      await _tokenProvider.clearActiveUserId();

      emit(const AuthShiftClosed());

      final cached = _tokenProvider.cachedProvision;
      if (cached != null) {
        emit(AuthProvisioned(cached));
      } else {
        emit(const AuthInitial());
      }
    } catch (e) {
      emit(AuthFailure('Не удалось закрыть смену: $e'));
    }
  }

  Future<void> resetAll() async {
    await _tokenProvider.clearPosKey();
    emit(const AuthInitial());
  }
}

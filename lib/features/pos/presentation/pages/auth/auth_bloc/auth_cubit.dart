import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';

import 'package:pos_desktop_clean/features/pos/domain/repositories/auth_repository.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/session_repository.dart';

import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required AuthRepository authRepository,
    required SessionRepository sessionRepository,
    required AuthTokenProvider tokenProvider,
  })  : _authRepository = authRepository,
        _sessionRepository = sessionRepository,
        _tokenProvider = tokenProvider,
        super(const AuthInitial());

  final AuthRepository _authRepository;
  final SessionRepository _sessionRepository;
  final AuthTokenProvider _tokenProvider;

  void bootstrapFromCache() {
    final cached = _tokenProvider.cachedProvision;
    if (cached == null) return;
    emit(AuthProvisioned(cached));
  }

  void lockToCashiers() {
    final cached = _tokenProvider.cachedProvision;
    if (cached != null) {
      emit(AuthProvisioned(cached));
      return;
    }
    emit(const AuthInitial());
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

  void verifyPin({
    required PosProvisionResponse provision,
    required PosUser user,
    required String inputPin,
  }) {
    final pin = inputPin.trim();
    if (pin.isEmpty) {
      emit(AuthPinStep(provision: provision, user: user, errorText: 'Введите PIN'));
      return;
    }

    final expectedHash = user.pinHash;

    bool ok = false;
    if (expectedHash != null && expectedHash.isNotEmpty) {
      final actualHash = _tokenProvider.hashPin(pin);
      ok = actualHash == expectedHash;
    } else {
      ok = user.pinCode.isNotEmpty && pin == user.pinCode;
    }

    if (!ok) {
      emit(AuthPinStep(provision: provision, user: user, errorText: 'Неверный PIN'));
      return;
    }

    // ✅ запоминаем активного кассира
    _tokenProvider.setActiveUserId(user.id.toString());

    emit(AuthOpeningCashStep(provision: provision, user: user));
  }

  Future<void> openSessionWithCash({
    required PosProvisionResponse provision,
    required PosUser user,
    required num openingCashAmount,
  }) async {
    try {
      emit(AuthOpeningSession(
        provision: provision,
        user: user,
        openingCashAmount: openingCashAmount,
      ));

      final key = _tokenProvider.posKey?.trim() ?? '';
      if (key.isEmpty) throw Exception('posKey пустой');

      // ✅ sessionId вернулся — сохраняем
      final sessionId = await _session_repositoryOpen(
        key: key,
        userId: user.id.toString(),
        openingCashAmount: openingCashAmount,
      );

      await _tokenProvider.setShiftId(sessionId);
      await _tokenProvider.setActiveUserId(user.id.toString());

      emit(const AuthSuccess());
    } on DioException catch (e) {
      emit(AuthFailure('Не удалось открыть смену: Dio ${e.response?.statusCode}: ${e.response?.data}'));
      emit(AuthOpeningCashStep(provision: provision, user: user));
    } catch (e) {
      emit(AuthFailure('Не удалось открыть смену: $e'));
      emit(AuthOpeningCashStep(provision: provision, user: user));
    }
  }

  // чтобы не путаться с именами — отдельный приватный вызов
  Future<String> _session_repositoryOpen({
    required String key,
    required String userId,
    required num openingCashAmount,
  }) async {
    return _sessionRepository.openSession(
      key: key,
      userId: userId,
      openingCashAmount: openingCashAmount,
    );
  }

  /// ✅ закрытие смены: берём shiftId + activeUserId из provider
  Future<void> closeSessionWithCash({
    required num closingCashAmount,
  }) async {
    try {
      final key = _tokenProvider.posKey?.trim() ?? '';
      if (key.isEmpty) throw Exception('posKey пустой');

      final sessionId = _tokenProvider.shiftId?.trim() ?? '';
      if (sessionId.isEmpty) throw Exception('sessionId отсутствует: нечего закрывать');

      final userId = _tokenProvider.activeUserId?.trim() ?? '';
      if (userId.isEmpty) throw Exception('activeUserId отсутствует: не определён кассир');

      emit(AuthClosingSession(closingCashAmount: closingCashAmount));

      await _sessionRepository.closeSession(
        key: key,
        sessionId: sessionId,
        userId: userId,
        closingCashAmount: closingCashAmount,
      );

      // ✅ после успеха — очистка
      await _tokenProvider.clearShiftId();
      await _tokenProvider.clearActiveUserId();

      emit(const AuthShiftClosed());
    } catch (e) {
      emit(AuthFailure('Не удалось закрыть смену: $e'));
    }
  }

  Future<void> resetAll() async {
    await _tokenProvider.clearPosKey();
    emit(const AuthInitial());
  }
}

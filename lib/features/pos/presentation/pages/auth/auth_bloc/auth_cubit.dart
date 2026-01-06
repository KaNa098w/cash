import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/auth_repository.dart';

import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required AuthRepository authRepository,
    required AuthTokenProvider tokenProvider,
  })  : _authRepository = authRepository,
        _tokenProvider = tokenProvider,
        super(const AuthInitial());

  final AuthRepository _authRepository;
  final AuthTokenProvider _tokenProvider;

  // STEP 1: key -> provision
  Future<void> provisionByKey(String key) async {
    emit(const AuthLoading());
    try {
      final cleanKey = key.trim();
      if (cleanKey.isEmpty) throw Exception('Ключ пустой');

      // posKey запомним
      await _tokenProvider.setPosKey(cleanKey);

      // deviceId обязателен
      var deviceId = _tokenProvider.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        await _tokenProvider.init(); // страховка
        deviceId = _tokenProvider.deviceId;
      }
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('deviceId отсутствует');
      }

      final resp = await _authRepository.provisionPos(
        key: cleanKey,
        deviceId: deviceId,
      );

      // сохраняем в кэш (posName/accountId/storeId/orgId/users)
      await _tokenProvider.setProvisioned(resp);

      // показываем список пользователей
      emit(AuthProvisioned(resp));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      emit(AuthFailure('Dio $status: $data'));
      emit(const AuthInitial());
    } catch (e) {
      emit(AuthFailure('Ошибка подключения кассы: $e'));
      emit(const AuthInitial());
    }
  }

  // STEP 2: choose user -> pin step
  void selectUser(PosProvisionResponse provision, PosUser user) {
    emit(AuthPinStep(provision: provision, user: user));
  }

  // STEP 3: verify pin
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

    if (pin == user.pinCode) {
      emit(const AuthSuccess());
      return;
    }

    emit(AuthPinStep(
      provision: provision,
      user: user,
      errorText: 'Неверный PIN',
    ));
  }

  // Back from pin to users list
  void backToUsers(PosProvisionResponse provision) {
    emit(AuthProvisioned(provision));
  }

  // Change key / reset
  Future<void> resetAll() async {
    await _tokenProvider.clearPosKey();
    emit(const AuthInitial());
  }
}

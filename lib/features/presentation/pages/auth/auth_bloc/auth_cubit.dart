import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdf/pdf.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
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

  Future<bool> _hasInternet() async {
    if (kIsWeb) return true;
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(milliseconds: 900));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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

      emit(
        AuthProvisioned(
          PosProvisionResponse(
            id: cached.id,
            name: cached.name,
            number: cached.number,
            key: cached.key,
            accountId: cached.accountId,
            storeId: cached.storeId,
            storeName: cached.storeName,
            organizationId: cached.organizationId,
            users: lockedUsers.isNotEmpty ? lockedUsers : cached.users,
            createdAt: cached.createdAt,
            updatedAt: cached.updatedAt,
          ),
        ),
      );
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
      emit(
        AuthPinStep(
          provision: provision,
          user: user,
          errorText: 'Введите PIN',
        ),
      );
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
      emit(
        AuthPinStep(
          provision: provision,
          user: user,
          errorText: 'Неверный PIN',
        ),
      );
      return;
    }

    await _tokenProvider.setActiveUserId(user.id);
    await _tokenProvider.setActiveUserName(user.name);
    await sl<PosSyncService>().ensureLocalSaleCounterSynced();

    if (_tokenProvider.hasShiftId) {
      emit(AuthUnlocked(provision: provision, user: user));
      return;
    }

    await openSessionWithCash(
      provision: provision,
      user: user,
    );
  }

  Future<void> openSessionWithCash({
    required PosProvisionResponse provision,
    required PosUser user,
  }) async {
    try {
      emit(
        AuthOpeningSession(
          provision: provision,
          user: user,
        ),
      );

      final key = _tokenProvider.posKey?.trim() ?? '';
      if (key.isEmpty) throw Exception('posKey пустой');

      final deviceId = _tokenProvider.deviceId?.trim() ?? '';
      if (deviceId.isEmpty) throw Exception('deviceId отсутствует');

      final sessionId = await _sessionRepository.openSession(
        key: key,
        deviceId: deviceId,
        userId: user.id,
      );
      debugPrint(
        '[AuthCubit] openSession completed: returned sessionId=$sessionId for userId=${user.id}',
      );

      await _tokenProvider.setShiftId(sessionId);
      await _tokenProvider.setActiveUserId(user.id);

      emit(const AuthSuccess());
    } on DioException catch (e) {
      emit(
        AuthFailure(
          'Не удалось открыть смену: Dio ${e.response?.statusCode}: ${e.response?.data}',
        ),
      );
      emit(AuthPinStep(provision: provision, user: user));
    } catch (e) {
      emit(AuthFailure('Не удалось открыть смену: $e'));
      emit(AuthPinStep(provision: provision, user: user));
    }
  }

  Future<void> closeSessionWithCash({
    required num closingCashAmount,
  }) async {
    try {
      final hasInternet = await _hasInternet();
      if (!hasInternet) {
        throw Exception(
          'Закрыть смену без интернета нельзя. Подключите интернет и попробуйте снова.',
        );
      }

      final key = _tokenProvider.posKey?.trim() ?? '';
      if (key.isEmpty) throw Exception('posKey пустой');

      final deviceId = _tokenProvider.deviceId?.trim() ?? '';
      if (deviceId.isEmpty) throw Exception('deviceId отсутствует');

      final sessionId = _tokenProvider.shiftId?.trim() ?? '';
      if (sessionId.isEmpty) {
        throw Exception('sessionId отсутствует: нечего закрывать');
      }

      final userId = _tokenProvider.activeUserId?.trim() ?? '';
      final cashierName = _tokenProvider.activeUserName?.trim() ?? userId;
      final storeName = (_tokenProvider.storeName ?? '').trim().isEmpty
          ? ((_tokenProvider.posName ?? '').trim().isEmpty
              ? 'Магазин'
              : _tokenProvider.posName!.trim())
          : _tokenProvider.storeName!.trim();
      final posName = (_tokenProvider.posName ?? '').trim().isEmpty
          ? 'POS'
          : _tokenProvider.posName!.trim();
      if (userId.isEmpty) {
        throw Exception('activeUserId отсутствует: не определен кассир');
      }

      emit(
        AuthClosingSession(
          closingCashAmount: closingCashAmount,
          title: 'Закрываем смену',
          message: 'Отправляем данные и фиксируем итог по кассе.',
        ),
      );

      final closeResult = await _sessionRepository.closeSession(
        key: key,
        deviceId: deviceId,
        sessionId: sessionId,
        userId: userId,
        closingCashAmount: closingCashAmount,
      );

      if (closeResult == QueueSendResult.sent) {
        emit(
          AuthClosingSession(
            closingCashAmount: closingCashAmount,
            title: 'Готовим Z-отчёт',
            message: 'Собираем продажи смены и считаем итоговые суммы.',
          ),
        );
        final report = await sl<PosSyncService>().loadShiftReport(sessionId);
        if (report != null) {
          emit(
            AuthClosingSession(
              closingCashAmount: closingCashAmount,
              title: 'Печатаем Z-отчёт',
              message: 'Отправляем чек закрытия смены на принтер.',
            ),
          );
          final pageFormat = _tokenProvider.receiptPaperMm == 57
              ? PdfPageFormat.roll57
              : PdfPageFormat.roll80;
          final printer = PrintService();
          await printer.print80mmSilently(
            () => buildShiftReportPdf(
              ShiftReportPdfData(
                pageFormat: pageFormat,
                money: money,
                storeName: storeName,
                posName: posName,
                cashierName: cashierName,
                sessionId: report.sessionId,
                openedAt: report.openedAt,
                closedAt: report.closedAt,
                openingCashAmount: report.openingCashAmount,
                closingCashAmount: report.closingCashAmount,
                salesCount: report.salesCount,
                cashTotal: report.cashTotal,
                cardTotal: report.cardTotal,
                transferTotal: report.transferTotal,
                creditTotal: report.creditTotal,
                grandTotal: report.grandTotal,
                refundsTotal: report.refundsTotal,
                incomeTotal: report.incomeTotal,
                expenseTotal: report.expenseTotal,
                expectedCashAmount: report.expectedCashAmount,
                items: report.items
                    .map(
                      (item) => ReceiptPdfItem(
                        name: item.name,
                        quantity: item.quantity,
                        unitPrice: 0,
                        lineTotal: item.totalSum,
                      ),
                    )
                    .toList(),
              ),
            ),
            format: pageFormat,
            printerName: _tokenProvider.receiptPrinterName,
          );
        }
      }

      emit(
        AuthClosingSession(
          closingCashAmount: closingCashAmount,
          title: 'Завершаем',
          message: 'Очищаем активную смену и возвращаем на экран входа.',
        ),
      );

      await _tokenProvider.clearShiftId();
      await _tokenProvider.clearActiveUserId();

      emit(const AuthShiftClosed());

      try {
        final refreshedProvision = await _authRepository.provisionPos(
          key: key,
          deviceId: deviceId,
        );
        await _tokenProvider.setProvisioned(refreshedProvision);
        emit(AuthProvisioned(refreshedProvision));
      } catch (_) {
        final cached = _tokenProvider.cachedProvision;
        if (cached != null) {
          emit(AuthProvisioned(cached));
        } else {
          emit(const AuthInitial());
        }
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

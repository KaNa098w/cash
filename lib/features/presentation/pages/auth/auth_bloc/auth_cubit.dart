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

  static bool _sessionOpenInProgress = false;

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
    if (cached != null) {
      return AuthProvisioned(tokenProvider.provisionForOpenShift(cached));
    }
    return const AuthInitial();
  }

  void bootstrapFromCache() {
    final cached = _tokenProvider.cachedProvision;
    if (cached == null) return;
    emit(AuthProvisioned(_tokenProvider.provisionForOpenShift(cached)));
  }

  Future<void> lockToCashiers() async {
    final cached = _tokenProvider.cachedProvision;
    final activeUserId = _tokenProvider.activeUserId?.trim() ?? '';
    final shiftUserId = (_tokenProvider.shiftUserId?.trim().isNotEmpty == true)
        ? _tokenProvider.shiftUserId!.trim()
        : activeUserId;
    if (_tokenProvider.hasShiftId && shiftUserId.isNotEmpty) {
      await _tokenProvider.setShiftUserId(shiftUserId);
    }

    await _tokenProvider.clearActiveUserId();

    if (cached != null) {
      emit(
        AuthProvisioned(_tokenProvider.provisionForOpenShift(cached)),
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
      emit(AuthProvisioned(_tokenProvider.provisionForOpenShift(resp)));
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
          errorText: 'Неверный PIN-код',
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
          errorText: 'Неверный PIN-код',
        ),
      );
      return;
    }

    final pricingPlanAllowsAccess = await _ensurePricingPlanAllowsAccess(
      provision: provision,
      user: user,
    );
    if (!pricingPlanAllowsAccess) return;

    await _tokenProvider.setActiveUserId(user.id);
    await _tokenProvider.setActiveUserName(user.name);
    await sl<PosSyncService>().ensureLocalSaleCounterSynced();

    if (_tokenProvider.hasShiftId) {
      final shiftUserId = _tokenProvider.shiftUserId?.trim() ?? '';
      if (shiftUserId.isNotEmpty && shiftUserId != user.id) {
        emit(
          AuthPinStep(
            provision: provision,
            user: user,
            errorText: 'Этот кассир не открывал текущую смену',
          ),
        );
        return;
      }
      emit(AuthUnlocked(provision: provision, user: user));
      return;
    }

    await openSessionWithCash(
      provision: provision,
      user: user,
    );
  }

  Future<bool> _ensurePricingPlanAllowsAccess({
    required PosProvisionResponse provision,
    required PosUser user,
  }) async {
    final key = _tokenProvider.posKey?.trim() ?? '';
    var status = _tokenProvider.pricingPlanStatus;

    if (key.isNotEmpty) {
      try {
        status = await sl<PosSyncService>().loadPricingPlan(key: key);
        await _tokenProvider.setPricingPlanStatus(status);
      } catch (error) {
        debugPrint('[AuthCubit] pricing-plan check failed: $error');
      }
    }

    if (status == null || !status.isAccessBlocked()) return true;

    emit(
      AuthPricingBlocked(
        provision: provision,
        user: user,
        status: status,
      ),
    );
    return false;
  }

  Future<void> openSessionWithCash({
    required PosProvisionResponse provision,
    required PosUser user,
  }) async {
    if (_sessionOpenInProgress) {
      debugPrint(
        '[AuthCubit] openSession skipped: another open-session request is already in progress',
      );
      return;
    }

    if (await _unlockIfShiftAlreadyOpen(provision: provision, user: user)) {
      return;
    }

    _sessionOpenInProgress = true;
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

      if (await _unlockIfShiftAlreadyOpen(provision: provision, user: user)) {
        return;
      }

      final sessionId = await _sessionRepository.openSession(
        key: key,
        deviceId: deviceId,
        userId: user.id,
      );
      debugPrint(
        '[AuthCubit] openSession completed: returned sessionId=$sessionId for userId=${user.id}',
      );

      await _tokenProvider.setShiftId(sessionId);
      await _tokenProvider.setShiftUserId(user.id);
      await _tokenProvider.setActiveUserId(user.id);
      await _tokenProvider.setActiveUserName(user.name);

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
    } finally {
      _sessionOpenInProgress = false;
    }
  }

  Future<bool> _unlockIfShiftAlreadyOpen({
    required PosProvisionResponse provision,
    required PosUser user,
  }) async {
    final shiftId = _tokenProvider.shiftId?.trim() ?? '';
    if (shiftId.isEmpty) return false;

    final shiftUserId = _tokenProvider.shiftUserId?.trim() ?? '';
    if (shiftUserId.isNotEmpty && shiftUserId != user.id) {
      emit(
        AuthPinStep(
          provision: provision,
          user: user,
          errorText: 'Этот кассир не открывал текущую смену',
        ),
      );
      return true;
    }

    if (shiftUserId.isEmpty) {
      await _tokenProvider.setShiftUserId(user.id);
    }
    await _tokenProvider.setActiveUserId(user.id);
    await _tokenProvider.setActiveUserName(user.name);

    debugPrint(
      '[AuthCubit] openSession skipped: active shift already exists shiftId=$shiftId userId=${user.id}',
    );
    emit(AuthUnlocked(provision: provision, user: user));
    return true;
  }

  Future<void> closeSessionWithCash({
    required num closingCashAmount,
    String? comment,
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
          title: 'Синхронизируем очередь',
          message: 'Отправляем продажи, возвраты и операции кассы.',
        ),
      );

      final sync = sl<PosSyncService>();
      await sync.pushPending(key: key, deviceId: deviceId, limit: 1000);
      final queueItems = await sync.loadQueueItems();
      if (queueItems.isNotEmpty) {
        throw Exception(
          'В очереди осталось ${queueItems.length} операций. Выполните синхронизацию и попробуйте снова.',
        );
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
        comment: comment,
      );

      if (closeResult == QueueSendResult.sent) {
        emit(
          AuthClosingSession(
            closingCashAmount: closingCashAmount,
            title: 'Готовим Z-отчёт',
            message: 'Собираем продажи смены и считаем итоговые суммы.',
          ),
        );
        ShiftReportData? report;
        try {
          report = await sync.loadShiftReportFromBackend(
            key: key,
            sessionId: sessionId,
            deviceId: deviceId,
            includeProducts: false,
          );
        } catch (_) {
          report = await sync.loadShiftReport(sessionId);
        }
        final printableReport = report;
        if (printableReport != null) {
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
                sessionId: printableReport.sessionId,
                openedAt: printableReport.openedAt,
                closedAt: printableReport.closedAt,
                openingCashAmount: printableReport.openingCashAmount,
                closingCashAmount: closingCashAmount,
                salesCount: printableReport.salesCount,
                cashTotal: printableReport.cashTotal,
                cardTotal: printableReport.cardTotal,
                transferTotal: printableReport.transferTotal,
                creditTotal: printableReport.creditTotal,
                grandTotal: printableReport.grandTotal,
                refundsTotal: printableReport.refundsTotal,
                incomeTotal: printableReport.incomeTotal,
                expenseTotal: printableReport.expenseTotal,
                expectedCashAmount: printableReport.expectedCashAmount,
                items: printableReport.items
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
      await _tokenProvider.setActiveUserId(userId);
      await _tokenProvider.setActiveUserName(cashierName);
      sync.stopBackgroundLoops();

      emit(const AuthShiftClosed());

      try {
        final refreshedProvision = await _authRepository.provisionPos(
          key: key,
          deviceId: deviceId,
        );
        await _tokenProvider.setProvisioned(refreshedProvision);
        emit(AuthProvisioned(
          _tokenProvider.provisionForOpenShift(refreshedProvision),
        ));
      } catch (_) {
        final cached = _tokenProvider.cachedProvision;
        if (cached != null) {
          emit(AuthProvisioned(_tokenProvider.provisionForOpenShift(cached)));
        } else {
          emit(const AuthInitial());
        }
      }
    } catch (e) {
      emit(AuthFailure('Не удалось закрыть смену: $e'));
    }
  }

  Future<void> resetAll() async {
    sl<PosSyncService>().stopBackgroundLoops();
    await _tokenProvider.clearPosKey();
    emit(const AuthInitial());
  }
}

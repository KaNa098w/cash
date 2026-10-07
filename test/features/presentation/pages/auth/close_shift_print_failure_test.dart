import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/auth_repository.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';
import 'package:leemon_app/features/presentation/widgets/shift_print_failure_dialog.dart';

class _Auth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No provision');
}

class _Sessions implements SessionRepository {
  int closes = 0;
  @override
  Future<QueueSendResult> closeSession(
      {required String key,
      required String deviceId,
      required String sessionId,
      required String userId,
      required num closingCashAmount,
      String? comment}) async {
    closes++;
    return QueueSendResult.sent;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Sync implements PosSyncService {
  int reports = 0;
  @override
  Future<void> pushPending(
      {required String key,
      required String deviceId,
      int limit = 5,
      void Function(QueuePushEvent event)? onProgress}) async {}
  @override
  Future<List<QueueListItem>> loadQueueItems() async => [];
  @override
  Future<ShiftReportData?> loadShiftReportFromBackend(
      {required String key,
      required String sessionId,
      String? deviceId,
      bool includeProducts = true}) async {
    reports++;
    return ShiftReportData(
        sessionId: sessionId,
        openedAt: DateTime(2026),
        closedAt: null,
        openingCashAmount: 0,
        closingCashAmount: 0,
        salesCount: 0,
        cashTotal: 0,
        cardTotal: 0,
        transferTotal: 0,
        creditTotal: 0,
        grandTotal: 0,
        refundsTotal: 0,
        incomeTotal: 0,
        expenseTotal: 0,
        expectedCashAmount: 0,
        items: const []);
  }

  @override
  void stopBackgroundLoops() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoPrinter extends PrintingPlatform {
  @override
  Future<List<Printer>> listPrinters() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintingPlatform original;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'posKey': 'KEY',
      'deviceId': 'DEVICE',
      'shiftId': 'SHIFT',
      'activeUserId': 'USER',
      'activeUserName': 'Cashier'
    });
    original = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoPrinter();
  });
  tearDown(() async {
    PrintingPlatform.instance = original;
    await sl.reset();
  });

  for (final approve in [false, true]) {
    test(
        'missing printer: close confirmation $approve occurs before server close',
        () async {
      final tokens = AuthTokenProvider();
      await tokens.init();
      final sessions = _Sessions();
      final sync = _Sync();
      sl.registerSingleton<PosSyncService>(sync);
      final cubit = AuthCubit(
          authRepository: _Auth(),
          sessionRepository: sessions,
          tokenProvider: tokens,
          internetCheck: () async => true);
      final decision = Completer<bool>();
      final prompted = Completer<Object>();
      final closing = cubit.closeSessionWithCash(
          closingCashAmount: 0,
          onPrintFailure: (e) {
            prompted.complete(e);
            return decision.future;
          });
      expect(await prompted.future, isA<StateError>());
      expect(sessions.closes, 0);
      expect(tokens.shiftId, 'SHIFT');
      decision.complete(approve);
      await closing;
      expect(sessions.closes, approve ? 1 : 0);
      expect(tokens.shiftId, approve ? isNull : 'SHIFT');
      if (!approve) expect(cubit.state, isA<AuthFailure>());
      await cubit.close();
      tokens.dispose();
    });
  }
  test('approved skip closes without trying to print again', () async {
    final tokens = AuthTokenProvider();
    await tokens.init();
    final sessions = _Sessions();
    final sync = _Sync();
    sl.registerSingleton<PosSyncService>(sync);
    final cubit = AuthCubit(
        authRepository: _Auth(),
        sessionRepository: sessions,
        tokenProvider: tokens,
        internetCheck: () async => true);
    await cubit.closeSessionWithCash(
        closingCashAmount: 0, skipReportPrinting: true);
    expect(sync.reports, 0);
    expect(sessions.closes, 1);
    expect(tokens.shiftId, isNull);
    await cubit.close();
    tokens.dispose();
  });
  for (final approve in [false, true]) {
    testWidgets('failure dialog returns $approve', (tester) async {
      if (!approve) {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      bool? answer;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          answer = await showShiftPrintFailureDialog(
                              context, StateError('Принтер не найден'));
                        },
                        child: const Text('Open')),
                  ))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Всё равно закрыть смену?'), findsOneWidget);
      await tester.tap(find.text('Подробности ошибки'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Bad state: Принтер не найден'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final action =
          find.text(approve ? 'Закрыть без печати' : 'Не закрывать смену');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(answer, approve);
    });
  }
}

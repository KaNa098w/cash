import 'dart:async';

import 'package:leemon_app/core/service/app_build_info.dart';
import 'package:leemon_app/core/models/pos_pricing_plan_status.dart';
import 'package:leemon_app/core/service/pos_diagnostics_service.dart';
import 'package:uuid/uuid.dart';

import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart' show SaleModel;
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';

class PosSyncService {
  PosSyncService(this._localStore, this._remote,
      {PosDiagnosticsService? diagnostics})
      : _diagnostics = diagnostics;

  final PosSyncLocalStore _localStore;
  final PosSyncRemoteDataSource _remote;
  final PosDiagnosticsService? _diagnostics;
  final _uuid = const Uuid();

  static const int _maxRetryCount = 50;

  Timer? _pullTimer;
  Timer? _pushTimer;
  Future<void>? _bootstrapFuture;
  Future<void>? _pullFuture;
  Future<void>? _pushFuture;
  Future<QueueOperationResult>? _openSessionFuture;
  bool _backgroundLoopsActive = false;
  bool _syncCancelRequested = false;

  final _syncedController = StreamController<int>.broadcast();
  final _productsChangedController = StreamController<void>.broadcast();
  final _salesHistoryChangedController = StreamController<void>.broadcast();
  final _debtsChangedController = StreamController<void>.broadcast();

  /// Emits the number of operations successfully sent in each push batch.
  Stream<int> get onOperationsSynced => _syncedController.stream;

  /// Emits whenever pull sync applies changes that include product entities.
  Stream<void> get onProductsChanged => _productsChangedController.stream;

  /// Emits when sales/refunds change and the history UI should refresh.
  Stream<void> get onSalesHistoryChanged =>
      _salesHistoryChangedController.stream;

  Stream<void> get onDebtsChanged => _debtsChangedController.stream;

  Future<void> initialize() => _localStore.initialize();

  /// Returns true if a full bootstrap has been completed at least once.
  Future<bool> isBootstrapped(String key) async {
    await initialize();
    final state = await _localStore.loadSyncState(key);
    return state?.lastBootstrapAt != null;
  }

  Future<void> dispose() async {
    _pullTimer?.cancel();
    _pushTimer?.cancel();
    await _syncedController.close();
    await _productsChangedController.close();
    await _salesHistoryChangedController.close();
    await _debtsChangedController.close();
    await _localStore.close();
  }

  void startBackgroundLoops({
    required String key,
    required String deviceId,
  }) {
    _backgroundLoopsActive = true;
    _syncCancelRequested = false;
    _pullTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _runBackgroundPull(key: key, deviceId: deviceId),
    );
    _pushTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _runBackgroundPush(key: key, deviceId: deviceId, limit: 5),
    );
  }

  void stopBackgroundLoops() {
    _backgroundLoopsActive = false;
    _pullTimer?.cancel();
    _pushTimer?.cancel();
    _pullTimer = null;
    _pushTimer = null;
  }

  void requestCancelSync() {
    _syncCancelRequested = true;
    stopBackgroundLoops();
  }

  Future<void> clearAllLocalData() {
    return _localStore.clearAllLocalData();
  }

  Future<List<ProductModel>> loadProducts() {
    return _localStore.loadProducts();
  }

  Future<void> cacheServerProduct(ProductModel product) async {
    await initialize();
    await _localStore.upsertLocalProduct(product.toJson());
    if (!_productsChangedController.isClosed) {
      _productsChangedController.add(null);
    }
  }

  Future<ProductModel> createProduct({
    required String key,
    required String deviceId,
    required String barcode,
    required double sellingPrice,
    String? name,
    MeasurementUnit? measurementUnit,
  }) async {
    final localId = 'product_${_uuid.v7()}';
    final safeName = name?.trim() ?? '';
    final unit = measurementUnit?.apiValue ?? MeasurementUnit.pieces.apiValue;
    final payload = <String, dynamic>{
      'barcode': barcode.trim(),
      'selling_price': sellingPrice,
      'device_id': deviceId.trim(),
      if (safeName.isNotEmpty) 'name': safeName,
      'measurement_unit': unit,
    };
    final localJson = <String, dynamic>{
      ...payload,
      'id': localId,
      'name': safeName.isEmpty ? barcode.trim() : safeName,
      'quantity': 0,
      'arrival_cost': 0,
      'wholesale_price': 0,
      'price_after_discount': sellingPrice,
    };

    await initialize();
    await _localStore.upsertLocalProduct(localJson);
    await _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.productCreate,
      clientId: localId,
      payload: payload,
      tryImmediateSend: false,
    );
    if (!_productsChangedController.isClosed) {
      _productsChangedController.add(null);
    }
    return ProductModel.fromJson(localJson);
  }

  Future<List<Map<String, dynamic>>> loadProductsRaw() {
    return _localStore.loadProductsRaw();
  }

  Future<Map<String, dynamic>> loadDiagnosticsState(String key) async {
    await initialize();
    final state = await _localStore.loadSyncState(key);
    return {
      'sync_state': state == null
          ? null
          : {
              'pos_key': state.posKey,
              'device_id': state.deviceId,
              'cursor': state.cursor,
              'last_bootstrap_at': state.lastBootstrapAt?.toIso8601String(),
              'last_pull_at': state.lastPullAt?.toIso8601String(),
              'last_push_at': state.lastPushAt?.toIso8601String(),
              'last_error': state.lastError,
            },
    };
  }

  Future<List<ProductModel>> loadFavoriteProducts() {
    return _localStore.loadFavoriteProducts();
  }

  Future<List<LocalExpenseType>> loadExpenseTypes() {
    return _localStore.loadExpenseTypes();
  }

  Future<List<LocalAccount>> loadAccounts() {
    return _localStore.loadAccounts();
  }

  Future<List<LocalAccount>> loadAccountsFromBackend({
    required String key,
  }) async {
    final accounts = await _remote.fetchAllAccounts(key: key);
    return accounts
        .map(
          (account) => LocalAccount(
            id: _stringFromMap(account, 'id'),
            name: _stringFromMap(account, 'name'),
            type: _stringFromMap(account, 'type'),
            logoUrl: _nullableStringFromMap(account, 'logo_url') ??
                _nullableStringFromMap(account, 'logoUrl'),
            visibleToPos: _boolFromMap(
              account,
              'visible_to_pos',
              fallback: true,
            ),
          ),
        )
        .where((account) => account.id.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<LocalCustomer>> loadCustomers() {
    return _localStore.loadCustomers();
  }

  Future<Map<String, dynamic>> refreshPosInfo({required String key}) async {
    await initialize();
    final posInfo = await _remote.fetchPosInfo(key: key);
    await _localStore.upsertPosInfo(posInfo);
    return posInfo;
  }

  Future<PosPricingPlanStatus> loadPricingPlan({
    required String key,
  }) async {
    final data = await _remote.fetchPricingPlan(key: key);
    return PosPricingPlanStatus.fromDataJson(data);
  }

  Future<void> upsertCustomersRaw(List<Map<String, dynamic>> customers) async {
    await _localStore.upsertCustomersRaw(customers);
    _notifyDebtsChanged();
  }

  Future<List<SaleModel>> loadPendingSales() {
    return _localStore.loadPendingSales();
  }

  Future<List<QueueListItem>> loadQueueItems() {
    return _localStore.loadQueueItems();
  }

  Future<QueueItemDetails?> loadQueueItemDetails(String operationId) {
    return _localStore.loadQueueItemDetails(operationId);
  }

  /// Get all active return access keys (for debugging).
  Future<List<String>> getAllActiveReturnAccessKeys() {
    return _localStore.getAllActiveReturnAccessKeys();
  }

  Future<void> updateQueueOperationPayload({
    required String operationId,
    required Map<String, dynamic> payload,
  }) {
    return _localStore.updateQueueOperationPayload(
      operationId: operationId,
      payload: payload,
    );
  }

  Future<void> deleteQueueOperation(String operationId) {
    return _localStore.deleteQueueOperation(operationId);
  }

  Future<void> rebindQueuedOperationsToCurrentContext({
    required String deviceId,
    String? posId,
    String? storeId,
    String? accountId,
    String? userId,
    String? sessionId,
  }) {
    return _localStore.rebindQueuedOperationsToCurrentContext(
      deviceId: deviceId,
      posId: posId,
      storeId: storeId,
      accountId: accountId,
      userId: userId,
      sessionId: sessionId,
    );
  }

  /// Check if a return access key is valid in the local DB.
  /// Pass [checkExpiry: false] for offline refund scenarios.
  Future<bool> checkReturnAccessKey(String key, {bool checkExpiry = true}) {
    return _localStore.checkReturnAccessKey(key, checkExpiry: checkExpiry);
  }

  Future<int> peekNextLocalSaleNumber() {
    return _localStore.peekNextLocalSaleNumber();
  }

  Future<void> ensureLocalSaleCounterSynced() {
    return _localStore.syncSaleLocalCounter();
  }

  Future<void> upsertSalesHistory(List<SaleModel> sales) {
    return _localStore.upsertSalesHistory(sales);
  }

  Future<List<SaleModel>> loadAllSalesHistory() {
    return _localStore.loadAllSalesHistory();
  }

  Future<List<RefundModel>> loadAllRefundsHistory() {
    return _localStore.loadAllRefundsHistory();
  }

  Future<List<LocalSession>> loadSessions() {
    return _localStore.loadSessions();
  }

  Future<({List<SaleModel> items, int total})> loadSalesHistoryPage({
    int page = 1,
    int perPage = 15,
  }) {
    return _localStore.loadSalesHistoryPage(page: page, perPage: perPage);
  }

  Future<ShiftReportData?> loadShiftReport(String clientSessionId) {
    return _localStore.loadShiftReport(clientSessionId);
  }

  Future<ShiftReportData?> loadShiftReportFromBackend({
    required String key,
    required String sessionId,
    String? deviceId,
    bool includeProducts = true,
  }) async {
    await initialize();
    final serverSessionId = await _resolveReportSessionId(sessionId);
    final cleanDeviceId = (deviceId ?? '').trim();
    if (includeProducts && cleanDeviceId.isEmpty) {
      throw Exception('x-report: deviceId is required');
    }
    final data = includeProducts
        ? await _remote.fetchXReport(
            key: key,
            sessionId: serverSessionId,
            deviceId: cleanDeviceId,
          )
        : await _remote.fetchZReport(key: key, sessionId: serverSessionId);
    return _mapRemoteShiftReport(
      data,
      fallbackSessionId: serverSessionId,
      includeProducts: includeProducts,
    );
  }

  Future<ShiftClosureSummaryData?> loadShiftClosureSummary(
      String clientSessionId) {
    return _localStore.loadShiftClosureSummary(clientSessionId);
  }

  Future<ShiftClosureSummaryData?> loadShiftClosureSummaryFromBackend({
    required String key,
    required String sessionId,
    required String deviceId,
  }) async {
    await initialize();
    final serverSessionId = await _resolveReportSessionId(sessionId);
    final cleanDeviceId = deviceId.trim();
    if (cleanDeviceId.isEmpty) {
      throw Exception('x-report: deviceId is required');
    }
    final data = await _remote.fetchXReport(
      key: key,
      sessionId: serverSessionId,
      deviceId: cleanDeviceId,
    );
    return _mapRemoteShiftClosureSummary(
      data,
      fallbackSessionId: serverSessionId,
    );
  }

  Future<void> bootstrap({
    required String key,
    required String deviceId,
    void Function(SyncProgress progress)? onProgress,
  }) {
    if (_bootstrapFuture != null) return _bootstrapFuture!;
    _syncCancelRequested = false;
    return _bootstrapFuture ??= _runBootstrap(
      key: key,
      deviceId: deviceId,
      onProgress: onProgress,
    ).whenComplete(() => _bootstrapFuture = null);
  }

  Future<void> _runBootstrap({
    required String key,
    required String deviceId,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);
    _throwIfSyncCancelled();

    // Step 1 — Request snapshot
    onProgress?.call(
        const SyncProgress(progress: 0.05, stage: 'Запрашиваем снапшот...'));
    var snapshot = await _remote.requestSnapshot(key: key);
    _throwIfSyncCancelled();

    // Step 2 — Poll until ready (retry POST if failed)
    var retryCount = 0;
    while (!snapshot.isReady) {
      if (snapshot.isFailed) {
        if (retryCount >= 3) {
          throw Exception('Snapshot failed after $retryCount retries');
        }
        retryCount++;
        onProgress?.call(SyncProgress(
            progress: 0.05,
            stage: 'Повторяем запрос снапшота...',
            detail: 'попытка $retryCount'));
        snapshot = await _remote.requestSnapshot(key: key);
        continue;
      }
      await Future.delayed(const Duration(seconds: 3));
      _throwIfSyncCancelled();
      onProgress?.call(const SyncProgress(
          progress: 0.08, stage: 'Ожидаем подготовку снапшота...'));
      snapshot = await _remote.pollSnapshotStatus(key: key);
      _throwIfSyncCancelled();
    }

    final snapshotUrl = snapshot.url;
    if (snapshotUrl == null || snapshotUrl.isEmpty) {
      throw Exception('Snapshot ready but URL is empty');
    }

    // Step 3 — Download snapshot file
    onProgress?.call(
        const SyncProgress(progress: 0.15, stage: 'Скачиваем снапшот...'));
    final snapshotFile = await _remote.downloadSnapshotFile(snapshotUrl);
    _throwIfSyncCancelled();
    _diagnostics?.recordSnapshotFile(snapshotFile);
    final snapshotCursor = snapshot.cursor > 0
        ? snapshot.cursor
        : _readIntFromMap(snapshotFile, 'cursor');

    final rawProducts = (snapshotFile['products'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        <Map<String, dynamic>>[];
    final rawSales = (snapshotFile['sales'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        <Map<String, dynamic>>[];
    final rawRefunds = (snapshotFile['refunds'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        <Map<String, dynamic>>[];

    onProgress?.call(
      SyncProgress(
        progress: 0.30,
        stage: 'Загружаем счета...',
        detail: '${rawProducts.length} товаров, ${rawSales.length} продаж',
      ),
    );
    final accounts = await _remote.fetchAllAccounts(key: key);
    _throwIfSyncCancelled();

    onProgress?.call(SyncProgress(
        progress: 0.45,
        stage: 'Загружаем типы расходов...',
        detail: '${accounts.length} счетов'));
    final expenseTypes = await _remote.fetchAllExpenseTypes(key: key);
    _throwIfSyncCancelled();

    onProgress?.call(SyncProgress(
        progress: 0.58,
        stage: 'Загружаем покупателей...',
        detail: '${expenseTypes.length} типов расходов'));
    final customers = await _remote.fetchAllCustomers(key: key);
    _throwIfSyncCancelled();

    onProgress?.call(SyncProgress(
        progress: 0.68,
        stage: 'Подключаемся к серверу...',
        detail: '${customers.length} покупателей'));
    final posInfo = await _remote.fetchPosInfo(key: key);
    _throwIfSyncCancelled();

    onProgress?.call(
        const SyncProgress(progress: 0.73, stage: 'Сохраняем данные...'));
    await _localStore.replaceBootstrapData(
      posKey: key,
      deviceId: deviceId,
      cursorBefore: snapshotCursor,
      posInfo: posInfo,
      products: rawProducts,
      sales: rawSales,
      refunds: rawRefunds,
      accounts: accounts,
      expenseTypes: expenseTypes,
      customers: customers,
    );
    _throwIfSyncCancelled();
    _diagnostics?.recordBootstrapSummary({
      'pos_key': key,
      'device_id': deviceId,
      'snapshot_status': {
        'status': snapshot.status,
        'cursor': snapshot.cursor,
        'url': snapshot.url,
        'expires_at': snapshot.expiresAt?.toIso8601String(),
      },
      'snapshot_cursor': snapshotCursor,
      'saved_counts': {
        'products': rawProducts.length,
        'sales': rawSales.length,
        'refunds': rawRefunds.length,
        'accounts': accounts.length,
        'expense_types': expenseTypes.length,
        'customers': customers.length,
      },
      'saved_snapshot_products': rawProducts,
    });
    _notifyDebtsChanged();

    onProgress?.call(
        const SyncProgress(progress: 0.82, stage: 'Применяем обновления...'));
    await _runPullOnce(
      key: key,
      deviceId: deviceId,
      initialCursor: snapshotCursor,
      refreshPosInfoAfterPull: false,
      onProgress: (progress) {
        final normalized = 0.82 + (progress.progress * 0.17);
        onProgress?.call(
          SyncProgress(
            progress: normalized.clamp(0.82, 0.99),
            stage: progress.stage,
            detail: progress.detail,
          ),
        );
      },
    );

    onProgress?.call(
      const SyncProgress(progress: 0.995, stage: 'Обновляем данные кассы...'),
    );
    await refreshPosInfo(key: key);
    _throwIfSyncCancelled();

    onProgress?.call(
        const SyncProgress(progress: 1, stage: 'Синхронизация завершена'));
  }

  int _readIntFromMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  Future<void> pullOnce({
    required String key,
    required String deviceId,
    int? initialCursor,
    bool refreshPosInfoAfterPull = true,
    void Function(SyncProgress progress)? onProgress,
  }) {
    if (_pullFuture != null) return _pullFuture!;
    _syncCancelRequested = false;
    return _pullFuture ??= _runPullOnce(
      key: key,
      deviceId: deviceId,
      initialCursor: initialCursor,
      refreshPosInfoAfterPull: refreshPosInfoAfterPull,
      onProgress: onProgress,
    ).whenComplete(() => _pullFuture = null);
  }

  Future<void> _runPullOnce({
    required String key,
    required String deviceId,
    int? initialCursor,
    bool refreshPosInfoAfterPull = true,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);
    _throwIfSyncCancelled();
    var cursor =
        initialCursor ?? (await _localStore.loadSyncState(key))?.cursor ?? 0;
    var batchIndex = 0;

    while (true) {
      _throwIfSyncCancelled();
      batchIndex += 1;
      onProgress?.call(
        SyncProgress(
          progress: batchIndex == 1 ? 0.1 : 0.6,
          stage: 'Получаем изменения',
          detail: 'cursor=$cursor',
        ),
      );

      final batch = await _remote.pullChanges(
        key: key,
        cursor: cursor,
        limit: 500,
      );
      _throwIfSyncCancelled();

      if (batch.items.isNotEmpty) {
        onProgress?.call(
          SyncProgress(
            progress: 0.8,
            stage: 'Применяем изменения',
            detail: 'batch $batchIndex',
          ),
        );
        await _localStore.applyPullBatch(
          posKey: key,
          changes: batch.items,
          nextCursor: batch.nextCursor,
        );
        final hasProducts = batch.items.any(
          (c) => c.entity.trim().toLowerCase().contains('product'),
        );
        if (hasProducts && !_productsChangedController.isClosed) {
          _productsChangedController.add(null);
        }
        final hasDebtRelatedChanges = batch.items.any((c) {
          final entity = c.entity.trim().toLowerCase();
          return entity.contains('customer') ||
              entity.contains('sale') ||
              entity.contains('payment') ||
              entity.contains('settlement');
        });
        if (hasDebtRelatedChanges) {
          _notifyDebtsChanged();
        }
        _notifySalesHistoryChanged();
      } else if (batch.nextCursor != cursor) {
        await _localStore.applyPullBatch(
          posKey: key,
          changes: const [],
          nextCursor: batch.nextCursor,
        );
      }

      cursor = batch.nextCursor;
      if (!batch.hasMore) {
        break;
      }
    }

    if (refreshPosInfoAfterPull) {
      _throwIfSyncCancelled();
      onProgress?.call(
        const SyncProgress(
          progress: 0.98,
          stage: 'Обновляем данные кассы',
        ),
      );
      await refreshPosInfo(key: key);
      _throwIfSyncCancelled();
    }
  }

  Future<void> pushPending({
    required String key,
    required String deviceId,
    int limit = 5,
    void Function(QueuePushEvent event)? onProgress,
  }) {
    if (_pushFuture != null) return _pushFuture!;
    _syncCancelRequested = false;
    return _pushFuture ??= _runPushPending(
      key: key,
      deviceId: deviceId,
      limit: limit,
      onProgress: onProgress,
    ).whenComplete(() => _pushFuture = null);
  }

  Future<void> _runPushPending({
    required String key,
    required String deviceId,
    int limit = 5,
    void Function(QueuePushEvent event)? onProgress,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);
    _throwIfSyncCancelled();

    final records = await _localStore.claimPendingOperations(limit: limit);
    if (records.isEmpty) return;

    var ackedCount = 0;
    for (final record in records) {
      _throwIfSyncCancelled();
      onProgress?.call(
        QueuePushEvent(
          operationId: record.id,
          type: record.type,
          clientId: record.clientId,
          title: _queueRecordTitle(record),
          stage: QueuePushStage.sending,
          message: 'Отправляется...',
        ),
      );
      final result = await _sendClaimedRecord(
        key: key,
        deviceId: deviceId,
        record: record,
      );
      _throwIfSyncCancelled();
      onProgress?.call(
        QueuePushEvent(
          operationId: record.id,
          type: record.type,
          clientId: record.clientId,
          title: _queueRecordTitle(record),
          stage: switch (result.result) {
            QueueSendResult.sent => QueuePushStage.success,
            QueueSendResult.queued => QueuePushStage.queued,
            QueueSendResult.manual => QueuePushStage.error,
          },
          message: switch (result.result) {
            QueueSendResult.sent => 'Успешно отправлено',
            QueueSendResult.queued =>
              result.errorMessage?.trim().isNotEmpty == true
                  ? result.errorMessage!.trim()
                  : 'Не отправлено, останется в очереди',
            QueueSendResult.manual =>
              result.errorMessage?.trim().isNotEmpty == true
                  ? result.errorMessage!.trim()
                  : 'Ошибка, требуется ручная проверка',
          },
        ),
      );
      if (result.result == QueueSendResult.sent) {
        ackedCount++;
      }
    }

    if (ackedCount > 0) {
      _syncedController.add(ackedCount);
      _notifySalesHistoryChanged();
      await _localStore.touchLastPush(key);
      await _runBackgroundPull(key: key, deviceId: deviceId);
    }
  }

  Future<QueueOperationResult?> sendQueueOperationById({
    required String key,
    required String deviceId,
    required String operationId,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);

    final claimed = await _localStore.claimOperationById(operationId);
    if (claimed == null) return null;

    final result = await _sendClaimedRecord(
      key: key,
      deviceId: deviceId,
      record: claimed,
    );
    if (result.result == QueueSendResult.sent) {
      _syncedController.add(1);
      _notifySalesHistoryChanged();
      await _localStore.touchLastPush(key);
      unawaited(_runBackgroundPull(key: key, deviceId: deviceId));
    }
    return result;
  }

  Future<QueueOperationResult> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
    required List<Map<String, dynamic>> payments,
    bool sendInBackground = false,
    bool requireOnline = false,
  }) async {
    final localPosSessionId = sale.posSessionId?.trim() ?? '';
    final localNumber = await _localStore.nextLocalSaleNumber();
    final exactTotal = double.parse(
      sale.items
          .fold(0.0, (sum, item) => sum + item.totalPrice)
          .toStringAsFixed(2),
    );
    final normalizedPaymentMethod = sale.paymentMethod.trim().toLowerCase();
    final normalizedPayments = _normalizedSalePayments(
      paymentMethod: normalizedPaymentMethod,
      posAccountId: sale.accountId,
      totalAmount: exactTotal,
      payments: payments,
    );
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_sale_id': sale.localId,
      'local_number': localNumber,
      if (localPosSessionId.isNotEmpty) 'pos_session_id': localPosSessionId,
      'date': _formatDate(sale.date),
      'total_amount': exactTotal,
      'payment_method':
          normalizedPaymentMethod == 'cash' ? 'cash' : sale.paymentMethod,
      if ((sale.paymentType ?? '').trim().isNotEmpty)
        'payment_type': sale.paymentType,
      if (sale.paidAmount > 0) 'paid_amount': sale.paidAmount,
      if (sale.debtAmount > 0) 'debt_amount': sale.debtAmount,
      if ((sale.paidPaymentMethod ?? '').trim().isNotEmpty)
        'paid_payment_method': sale.paidPaymentMethod,
      if (sale.dueDate != null)
        'due_date':
            '${sale.dueDate!.year.toString().padLeft(4, '0')}-${sale.dueDate!.month.toString().padLeft(2, '0')}-${sale.dueDate!.day.toString().padLeft(2, '0')}',
      if ((sale.comment ?? '').trim().isNotEmpty) 'comment': sale.comment,
      if ((sale.idempotencyKey ?? '').trim().isNotEmpty)
        'idempotency_key': sale.idempotencyKey,
      'pos_id': sale.posId,
      'store_id': sale.storeId,
      'user_id': sale.userId,
      if ((sale.customerId ?? '').trim().isNotEmpty)
        'customer_id': sale.customerId!.trim(),
      'items': sale.items
          .map(
            (item) => {
              'product_id': item.productId,
              'product_name': (item.product?.name ?? '').trim().isEmpty
                  ? item.productId
                  : item.product!.name,
              'quantity': item.quantity,
              'price': item.price,
              'total_price': item.totalPrice,
              if (item.markCodes.isNotEmpty) 'mark_codes': item.markCodes,
            },
          )
          .toList(growable: false),
      'payments': normalizedPayments,
    };

    await _localStore.insertSaleLocal(
      clientSaleId: sale.localId,
      localNumber: localNumber,
      payload: payload,
    );
    _notifySalesHistoryChanged();

    final result = await _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.sale,
      clientId: sale.localId,
      payload: payload,
      tryImmediateSend: !sendInBackground,
    );
    // Keep the original operation on timeout. Retrying must reuse the same
    // client_sale_id, local_number and byte-for-byte marking payload.
    if (result.result == QueueSendResult.sent &&
        sale.paymentMethod.trim().toLowerCase() == 'debt') {
      _notifyDebtsChanged();
      unawaited(_runBackgroundPull(key: key, deviceId: deviceId));
    }
    return result;
  }

  Future<void> registerOpenedSession({
    required String sessionId,
    required String userId,
    required String deviceId,
    String? serverSessionId,
    required DateTime openedAt,
  }) async {
    final value = sessionId.trim();
    if (value.isEmpty) {
      throw Exception('openSession: server returned empty session id');
    }

    await _localStore.upsertSession(
      sessionId: value,
      userId: userId,
      deviceId: deviceId,
      serverSessionId: serverSessionId,
      openedAt: openedAt,
    );
    await _localStore.markSessionSynced(value);
  }

  Future<QueueOperationResult> openSession({
    required String key,
    required String deviceId,
    required String userId,
    DateTime? openedAt,
  }) async {
    final pending = _openSessionFuture;
    if (pending != null) return pending;

    final future = _openSessionLocked(
      key: key,
      deviceId: deviceId,
      userId: userId,
      openedAt: openedAt,
    );
    _openSessionFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_openSessionFuture, future)) {
        _openSessionFuture = null;
      }
    }
  }

  Future<QueueOperationResult> _openSessionLocked({
    required String key,
    required String deviceId,
    required String userId,
    DateTime? openedAt,
  }) async {
    final existingSession = await _findOpenSessionForDevice(deviceId);
    if (existingSession != null) {
      if (existingSession.userId.trim() != userId.trim()) {
        throw Exception('Смена уже открыта другим кассиром');
      }

      return QueueOperationResult(
        operationId: '',
        result: QueueSendResult.queued,
        type: OutboxOperationType.sessionOpen,
        clientId: existingSession.clientSessionId,
        payload: {
          'device_id': existingSession.deviceId,
          'client_session_id': existingSession.clientSessionId,
          'opened_at': _formatDate(existingSession.openedAt),
          'user_id': existingSession.userId,
        },
      );
    }

    final clientSessionId = 'session_${_uuid.v7()}';
    final effectiveOpenedAt = openedAt ?? DateTime.now();

    await _localStore.upsertSession(
      sessionId: clientSessionId,
      serverSessionId: null,
      userId: userId,
      deviceId: deviceId,
      openedAt: effectiveOpenedAt,
    );

    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_session_id': clientSessionId,
      'opened_at': _formatDate(effectiveOpenedAt),
      'user_id': userId,
    };

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.sessionOpen,
      clientId: clientSessionId,
      payload: payload,
    );
  }

  Future<LocalSession?> _findOpenSessionForDevice(String deviceId) async {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) return null;

    final sessions = await _localStore.loadSessions();
    for (final session in sessions) {
      if (session.deviceId.trim() == normalizedDeviceId &&
          session.isOpened &&
          session.closedAt == null) {
        return session;
      }
    }
    return null;
  }

  Future<void> registerClosedSession({
    required String sessionId,
    required double closingCashAmount,
    required DateTime closedAt,
  }) async {
    final value = sessionId.trim();
    if (value.isEmpty) {
      throw Exception('closeSession: session id is empty');
    }

    await _localStore.closeSessionLocal(
      sessionId: value,
      closingCashAmount: closingCashAmount,
      closedAt: closedAt,
    );
    await _localStore.markSessionSynced(value);
  }

  Future<QueueOperationResult> createPayment({
    required String key,
    required String deviceId,
    required String posSessionId,
    required String accountId,
    required bool isExpense,
    required num amount,
    required DateTime date,
    String? comment,
    String? expenseTypeId,
    String? userId,
  }) async {
    final localPosSessionId = posSessionId.trim();
    final clientId = 'payment_${_uuid.v7()}';
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_payment_id': clientId,
      'date': _formatDate(date),
      'is_expense': isExpense,
      'amount': amount.round(),
      'pos_session_id': localPosSessionId,
      'account_id': accountId,
      if ((comment ?? '').trim().isNotEmpty) 'comment': comment!.trim(),
      if ((expenseTypeId ?? '').trim().isNotEmpty)
        'expense_type_id': expenseTypeId!.trim(),
      if ((userId ?? '').trim().isNotEmpty) 'created_by_id': userId!.trim(),
    };

    await _localStore.insertPaymentLocal(payload);

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.payment,
      clientId: clientId,
      payload: payload,
    );
  }

  Future<QueueOperationResult> createRefund({
    required String key,
    required String deviceId,
    required String posSessionId,
    String? posId,
    String? storeId,
    String? accountId,

    /// Server-assigned sale id. Pass empty string if the sale is not yet synced.
    required String saleId,

    /// Client-side client_sale_id. Required when [saleId] is empty (offline refund).
    String? clientSaleId,
    required num totalAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>> payments,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    String? returnAccessKey,
    String? reasonCode,
    String? note,
  }) async {
    final localPosSessionId = posSessionId.trim();
    final clientId = 'refund_${_uuid.v7()}';
    final cleanSaleId = saleId.trim();
    final cleanClientSaleId = (clientSaleId ?? '').trim();
    final hasLinkedSale =
        cleanSaleId.isNotEmpty || cleanClientSaleId.isNotEmpty;
    final nonZeroPayments = _withoutZeroAmountPayments(payments);
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_refund_id': clientId,
      'pos_session_id': localPosSessionId,
      'date': _formatDate(date),
      if (cleanSaleId.isNotEmpty) 'sale_id': cleanSaleId,
      if (cleanSaleId.isEmpty && cleanClientSaleId.isNotEmpty)
        'client_sale_id': cleanClientSaleId,
      if ((posId ?? '').trim().isNotEmpty) 'pos_id': posId!.trim(),
      if ((storeId ?? '').trim().isNotEmpty) 'store_id': storeId!.trim(),
      if (!hasLinkedSale && (accountId ?? '').trim().isNotEmpty)
        'account_id': accountId!.trim(),
      'total_amount': totalAmount,
      if (!hasLinkedSale) 'payment_method': paymentMethod,
      if ((reasonCode ?? '').trim().isNotEmpty)
        'reason_code': reasonCode!.trim(),
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      if (!hasLinkedSale) 'payments': nonZeroPayments,
      'items': items,
      if ((returnAccessKey ?? '').trim().isNotEmpty)
        'return_access_key': returnAccessKey!.trim(),
    };

    await _localStore.insertRefundLocal(payload);
    _notifySalesHistoryChanged();

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.refund,
      clientId: clientId,
      payload: payload,
    );
  }

  List<Map<String, dynamic>> _withoutZeroAmountPayments(
    List<Map<String, dynamic>> payments,
  ) {
    return payments.where((payment) {
      final amount = payment['amount'];
      if (amount is num) return amount > 0;
      final parsed = num.tryParse((amount ?? '').toString().trim());
      return parsed != null && parsed > 0;
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _normalizedSalePayments({
    required String paymentMethod,
    required String posAccountId,
    required num totalAmount,
    required List<Map<String, dynamic>> payments,
  }) {
    final nonZeroPayments = _withoutZeroAmountPayments(payments);

    if (paymentMethod == 'cash') {
      final cleanPosAccountId = posAccountId.trim();
      if (cleanPosAccountId.isEmpty) {
        throw Exception('POS account_id is empty for cash sale');
      }

      final existingClientPaymentId =
          _firstClientPaymentId(nonZeroPayments).trim();

      return [
        {
          'account_id': cleanPosAccountId,
          'amount': totalAmount,
          'client_payment_id': existingClientPaymentId.isNotEmpty
              ? existingClientPaymentId
              : _uuid.v4(),
        },
      ];
    }

    return nonZeroPayments
        .map((payment) => _salePaymentApiJson(payment))
        .toList(growable: false);
  }

  Map<String, dynamic> _salePaymentApiJson(Map<String, dynamic> payment) {
    final accountId = (payment['account_id'] ?? '').toString().trim();
    final clientPaymentId =
        (payment['client_payment_id'] ?? '').toString().trim();
    return {
      'account_id': accountId,
      'amount': payment['amount'],
      if (clientPaymentId.isNotEmpty) 'client_payment_id': clientPaymentId,
      if ((payment['comment'] ?? '').toString().trim().isNotEmpty)
        'comment': payment['comment'].toString().trim(),
    };
  }

  String _firstClientPaymentId(List<Map<String, dynamic>> payments) {
    for (final payment in payments) {
      final value = (payment['client_payment_id'] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<QueueOperationResult> _queueAndTrySend({
    required String key,
    required String deviceId,
    required OutboxOperationType type,
    required String clientId,
    required Map<String, dynamic> payload,
    String? relatedClientId,
    bool tryImmediateSend = true,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);
    final operationId = _uuid.v7();

    await _localStore.enqueueOperation(
      id: operationId,
      type: type,
      clientId: clientId,
      relatedClientId: relatedClientId,
      payload: payload,
    );

    if (!tryImmediateSend) {
      Timer.run(() {
        _runBackgroundPush(key: key, deviceId: deviceId);
      });
      return QueueOperationResult(
        operationId: operationId,
        result: QueueSendResult.queued,
        type: type,
        clientId: clientId,
        payload: payload,
      );
    }

    if (_pushFuture != null) {
      return QueueOperationResult(
        operationId: operationId,
        result: QueueSendResult.queued,
        type: type,
        clientId: clientId,
        payload: payload,
      );
    }

    final claimed = await _localStore.claimSpecificPendingOperation(
      type: type,
      clientId: clientId,
    );
    if (claimed == null) {
      return QueueOperationResult(
        operationId: operationId,
        result: QueueSendResult.queued,
        type: type,
        clientId: clientId,
        payload: payload,
      );
    }

    final result = await _sendClaimedRecord(
      key: key,
      deviceId: deviceId,
      record: claimed,
    );
    if (result.result == QueueSendResult.sent) {
      await _localStore.touchLastPush(key);
      _notifySalesHistoryChanged();
      _runBackgroundPull(key: key, deviceId: deviceId);
    }
    return result;
  }

  Future<void> _runBackgroundPush({
    required String key,
    required String deviceId,
    int limit = 5,
  }) {
    if (!_backgroundLoopsActive) return Future<void>.value();
    return _ignoreBackgroundSyncErrors(
      pushPending(key: key, deviceId: deviceId, limit: limit),
    );
  }

  Future<void> _runBackgroundPull({
    required String key,
    required String deviceId,
  }) {
    if (!_backgroundLoopsActive) return Future<void>.value();
    return _ignoreBackgroundSyncErrors(
      pullOnce(key: key, deviceId: deviceId),
    );
  }

  Future<void> _ignoreBackgroundSyncErrors(Future<void> future) async {
    try {
      await future;
    } on _SyncCancelledException {
      // Cancellation is intentional.
    } catch (_) {
      // Background sync is best-effort. Pending operations stay queued and
      // will be retried by the next timer tick or when connectivity returns.
    }
  }

  void _throwIfSyncCancelled() {
    if (_syncCancelRequested) throw const _SyncCancelledException();
  }

  Future<String> resolveServerSessionId(String sessionId) {
    return _localStore.resolveServerSessionId(sessionId);
  }

  Future<String> _resolveReportSessionId(String sessionId) async {
    final value = sessionId.trim();
    if (value.isEmpty) return value;
    try {
      return await _localStore.resolveServerSessionId(value);
    } catch (_) {
      return value;
    }
  }

  ShiftReportData _mapRemoteShiftReport(
    Map<String, dynamic> data, {
    required String fallbackSessionId,
    required bool includeProducts,
  }) {
    final summary = _asMap(data['summary']);
    final products =
        includeProducts ? _asListOfMaps(data['products']) : const [];
    final items = products.map((product) {
      return ShiftReportItem(
        name: _stringFromMap(product, 'name', fallback: 'Товар'),
        quantity: _numFromMap(product, 'quantity'),
        totalSum: _numFromMap(product, 'amount'),
      );
    }).toList(growable: false);
    final cashTotal = _numFromMap(summary, 'sales_cash_total');
    final cardTotal = _numFromMap(summary, 'sales_card_total');
    final grandTotal = _numFromMap(summary, 'sales_total');
    final debtTotal = _numFromMap(summary, 'debt_total');

    return ShiftReportData(
      sessionId:
          _stringFromMap(data, 'session_id', fallback: fallbackSessionId),
      openedAt: _parseRemoteDate(data['opened_at']),
      closedAt: _parseRemoteDate(data['closed_at']),
      openingCashAmount: _numFromMap(summary, 'opening_cash_amount'),
      closingCashAmount: 0,
      salesCount: 0,
      cashTotal: cashTotal,
      cardTotal: cardTotal,
      transferTotal: 0,
      creditTotal: debtTotal,
      grandTotal: grandTotal,
      refundsTotal: _numFromMap(summary, 'refunds_total'),
      incomeTotal: _numFromMap(summary, 'income_total'),
      expenseTotal: _numFromMap(summary, 'expense_total'),
      expectedCashAmount: _numFromMap(summary, 'expected_cash_amount'),
      items: items,
    );
  }

  ShiftClosureSummaryData _mapRemoteShiftClosureSummary(
    Map<String, dynamic> data, {
    required String fallbackSessionId,
  }) {
    final summary = _asMap(data['summary']);
    final cashTotal = _numFromMap(summary, 'sales_cash_total');
    final cardTotal = _numFromMap(summary, 'sales_card_total');
    final salesTotal = _numFromMap(summary, 'sales_total');
    final debtTotal = _numFromMap(summary, 'debt_total');
    final cashlessAccounts = _asListOfMaps(data['cashless_accounts'])
        .map(_mapCashlessAccountReport)
        .toList(growable: false);

    return ShiftClosureSummaryData(
      sessionId:
          _stringFromMap(data, 'session_id', fallback: fallbackSessionId),
      openingCashAmount: _numFromMap(summary, 'opening_cash_amount'),
      cashSalesTotal: cashTotal,
      cardSalesTotal: cardTotal,
      transferSalesTotal: 0,
      creditSalesTotal: debtTotal,
      refundsTotal: _numFromMap(summary, 'refunds_total'),
      incomeTotal: _numFromMap(summary, 'income_total'),
      expenseTotal: _numFromMap(summary, 'expense_total'),
      expectedCashAmount: _numFromMap(summary, 'expected_cash_amount'),
      totalSalesAmount: salesTotal,
      cashlessAccounts: cashlessAccounts,
    );
  }

  CashlessAccountReport _mapCashlessAccountReport(Map<String, dynamic> json) {
    return CashlessAccountReport(
      accountId: _stringFromMap(json, 'account_id'),
      accountName: _stringFromMap(json, 'account_name'),
      salesTotal: _numFromMap(json, 'sales_total').toDouble(),
      refundsTotal: _numFromMap(json, 'refunds_total').toDouble(),
      incomeTotal: _numFromMap(json, 'income_total').toDouble(),
      expenseTotal: _numFromMap(json, 'expense_total').toDouble(),
      netTotal: _numFromMap(json, 'net_total').toDouble(),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  num _numFromMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value;
    return num.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  bool _boolFromMap(
    Map<String, dynamic> map,
    String key, {
    bool fallback = false,
  }) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  String _stringFromMap(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) {
    final value = (map[key] ?? '').toString().trim();
    return value.isEmpty ? fallback : value;
  }

  String? _nullableStringFromMap(Map<String, dynamic> map, String key) {
    final value = (map[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  DateTime? _parseRemoteDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  Future<QueueOperationResult> _sendClaimedRecord({
    required String key,
    required String deviceId,
    required OutboxOperationRecord record,
  }) async {
    late final Map<String, dynamic> payloadForSend;
    try {
      payloadForSend = await _preparePayloadForSend(record);
      final responseData = await _remote.sendOperation(
        type: record.type,
        key: key,
        payload: {
          ...payloadForSend,
          'device_id': deviceId,
        },
      );
      await _applySuccessfulResponse(record, responseData);
      await _localStore.markOperationAcked(record.id);
      _markDedicatedTableSynced(record);
      return QueueOperationResult(
        operationId: record.id,
        result: QueueSendResult.sent,
        type: record.type,
        clientId: record.clientId,
        payload: payloadForSend,
        responseData: responseData,
      );
    } catch (error) {
      if (error is _WaitingForServerSessionId ||
          error is _WaitingForServerProductId) {
        final message = switch (error) {
          _WaitingForServerSessionId() => error.message,
          _WaitingForServerProductId() => error.message,
          _ => 'Ожидаем связанные данные',
        };
        await _localStore.deferOperation(
          operationId: record.id,
          message: message,
        );
        return QueueOperationResult(
          operationId: record.id,
          result: QueueSendResult.queued,
          type: record.type,
          clientId: record.clientId,
          payload: record.payload,
          errorMessage: message,
        );
      }

      final errorCode = _remote.extractErrorCode(error);
      final errorMessage = _remote.extractErrorMessage(error);
      final errorDetails = _remote.extractErrorDetails(error);

      if (errorCode == 'IDEMPOTENCY_CONFLICT') {
        await _localStore.markOperationManual(
          operationId: record.id,
          errorCode: errorCode,
          errorMessage: errorMessage,
          payload: payloadForSend,
        );
        return QueueOperationResult(
          operationId: record.id,
          result: QueueSendResult.manual,
          type: record.type,
          clientId: record.clientId,
          payload: payloadForSend,
          errorMessage: errorMessage,
        );
      }

      if (_remote.isRetryable(error) && record.retryCount < _maxRetryCount) {
        await _localStore.markOperationPending(
          operationId: record.id,
          errorCode: errorCode,
          errorMessage: errorMessage,
          payload: payloadForSend,
          errorDetails: errorDetails,
        );
        return QueueOperationResult(
          operationId: record.id,
          result: QueueSendResult.queued,
          type: record.type,
          clientId: record.clientId,
          payload: record.payload,
          errorCode: errorCode,
          errorMessage: errorMessage,
        );
      }

      final manualCode = _remote.isManualErrorCode(errorCode)
          ? errorCode
          : 'MANUAL_REVIEW_REQUIRED';
      await _localStore.markOperationManual(
        operationId: record.id,
        errorCode: manualCode,
        errorMessage: errorMessage,
        payload: payloadForSend,
        errorDetails: errorDetails,
      );
      return QueueOperationResult(
        operationId: record.id,
        result: QueueSendResult.manual,
        type: record.type,
        clientId: record.clientId,
        payload: record.payload,
        errorCode: manualCode,
        errorMessage: errorMessage,
      );
    }
  }

  Future<void> _applySuccessfulResponse(
    OutboxOperationRecord record,
    Map<String, dynamic>? responseData,
  ) async {
    if (record.type == OutboxOperationType.productCreate) {
      final response = responseData;
      if (response == null) {
        throw const FormatException('Product response is empty');
      }
      await _localStore.replaceLocalProduct(
        localId: record.clientId,
        serverProduct: {...record.payload, ...response},
      );
      if (!_productsChangedController.isClosed) {
        _productsChangedController.add(null);
      }
      return;
    }
    if (record.type != OutboxOperationType.sessionOpen) return;

    final serverSessionId = responseData?['id']?.toString().trim() ?? '';
    if (serverSessionId.isEmpty) {
      throw Exception('openSession: missing response data.id');
    }

    await _localStore.bindServerSessionId(
      clientSessionId: record.clientId,
      serverSessionId: serverSessionId,
    );
  }

  Future<Map<String, dynamic>> _preparePayloadForSend(
      OutboxOperationRecord record) async {
    final payload = Map<String, dynamic>.from(record.payload);
    await _attachServerSessionIdIfReady(record.type, payload);
    await _attachServerProductIdsIfReady(record.type, payload);
    payload['app_version'] = AppBuildInfo.appVersion;
    return payload;
  }

  Future<void> _attachServerSessionIdIfReady(
    OutboxOperationType type,
    Map<String, dynamic> payload,
  ) async {
    switch (type) {
      case OutboxOperationType.productCreate:
        return;
      case OutboxOperationType.sale:
      case OutboxOperationType.payment:
      case OutboxOperationType.refund:
        final currentSessionId =
            (payload['pos_session_id'] ?? '').toString().trim();
        if (currentSessionId.isEmpty ||
            !currentSessionId.startsWith('session_')) {
          return;
        }
        final serverSessionId =
            await _localStore.findServerSessionId(currentSessionId);
        if (serverSessionId == null || serverSessionId.isEmpty) {
          throw const _WaitingForServerSessionId(
            'Ожидаем получение server session id',
          );
        }
        payload['pos_session_id'] = serverSessionId;
      case OutboxOperationType.sessionOpen:
      case OutboxOperationType.sessionClose:
        return;
    }
  }

  Future<void> _attachServerProductIdsIfReady(
    OutboxOperationType type,
    Map<String, dynamic> payload,
  ) async {
    if (type != OutboxOperationType.sale) return;
    final items = payload['items'];
    if (items is! List) return;
    for (final rawItem in items) {
      if (rawItem is! Map) continue;
      final item = rawItem.cast<String, dynamic>();
      final productId = (item['product_id'] ?? '').toString().trim();
      if (!productId.startsWith('product_')) continue;
      final serverId = await _localStore.findServerProductId(productId);
      if (serverId == null) {
        throw const _WaitingForServerProductId(
          'Ожидаем создание товара на сервере',
        );
      }
      item['product_id'] = serverId;
    }
  }

  void _markDedicatedTableSynced(OutboxOperationRecord record) {
    switch (record.type) {
      case OutboxOperationType.productCreate:
        return;
      case OutboxOperationType.sale:
        unawaited(_localStore.upsertSaleFromOutboxPayload(record.payload));
        unawaited(_localStore.markSaleSynced(record.clientId));
      case OutboxOperationType.payment:
        unawaited(_localStore.markPaymentSynced(record.clientId));
      case OutboxOperationType.refund:
        unawaited(_localStore.markRefundSynced(record.clientId));
      case OutboxOperationType.sessionOpen:
        unawaited(_localStore.markSessionSynced(record.clientId));
      case OutboxOperationType.sessionClose:
        unawaited(_localStore.markSessionSynced(record.clientId));
    }
  }

  void _notifySalesHistoryChanged() {
    if (_salesHistoryChangedController.isClosed) return;
    _salesHistoryChangedController.add(null);
  }

  void _notifyDebtsChanged() {
    if (_debtsChangedController.isClosed) return;
    _debtsChangedController.add(null);
  }

  String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _queueRecordTitle(OutboxOperationRecord record) {
    final payload = record.payload;
    return switch (record.type) {
      OutboxOperationType.productCreate =>
        'Товар ${payload['name'] ?? payload['barcode'] ?? record.clientId}',
      OutboxOperationType.sale =>
        'Чек №${payload['local_number'] ?? payload['client_sale_id'] ?? record.clientId}',
      OutboxOperationType.payment =>
        'Платеж ${payload['amount'] ?? record.clientId}'.trim(),
      OutboxOperationType.refund =>
        'Возврат ${payload['sale_id'] ?? record.clientId}',
      OutboxOperationType.sessionOpen => 'Открытие смены',
      OutboxOperationType.sessionClose => 'Закрытие смены',
    };
  }
}

class _SyncCancelledException implements Exception {
  const _SyncCancelledException();
}

class _WaitingForServerSessionId implements Exception {
  const _WaitingForServerSessionId(this.message);

  final String message;
}

class _WaitingForServerProductId implements Exception {
  const _WaitingForServerProductId(this.message);

  final String message;
}

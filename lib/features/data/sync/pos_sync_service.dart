import 'dart:async';

import 'package:leemon_app/core/service/app_build_info.dart';
import 'package:uuid/uuid.dart';

import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/sale_model.dart' show SaleModel;
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';

class PosSyncService {
  PosSyncService(
    this._localStore,
    this._remote,
  );

  final PosSyncLocalStore _localStore;
  final PosSyncRemoteDataSource _remote;
  final _uuid = const Uuid();

  static const int _maxRetryCount = 50;

  Timer? _pullTimer;
  Timer? _pushTimer;
  Future<void>? _bootstrapFuture;
  Future<void>? _pullFuture;
  Future<void>? _pushFuture;

  final _syncedController = StreamController<int>.broadcast();
  final _productsChangedController = StreamController<void>.broadcast();
  final _salesHistoryChangedController = StreamController<void>.broadcast();

  /// Emits the number of operations successfully sent in each push batch.
  Stream<int> get onOperationsSynced => _syncedController.stream;

  /// Emits whenever pull sync applies changes that include product entities.
  Stream<void> get onProductsChanged => _productsChangedController.stream;

  /// Emits when sales/refunds change and the history UI should refresh.
  Stream<void> get onSalesHistoryChanged =>
      _salesHistoryChangedController.stream;

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
    await _localStore.close();
  }

  void startBackgroundLoops({
    required String key,
    required String deviceId,
  }) {
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
    _pullTimer?.cancel();
    _pushTimer?.cancel();
    _pullTimer = null;
    _pushTimer = null;
  }

  Future<void> clearAllLocalData() {
    return _localStore.clearAllLocalData();
  }

  Future<List<ProductModel>> loadProducts() {
    return _localStore.loadProducts();
  }

  Future<List<ProductModel>> loadFavoriteProducts() {
    return _localStore.loadFavoriteProducts();
  }

  Future<List<LocalExpenseType>> loadExpenseTypes() {
    return _localStore.loadExpenseTypes();
  }

  Future<List<LocalCustomer>> loadCustomers() {
    return _localStore.loadCustomers();
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

  Future<({List<SaleModel> items, int total})> loadSalesHistoryPage({
    int page = 1,
    int perPage = 15,
  }) {
    return _localStore.loadSalesHistoryPage(page: page, perPage: perPage);
  }

  Future<ShiftReportData?> loadShiftReport(String clientSessionId) {
    return _localStore.loadShiftReport(clientSessionId);
  }

  Future<ShiftClosureSummaryData?> loadShiftClosureSummary(
      String clientSessionId) {
    return _localStore.loadShiftClosureSummary(clientSessionId);
  }

  Future<void> bootstrap({
    required String key,
    required String deviceId,
    void Function(SyncProgress progress)? onProgress,
  }) {
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

    // Step 1 — Request snapshot
    onProgress?.call(
        const SyncProgress(progress: 0.05, stage: 'Запрашиваем снапшот...'));
    var snapshot = await _remote.requestSnapshot(key: key);

    // Step 2 — Poll until ready (retry POST if failed)
    var retryCount = 0;
    while (!snapshot.isReady) {
      if (snapshot.isFailed) {
        if (retryCount >= 3)
          throw Exception('Snapshot failed after $retryCount retries');
        retryCount++;
        onProgress?.call(SyncProgress(
            progress: 0.05,
            stage: 'Повторяем запрос снапшота...',
            detail: 'попытка $retryCount'));
        snapshot = await _remote.requestSnapshot(key: key);
        continue;
      }
      await Future.delayed(const Duration(seconds: 3));
      onProgress?.call(const SyncProgress(
          progress: 0.08, stage: 'Ожидаем подготовку снапшота...'));
      snapshot = await _remote.pollSnapshotStatus(key: key);
    }

    final snapshotUrl = snapshot.url;
    if (snapshotUrl == null || snapshotUrl.isEmpty) {
      throw Exception('Snapshot ready but URL is empty');
    }

    // Step 3 — Download snapshot file
    onProgress?.call(
        const SyncProgress(progress: 0.15, stage: 'Скачиваем снапшот...'));
    final snapshotFile = await _remote.downloadSnapshotFile(snapshotUrl);
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

    onProgress?.call(
      SyncProgress(
        progress: 0.30,
        stage: 'Загружаем счета...',
        detail: '${rawProducts.length} товаров, ${rawSales.length} продаж',
      ),
    );
    final accounts = await _remote.fetchAllAccounts(key: key);

    onProgress?.call(SyncProgress(
        progress: 0.45,
        stage: 'Загружаем типы расходов...',
        detail: '${accounts.length} счетов'));
    final expenseTypes = await _remote.fetchAllExpenseTypes(key: key);

    onProgress?.call(SyncProgress(
        progress: 0.58,
        stage: 'Загружаем покупателей...',
        detail: '${expenseTypes.length} типов расходов'));
    final customers = await _remote.fetchAllCustomers(key: key);

    onProgress?.call(SyncProgress(
        progress: 0.68,
        stage: 'Подключаемся к серверу...',
        detail: '${customers.length} покупателей'));
    final posInfo = await _remote.fetchPosInfo(key: key);

    onProgress
        ?.call(SyncProgress(progress: 0.73, stage: 'Сохраняем данные...'));
    await _localStore.replaceBootstrapData(
      posKey: key,
      deviceId: deviceId,
      cursorBefore: snapshotCursor,
      posInfo: posInfo,
      products: rawProducts,
      sales: rawSales,
      accounts: accounts,
      expenseTypes: expenseTypes,
      customers: customers,
    );

    onProgress?.call(
        const SyncProgress(progress: 0.82, stage: 'Применяем обновления...'));
    await pullOnce(
      key: key,
      deviceId: deviceId,
      initialCursor: snapshotCursor,
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
    void Function(SyncProgress progress)? onProgress,
  }) {
    return _pullFuture ??= _runPullOnce(
      key: key,
      deviceId: deviceId,
      initialCursor: initialCursor,
      onProgress: onProgress,
    ).whenComplete(() => _pullFuture = null);
  }

  Future<void> _runPullOnce({
    required String key,
    required String deviceId,
    int? initialCursor,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);
    var cursor =
        initialCursor ?? (await _localStore.loadSyncState(key))?.cursor ?? 0;
    var batchIndex = 0;

    while (true) {
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
  }

  Future<void> pushPending({
    required String key,
    required String deviceId,
    int limit = 5,
  }) {
    return _pushFuture ??= _runPushPending(
      key: key,
      deviceId: deviceId,
      limit: limit,
    ).whenComplete(() => _pushFuture = null);
  }

  Future<void> _runPushPending({
    required String key,
    required String deviceId,
    int limit = 5,
  }) async {
    await initialize();
    await _localStore.ensureSyncState(posKey: key, deviceId: deviceId);

    final records = await _localStore.claimPendingOperations(limit: limit);
    if (records.isEmpty) return;

    var ackedCount = 0;
    for (final record in records) {
      final result = await _sendClaimedRecord(
        key: key,
        deviceId: deviceId,
        record: record,
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

  Future<QueueOperationResult> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
    bool sendInBackground = false,
  }) async {
    final localNumber = await _localStore.nextLocalSaleNumber();
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_sale_id': sale.localId,
      'local_number': localNumber,
      if ((sale.posSessionId ?? '').trim().isNotEmpty)
        'pos_session_id': sale.posSessionId!.trim(),
      'date': _formatDate(sale.date),
      'total_amount': sale.totalAmount,
      'payment_method': sale.paymentMethod,
      'pos_id': sale.posId,
      'store_id': sale.storeId,
      'account_id': sale.accountId,
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
            },
          )
          .toList(growable: false),
    };

    await _localStore.insertSaleLocal(
      clientSaleId: sale.localId,
      localNumber: localNumber,
      payload: payload,
    );
    _notifySalesHistoryChanged();

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.sale,
      clientId: sale.localId,
      payload: payload,
      tryImmediateSend: !sendInBackground,
    );
  }

  Future<QueueOperationResult> createPayment({
    required String key,
    required String deviceId,
    required String posSessionId,
    required String accountId,
    required bool isExpense,
    required num amount,
    required DateTime date,
    String? expenseTypeId,
    String? userId,
  }) async {
    final clientId = 'payment_${_uuid.v7()}';
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_payment_id': clientId,
      'date': _formatDate(date),
      'is_expense': isExpense,
      'amount': amount.round(),
      'pos_session_id': posSessionId,
      'account_id': accountId,
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

  Future<QueueOperationResult> openSession({
    required String key,
    required String deviceId,
    required String userId,
    required DateTime openedAt,
  }) async {
    final clientId = 'session_${_uuid.v7()}';
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_session_id': clientId,
      'opened_at': _formatDate(openedAt),
      'user_id': userId,
    };

    await _localStore.upsertSession(
      clientSessionId: clientId,
      userId: userId,
      deviceId: deviceId,
      openedAt: openedAt,
    );

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.sessionOpen,
      clientId: clientId,
      payload: payload,
    );
  }

  Future<QueueOperationResult> closeSession({
    required String key,
    required String deviceId,
    required String clientSessionId,
    required String userId,
    required num closingCashAmount,
    required DateTime closedAt,
  }) async {
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_session_id': clientSessionId,
      'closed_at': _formatDate(closedAt),
      'user_id': userId,
      'closing_cash_amount': double.parse(closingCashAmount.toStringAsFixed(2)),
    };

    await _localStore.closeSessionLocal(
      clientSessionId: clientSessionId,
      closingCashAmount: closingCashAmount.toDouble(),
      closedAt: closedAt,
    );

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.sessionClose,
      clientId: clientSessionId,
      relatedClientId: clientSessionId,
      payload: payload,
    );
  }

  Future<QueueOperationResult> createRefund({
    required String key,
    required String deviceId,
    required String posSessionId,

    /// Server-assigned sale id. Pass empty string if the sale is not yet synced.
    required String saleId,

    /// Client-side client_sale_id. Required when [saleId] is empty (offline refund).
    String? clientSaleId,
    required int totalAmount,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    String? returnAccessKey,
  }) async {
    final clientId = 'refund_${_uuid.v7()}';
    final isOffline = saleId.isEmpty;
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'app_version': AppBuildInfo.appVersion,
      'client_refund_id': clientId,
      'pos_session_id': posSessionId,
      'date': _formatDate(date),
      if (!isOffline)
        'sale_id': saleId
      else if ((clientSaleId ?? '').isNotEmpty)
        'client_sale_id': clientSaleId!,
      'total_amount': totalAmount,
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

    await _localStore.enqueueOperation(
      id: _uuid.v7(),
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
        result: QueueSendResult.queued,
        type: type,
        clientId: clientId,
        payload: payload,
      );
    }

    if (_pushFuture != null) {
      return QueueOperationResult(
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
    return _ignoreBackgroundSyncErrors(
      pushPending(key: key, deviceId: deviceId, limit: limit),
    );
  }

  Future<void> _runBackgroundPull({
    required String key,
    required String deviceId,
  }) {
    return _ignoreBackgroundSyncErrors(
      pullOnce(key: key, deviceId: deviceId),
    );
  }

  Future<void> _ignoreBackgroundSyncErrors(Future<void> future) async {
    try {
      await future;
    } catch (_) {
      // Background sync is best-effort. Pending operations stay queued and
      // will be retried by the next timer tick or when connectivity returns.
    }
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
      await _localStore.markOperationAcked(record.id);
      if (record.type == OutboxOperationType.sessionOpen) {
        final serverSessionId = responseData?['id']?.toString().trim() ?? '';
        if (serverSessionId.isNotEmpty) {
          await _localStore.setSessionServerId(
            clientSessionId: record.clientId,
            serverSessionId: serverSessionId,
          );
        }
      }
      _markDedicatedTableSynced(record);
      return QueueOperationResult(
        result: QueueSendResult.sent,
        type: record.type,
        clientId: record.clientId,
        payload: payloadForSend,
      );
    } catch (error) {
      final errorCode = _remote.extractErrorCode(error);
      final errorMessage = _remote.extractErrorMessage(error);
      final errorDetails = _remote.extractErrorDetails(error);

      // Duplicate key: the operation already exists on the server — treat as success.
      if (errorCode == 'IDEMPOTENCY_CONFLICT') {
        await _localStore.markOperationAcked(record.id);
        _markDedicatedTableSynced(record);
        return QueueOperationResult(
          result: QueueSendResult.sent,
          type: record.type,
          clientId: record.clientId,
          payload: record.payload,
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
        result: QueueSendResult.manual,
        type: record.type,
        clientId: record.clientId,
        payload: record.payload,
        errorCode: manualCode,
        errorMessage: errorMessage,
      );
    }
  }

  Future<Map<String, dynamic>> _preparePayloadForSend(
      OutboxOperationRecord record) async {
    final payload = Map<String, dynamic>.from(record.payload);
    payload['app_version'] = AppBuildInfo.appVersion;
    switch (record.type) {
      case OutboxOperationType.sale:
      case OutboxOperationType.payment:
      case OutboxOperationType.refund:
        final rawSessionId =
            (payload['pos_session_id'] ?? '').toString().trim();
        if (rawSessionId.isNotEmpty) {
          final serverSessionId =
              await _localStore.resolveServerSessionId(rawSessionId);
          if ((serverSessionId ?? '').isNotEmpty) {
            payload['pos_session_id'] = serverSessionId;
          }
        }
      case OutboxOperationType.sessionOpen:
      case OutboxOperationType.sessionClose:
        break;
    }
    return payload;
  }

  void _markDedicatedTableSynced(OutboxOperationRecord record) {
    switch (record.type) {
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

  String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

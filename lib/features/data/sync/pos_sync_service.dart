import 'dart:async';

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

  Timer? _pullTimer;
  Timer? _pushTimer;
  Future<void>? _bootstrapFuture;
  Future<void>? _pullFuture;
  Future<void>? _pushFuture;

  Future<void> initialize() => _localStore.initialize();

  Future<void> dispose() async {
    _pullTimer?.cancel();
    _pushTimer?.cancel();
    await _localStore.close();
  }

  void startBackgroundLoops({
    required String key,
    required String deviceId,
  }) {
    _pullTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => pullOnce(key: key, deviceId: deviceId),
    );
    _pushTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => pushPending(key: key, deviceId: deviceId, limit: 5),
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

    onProgress?.call(const SyncProgress(progress: 0.05, stage: 'Получаем sync state'));
    final cursorBefore = await _remote.fetchServerCursor(key: key);

    onProgress?.call(const SyncProgress(progress: 0.12, stage: 'Загружаем POS'));
    final posInfo = await _remote.fetchPosInfo(key: key);

    onProgress?.call(const SyncProgress(progress: 0.28, stage: 'Загружаем товары'));
    final productsFuture = _remote.fetchAllProducts(key: key);
    onProgress?.call(const SyncProgress(progress: 0.42, stage: 'Загружаем счета'));
    final accountsFuture = _remote.fetchAllAccounts(key: key);
    onProgress?.call(const SyncProgress(progress: 0.56, stage: 'Загружаем типы расходов'));
    final expenseTypesFuture = _remote.fetchAllExpenseTypes(key: key);
    onProgress?.call(const SyncProgress(progress: 0.70, stage: 'Загружаем покупателей'));
    final customersFuture = _remote.fetchAllCustomers(key: key);

    final products = await productsFuture;
    final accounts = await accountsFuture;
    final expenseTypes = await expenseTypesFuture;
    final customers = await customersFuture;

    onProgress?.call(const SyncProgress(progress: 0.80, stage: 'Сохраняем snapshot'));
    await _localStore.replaceBootstrapData(
      posKey: key,
      deviceId: deviceId,
      cursorBefore: cursorBefore,
      posInfo: posInfo,
      products: products,
      accounts: accounts,
      expenseTypes: expenseTypes,
      customers: customers,
    );

    onProgress?.call(const SyncProgress(progress: 0.88, stage: 'Применяем дельту'));
    await pullOnce(
      key: key,
      deviceId: deviceId,
      initialCursor: cursorBefore,
      onProgress: (progress) {
        final normalized = 0.88 + (progress.progress * 0.11);
        onProgress?.call(
          SyncProgress(
            progress: normalized.clamp(0.88, 0.99),
            stage: progress.stage,
            detail: progress.detail,
          ),
        );
      },
    );

    onProgress?.call(const SyncProgress(progress: 1, stage: 'Синхронизация завершена'));
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
    var cursor = initialCursor ?? (await _localStore.loadSyncState(key))?.cursor ?? 0;
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
            detail: 'batch ${batchIndex}',
          ),
        );
        await _localStore.applyPullBatch(
          posKey: key,
          changes: batch.items,
          nextCursor: batch.nextCursor,
        );
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

    var hadAcked = false;
    for (final record in records) {
      final result = await _sendClaimedRecord(
        key: key,
        deviceId: deviceId,
        record: record,
      );
      if (result.result == QueueSendResult.sent) {
        hadAcked = true;
      }
      if (result.result == QueueSendResult.queued) {
        break;
      }
    }

    if (hadAcked) {
      await _localStore.touchLastPush(key);
      await pullOnce(key: key, deviceId: deviceId);
    }
  }

  Future<QueueOperationResult> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
  }) async {
    final localNumber = await _localStore.nextLocalSaleNumber();
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'client_sale_id': sale.localId,
      'local_number': localNumber,
      'date': _formatDate(sale.date),
      'total_amount': sale.totalAmount,
      'payment_method': sale.paymentMethod,
      'pos_id': sale.posId,
      'store_id': sale.storeId,
      'account_id': sale.accountId,
      'user_id': sale.userId,
      if ((sale.customerId ?? '').trim().isNotEmpty) 'customer_id': sale.customerId!.trim(),
      'items': sale.items
          .map(
            (item) => {
              'product_id': item.productId,
              'quantity': item.quantity,
              'price': item.price,
              'total_price': item.totalPrice,
            },
          )
          .toList(growable: false),
    };

    return _queueAndTrySend(
      key: key,
      deviceId: deviceId,
      type: OutboxOperationType.sale,
      clientId: sale.localId,
      payload: payload,
    );
  }

  Future<QueueOperationResult> createPayment({
    required String key,
    required String deviceId,
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
      'client_payment_id': clientId,
      'date': _formatDate(date),
      'is_expense': isExpense,
      'amount': amount.round(),
      'account_id': accountId,
      if ((expenseTypeId ?? '').trim().isNotEmpty) 'expense_type_id': expenseTypeId!.trim(),
      if ((userId ?? '').trim().isNotEmpty) 'created_by_id': userId!.trim(),
    };

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
      'client_session_id': clientId,
      'opened_at': _formatDate(openedAt),
      'user_id': userId,
    };

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
      'client_session_id': clientSessionId,
      'closed_at': _formatDate(closedAt),
      'user_id': userId,
      'closing_cash_amount': closingCashAmount.round(),
    };

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
    required String saleId,
    required int totalAmount,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    String? returnAccessKey,
  }) async {
    final clientId = 'refund_${_uuid.v7()}';
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'client_refund_id': clientId,
      'date': _formatDate(date),
      'sale_id': saleId,
      'total_amount': totalAmount,
      'items': items,
      if ((returnAccessKey ?? '').trim().isNotEmpty) 'return_access_key': returnAccessKey!.trim(),
    };

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
      unawaited(pullOnce(key: key, deviceId: deviceId));
    }
    return result;
  }

  Future<QueueOperationResult> _sendClaimedRecord({
    required String key,
    required String deviceId,
    required OutboxOperationRecord record,
  }) async {
    try {
      await _remote.sendOperation(
        type: record.type,
        key: key,
        payload: {
          ...record.payload,
          'device_id': deviceId,
        },
      );
      await _localStore.markOperationAcked(record.id);
      return QueueOperationResult(
        result: QueueSendResult.sent,
        type: record.type,
        clientId: record.clientId,
        payload: record.payload,
      );
    } catch (error) {
      final errorCode = _remote.extractErrorCode(error);
      final errorMessage = _remote.extractErrorMessage(error);

      if (_remote.isRetryable(error)) {
        await _localStore.markOperationPending(
          operationId: record.id,
          errorCode: errorCode,
          errorMessage: errorMessage,
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

      final manualCode =
          _remote.isManualErrorCode(errorCode) ? errorCode : 'MANUAL_REVIEW_REQUIRED';
      await _localStore.markOperationManual(
        operationId: record.id,
        errorCode: manualCode,
        errorMessage: errorMessage,
        payload: record.payload,
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

  String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

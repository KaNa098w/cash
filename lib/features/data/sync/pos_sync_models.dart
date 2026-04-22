import 'dart:convert';

enum OutboxOperationType {
  sale,
  payment,
  refund,
  sessionOpen,
  sessionClose,
}

extension OutboxOperationTypeX on OutboxOperationType {
  String get value => switch (this) {
        OutboxOperationType.sale => 'sale',
        OutboxOperationType.payment => 'payment',
        OutboxOperationType.refund => 'refund',
        OutboxOperationType.sessionOpen => 'session_open',
        OutboxOperationType.sessionClose => 'session_close',
      };

  String get label => switch (this) {
        OutboxOperationType.sale => 'Продажа',
        OutboxOperationType.payment => 'Платеж',
        OutboxOperationType.refund => 'Возврат',
        OutboxOperationType.sessionOpen => 'Открытие смены',
        OutboxOperationType.sessionClose => 'Закрытие смены',
      };

  static OutboxOperationType? fromValue(String raw) {
    final value = raw.trim().toLowerCase();
    for (final item in OutboxOperationType.values) {
      if (item.value == value) return item;
    }
    return null;
  }
}

enum OutboxOperationStatus {
  pending,
  sending,
  acked,
  manual,
}

extension OutboxOperationStatusX on OutboxOperationStatus {
  String get value => switch (this) {
        OutboxOperationStatus.pending => 'pending',
        OutboxOperationStatus.sending => 'sending',
        OutboxOperationStatus.acked => 'acked',
        OutboxOperationStatus.manual => 'manual',
      };

  static OutboxOperationStatus? fromValue(String raw) {
    final value = raw.trim().toLowerCase();
    for (final item in OutboxOperationStatus.values) {
      if (item.value == value) return item;
    }
    return null;
  }
}

enum QueueSendResult {
  sent,
  queued,
  manual,
}

enum QueuePushStage {
  sending,
  success,
  queued,
  error,
}

class QueuePushEvent {
  const QueuePushEvent({
    required this.operationId,
    required this.type,
    required this.clientId,
    required this.title,
    required this.stage,
    this.message,
  });

  final String operationId;
  final OutboxOperationType type;
  final String clientId;
  final String title;
  final QueuePushStage stage;
  final String? message;
}

class QueueOperationResult {
  const QueueOperationResult({
    required this.operationId,
    required this.result,
    required this.type,
    required this.clientId,
    required this.payload,
    this.errorCode,
    this.errorMessage,
  });

  final String operationId;
  final QueueSendResult result;
  final OutboxOperationType type;
  final String clientId;
  final Map<String, dynamic> payload;
  final String? errorCode;
  final String? errorMessage;
}

class SyncProgress {
  const SyncProgress({
    required this.progress,
    required this.stage,
    this.detail,
  });

  final double progress;
  final String stage;
  final String? detail;
}

class SyncStateSnapshot {
  const SyncStateSnapshot({
    required this.posKey,
    required this.deviceId,
    required this.cursor,
    this.lastBootstrapAt,
    this.lastPullAt,
    this.lastPushAt,
    this.lastError,
  });

  final String posKey;
  final String deviceId;
  final int cursor;
  final DateTime? lastBootstrapAt;
  final DateTime? lastPullAt;
  final DateTime? lastPushAt;
  final String? lastError;
}

class SnapshotStatus {
  const SnapshotStatus({
    required this.status,
    required this.cursor,
    this.url,
    this.expiresAt,
  });

  final String status; // 'pending', 'ready', 'failed'
  final int cursor;
  final String? url;
  final DateTime? expiresAt;

  bool get isPending => status == 'pending';
  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
}

class SyncPullChange {
  const SyncPullChange({
    required this.entity,
    required this.action,
    this.payload,
    this.targetId,
    this.raw,
  });

  final String entity;
  final String action;
  final Map<String, dynamic>? payload;
  final String? targetId;
  final dynamic raw;
}

class SyncPullBatch {
  const SyncPullBatch({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<SyncPullChange> items;
  final int nextCursor;
  final bool hasMore;
}

class OutboxOperationRecord {
  const OutboxOperationRecord({
    required this.id,
    required this.type,
    required this.clientId,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    this.relatedClientId,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  final String id;
  final OutboxOperationType type;
  final String clientId;
  final String? relatedClientId;
  final Map<String, dynamic> payload;
  final OutboxOperationStatus status;
  final int retryCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class QueueListItem {
  const QueueListItem({
    required this.id,
    required this.type,
    required this.clientId,
    required this.status,
    required this.createdAt,
    this.title,
    this.subtitle,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final OutboxOperationType type;
  final String clientId;
  final OutboxOperationStatus status;
  final DateTime createdAt;
  final String? title;
  final String? subtitle;
  final String? errorCode;
  final String? errorMessage;
}

class QueueItemDetails {
  const QueueItemDetails({
    required this.id,
    required this.type,
    required this.clientId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.payload,
    this.title,
    this.subtitle,
    this.errorCode,
    this.errorMessage,
    this.lastErrorDetails,
  });

  final String id;
  final OutboxOperationType type;
  final String clientId;
  final OutboxOperationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;
  final String? title;
  final String? subtitle;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? lastErrorDetails;
}

class LocalExpenseType {
  const LocalExpenseType({
    required this.id,
    required this.name,
    required this.rawJson,
  });

  final String id;
  final String name;
  final Map<String, dynamic> rawJson;
}

class LocalCustomer {
  const LocalCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.rawJson,
  });

  final String id;
  final String name;
  final String phone;
  final Map<String, dynamic> rawJson;
}

class ShiftReportItem {
  const ShiftReportItem({
    required this.name,
    required this.quantity,
    required this.totalSum,
  });

  final String name;
  final num quantity;
  final num totalSum;
}

class ShiftReportData {
  const ShiftReportData({
    required this.sessionId,
    required this.openedAt,
    required this.closedAt,
    required this.openingCashAmount,
    required this.closingCashAmount,
    required this.salesCount,
    required this.cashTotal,
    required this.cardTotal,
    required this.transferTotal,
    required this.creditTotal,
    required this.grandTotal,
    required this.refundsTotal,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.expectedCashAmount,
    required this.items,
  });

  final String sessionId;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final num openingCashAmount;
  final num closingCashAmount;
  final int salesCount;
  final num cashTotal;
  final num cardTotal;
  final num transferTotal;
  final num creditTotal;
  final num grandTotal;
  final num refundsTotal;
  final num incomeTotal;
  final num expenseTotal;
  final num expectedCashAmount;
  final List<ShiftReportItem> items;
}

class ShiftClosureSummaryData {
  const ShiftClosureSummaryData({
    required this.sessionId,
    required this.openingCashAmount,
    required this.cashSalesTotal,
    required this.cardSalesTotal,
    required this.transferSalesTotal,
    required this.creditSalesTotal,
    required this.refundsTotal,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.expectedCashAmount,
    required this.totalSalesAmount,
  });

  final String sessionId;
  final num openingCashAmount;
  final num cashSalesTotal;
  final num cardSalesTotal;
  final num transferSalesTotal;
  final num creditSalesTotal;
  final num refundsTotal;
  final num incomeTotal;
  final num expenseTotal;
  final num expectedCashAmount;
  final num totalSalesAmount;
}

class LocalAccount {
  const LocalAccount({
    required this.id,
    required this.name,
    this.type,
    this.visibleToPos = true,
  });

  final String id;
  final String name;
  final String? type;
  final bool visibleToPos;

  bool get isCash => type?.toLowerCase() == 'cash';
}

Map<String, dynamic> decodeJsonMap(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  return <String, dynamic>{};
}

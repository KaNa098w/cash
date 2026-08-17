import 'dart:developer' as developer;

import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';

class SaleRepositoryImpl implements SaleRepository {
  SaleRepositoryImpl(Object _, Object __, this._syncService);

  final PosSyncService _syncService;

  @override
  Future<CreateSaleOutcome> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
    required List<Map<String, dynamic>> payments,
    bool requireOnline = false,
  }) async {
    try {
      final queueResult = await _syncService.createSale(
        key: key,
        deviceId: deviceId,
        sale: sale,
        payments: payments,
        sendInBackground: !requireOnline,
        requireOnline: requireOnline,
      );

      final localNumber = queueResult.payload['local_number']?.toString() ?? '';
      final printedSale = sale.copyWith(number: localNumber);

      return CreateSaleOutcome(
        result: requireOnline
            ? (queueResult.result == QueueSendResult.sent
                ? CreateSaleResult.sent
                : CreateSaleResult.rejected)
            : (queueResult.result == QueueSendResult.manual
                ? CreateSaleResult.rejected
                : CreateSaleResult.sent),
        sale: printedSale,
        errorMessage: queueResult.errorMessage,
        responseData: queueResult.responseData,
        retryScheduled: queueResult.result == QueueSendResult.queued,
      );
    } catch (error, stackTrace) {
      developer.log(
        'createSale failed',
        name: 'SaleRepositoryImpl',
        error: error,
        stackTrace: stackTrace,
      );
      return CreateSaleOutcome(
        result: CreateSaleResult.rejected,
        sale: sale,
        errorMessage: error.toString(),
      );
    }
  }

  @override
  Future<void> syncPendingSales({
    required String key,
    required String deviceId,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) return;

    await _syncService.pushPending(
      key: safeKey,
      deviceId: deviceId,
      limit: 10,
    );
  }
}

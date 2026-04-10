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
  }) async {
    try {
      final queueResult = await _syncService.createSale(
        key: key,
        deviceId: deviceId,
        sale: sale,
        sendInBackground: true,
      );

      final localNumber = queueResult.payload['local_number']?.toString() ?? '';
      final printedSale = sale.copyWith(number: localNumber);

      return CreateSaleOutcome(
        result: queueResult.result == QueueSendResult.manual
            ? CreateSaleResult.rejected
            : CreateSaleResult.sent,
        sale: printedSale,
      );
    } catch (_) {
      return CreateSaleOutcome(result: CreateSaleResult.rejected, sale: sale);
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

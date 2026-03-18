import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

class SaleLocalDataSource {
  Future<List<SaleModel>> loadPending() {
    return sl<PosSyncService>().loadPendingSales();
  }

  Future<void> enqueue(SaleModel sale) async {}

  Future<void> removeFromQueueByLocalId(String localId) async {}

  Future<void> clear() {
    return sl<PosSyncService>().clearAllLocalData();
  }
}

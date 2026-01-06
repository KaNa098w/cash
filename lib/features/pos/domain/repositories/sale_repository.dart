// lib/features/sales/domain/repositories/sale_repository.dart
import 'package:pos_desktop_clean/core/models/sale_model.dart';

enum CreateSaleResult { sent, queued, rejected }

abstract class SaleRepository {
  Future<CreateSaleResult> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
  });

  Future<void> syncPendingSales({
    required String key,
    required String deviceId,
  });
}

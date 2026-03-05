// lib/features/sales/domain/repositories/sale_repository.dart
import 'package:leemon_app/core/models/sale_model.dart';

enum CreateSaleResult { sent, queued, rejected }

class CreateSaleOutcome {
  const CreateSaleOutcome({
    required this.result,
    required this.sale,
  });

  final CreateSaleResult result;
  final SaleModel sale;
}

abstract class SaleRepository {
  Future<CreateSaleOutcome> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
  });

  Future<void> syncPendingSales({
    required String key,
    required String deviceId,
  });
}

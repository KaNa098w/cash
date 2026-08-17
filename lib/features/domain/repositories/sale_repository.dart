// lib/features/sales/domain/repositories/sale_repository.dart
import 'package:leemon_app/core/models/sale_model.dart';

enum CreateSaleResult { sent, queued, rejected }

class CreateSaleOutcome {
  const CreateSaleOutcome({
    required this.result,
    required this.sale,
    this.errorMessage,
    this.responseData,
    this.retryScheduled = false,
  });

  final CreateSaleResult result;
  final SaleModel sale;
  final String? errorMessage;
  final Map<String, dynamic>? responseData;
  final bool retryScheduled;
}

abstract class SaleRepository {
  Future<CreateSaleOutcome> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
    required List<Map<String, dynamic>> payments,
    bool requireOnline = false,
  });

  Future<void> syncPendingSales({
    required String key,
    required String deviceId,
  });
}

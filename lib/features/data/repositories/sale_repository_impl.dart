// lib/features/sales/data/repositories/sale_repository_impl.dart
import 'package:dio/dio.dart';
import 'package:leemon_app/core/di/utils/dio_error_utils.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';

import '../datasources/sale_local_datasource.dart';

class SaleRepositoryImpl implements SaleRepository {
  SaleRepositoryImpl(this._remote, this._local);

  final SaleRemoteDataSource _remote;
  final SaleLocalDataSource _local;

  @override
  Future<CreateSaleResult> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
  }) async {
    try {
      await _remote.createSale(key: key, deviceId: deviceId, sale: sale);
      return CreateSaleResult.sent;
    } on DioException catch (e) {
      if (shouldQueueOnDioError(e)) {
        await _local.enqueue(sale);
        return CreateSaleResult.queued;
      }
      return CreateSaleResult.rejected;
    } catch (_) {
      return CreateSaleResult.rejected;
    }
  }

  @override
  Future<void> syncPendingSales({
    required String key,
    required String deviceId,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) return;

    final pending = await _local.loadPending();
    if (pending.isEmpty) return;

    for (final sale in pending) {
      try {
        await _remote.createSale(key: safeKey, deviceId: deviceId, sale: sale);
        await _local.removeFromQueueByLocalId(sale.localId);
      } on DioException catch (e) {
        if (shouldQueueOnDioError(e)) break;
        await _local.removeFromQueueByLocalId(sale.localId);
        continue;
      } catch (_) {
        break;
      }
    }
  }
}

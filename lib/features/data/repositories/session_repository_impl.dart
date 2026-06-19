import 'package:leemon_app/features/data/datasources/session_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';

class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl(this._remoteDataSource, this._syncService);

  final SessionRemoteDataSource _remoteDataSource;
  final PosSyncService _syncService;

  @override
  Future<String> openSession({
    required String key,
    required String deviceId,
    required String userId,
  }) async {
    final result = await _syncService.openSession(
      key: key,
      deviceId: deviceId,
      userId: userId,
    );
    return result.clientId;
  }

  @override
  Future<QueueSendResult> closeSession({
    required String key,
    required String deviceId,
    required String sessionId,
    required String userId,
    required num closingCashAmount,
    String? comment,
  }) async {
    final closedAt = DateTime.now();
    final remoteSessionId = await _syncService.resolveServerSessionId(
      sessionId,
    );
    if (remoteSessionId.startsWith('session_')) {
      throw Exception(
        'closeSession: server session id is missing for $sessionId',
      );
    }

    await _remoteDataSource.closeSession(
      key: key,
      sessionId: remoteSessionId,
      userId: userId,
      deviceId: deviceId,
      closingCashAmount: closingCashAmount,
      comment: comment,
      closedAt: closedAt,
    );

    await _syncService.registerClosedSession(
      sessionId: sessionId,
      closingCashAmount: closingCashAmount.toDouble(),
      closedAt: closedAt,
    );

    return QueueSendResult.sent;
  }
}

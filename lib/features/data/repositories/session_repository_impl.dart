import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/session_repository.dart';

class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl(Object _, this._syncService);

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
      openedAt: DateTime.now(),
    );

    if (result.result == QueueSendResult.manual) {
      throw Exception(result.errorMessage ?? 'Не удалось открыть смену');
    }

    return result.clientId;
  }

  @override
  Future<void> closeSession({
    required String key,
    required String deviceId,
    required String sessionId,
    required String userId,
    required num closingCashAmount,
  }) async {
    final result = await _syncService.closeSession(
      key: key,
      deviceId: deviceId,
      clientSessionId: sessionId,
      userId: userId,
      closingCashAmount: closingCashAmount,
      closedAt: DateTime.now(),
    );

    if (result.result == QueueSendResult.manual) {
      throw Exception(result.errorMessage ?? 'Не удалось закрыть смену');
    }
  }
}

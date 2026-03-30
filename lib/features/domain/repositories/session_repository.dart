import 'package:leemon_app/features/data/sync/pos_sync_models.dart';

abstract class SessionRepository {
  Future<String> openSession({
    required String key,
    required String deviceId,
    required String userId,
  });

  Future<QueueSendResult> closeSession({
    required String key,
    required String deviceId,
    required String sessionId,
    required String userId,
    required num closingCashAmount,
  });
}

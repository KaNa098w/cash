abstract class SessionRepository {
  Future<String> openSession({
    required String key,
    required String deviceId,
    required String userId,
  });

  Future<void> closeSession({
    required String key,
    required String deviceId,
    required String sessionId,
    required String userId,
    required num closingCashAmount,
  });
}

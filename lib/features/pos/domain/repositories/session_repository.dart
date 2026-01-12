abstract class SessionRepository {
  Future<String> openSession({
    required String key,
    required String userId,
    required num openingCashAmount,
  });

  Future<void> closeSession({
    required String key,
    required String sessionId,
    required String userId,
    required num closingCashAmount,
  });
}

import 'package:pos_desktop_clean/features/pos/data/datasources/session_remote_datasource.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/session_repository.dart';

class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl(this.remote);

  final SessionRemoteDataSource remote;

  @override
  Future<String> openSession({
    required String key,
    required String userId,
    required num openingCashAmount,
  }) {
    return remote.openSession(
      key: key,
      userId: userId,
      openingCashAmount: openingCashAmount,
    );
  }

  @override
  Future<void> closeSession({
    required String key,
    required String sessionId,
    required String userId,
    required num closingCashAmount,
  }) {
    return remote.closeSession(
      key: key,
      sessionId: sessionId,
      userId: userId,
      closingCashAmount: closingCashAmount,
    );
  }
}

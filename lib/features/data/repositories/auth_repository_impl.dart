import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';
import 'package:pos_desktop_clean/features/domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);
  final AuthRemoteDataSource _remote;

  @override
  Future<PosProvisionResponse> provisionPos({
    required String key,
    required String deviceId,
  }) {
    return _remote.provisionPos(key: key, deviceId: deviceId);
  }
}

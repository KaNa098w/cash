import 'package:leemon_app/core/models/pos_provision_response.dart';

abstract class AuthRepository {
  Future<PosProvisionResponse> provisionPos({
    required String key,
    required String deviceId,
  });
}
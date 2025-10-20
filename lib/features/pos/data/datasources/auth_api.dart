import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pos_desktop_clean/core/http/api_client.dart';
import 'package:pos_desktop_clean/features/pos/data/dto/login_request_dto.dart';
import 'package:pos_desktop_clean/features/pos/data/dto/login_response_dto.dart';

class AuthApi {
  final ApiClient client;
  AuthApi(this.client);

  // dev-хост из твоих заметок
  static const _provisioningHost = 'https://kfmzyjghfw.dev.aloteq.dev';
  // секретный заголовок обязателен (dev)
  static const _secretHeaderKey = 'xgkqkpfcvq';
  static const _secretHeaderVal = 'zjqvxmnrbttyslcrlqnf';

  Future<LoginResponseDto> login(LoginRequestDto dto) async {
    final uri = Uri.parse('$_provisioningHost/api/v1/login');
    final res = await client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        _secretHeaderKey: _secretHeaderVal,
      },
      body: jsonEncode(dto.toJson()),
      timeout: const Duration(seconds: 15),
    );

    if (res.statusCode == 418) {
      throw const ApiException('Неверный секретный заголовок (418).');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Ошибка логина: ${res.statusCode} ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return LoginResponseDto.fromJson(json);
  }
}

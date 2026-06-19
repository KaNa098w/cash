import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

class SessionRemoteDataSource {
  final Dio _dio;
  SessionRemoteDataSource(this._dio);

  Future<String> openSession({
    required String key,
    required String userId,
    required String deviceId,
  }) async {
    final safeKey = key.trim();

    final resp = await _dio.post(
      '/organizations/pos/$safeKey/open-session',
      data: {
        'user_id': userId,
        'device_id': deviceId,
      },
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('openSession: invalid response format (expected Map)');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('openSession: invalid "data" (expected Map)');
    }

    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw Exception('openSession: missing data.id');
    }

    return id;
  }

  Future<void> closeSession({
    required String key,
    required String sessionId,
    required String userId,
    required String deviceId,
    required num closingCashAmount,
    String? comment,
    DateTime? closedAt,
  }) async {
    final safeKey = key.trim();
    final cleanSessionId = sessionId.trim();
    final isClientSession = cleanSessionId.startsWith('session_');
    final cleanComment = (comment ?? '').trim();
    final data = <String, dynamic>{
      if (isClientSession) ...{
        'client_session_id': cleanSessionId,
        'closed_at': DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(closedAt ?? DateTime.now()),
      } else
        'session_id': cleanSessionId,
      'user_id': userId,
      'device_id': deviceId,
      'closing_cash_amount': double.parse(
        closingCashAmount.toStringAsFixed(2),
      ),
      if (cleanComment.isNotEmpty) 'comment': cleanComment,
    };

    await _dio.put(
      '/organizations/pos/$safeKey/close-session',
      data: data,
    );
  }
}

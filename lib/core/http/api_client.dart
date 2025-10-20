import 'package:http/http.dart' as http;

class ApiClient {
  final http.Client _client;
  ApiClient(this._client);

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    final f = _client.post(url, headers: headers, body: body);
    return timeout != null ? f.timeout(timeout) : f;
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
}

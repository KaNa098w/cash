class AuthResult {
  final String accessToken;
  final String refreshToken;
  final Uri apiBaseUrl;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.apiBaseUrl,
  });
}

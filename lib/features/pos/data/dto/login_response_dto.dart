class LoginResponseDto {
  final String accessToken;
  final String refreshToken;
  final String apiBaseUrl;

  LoginResponseDto({
    required this.accessToken,
    required this.refreshToken,
    required this.apiBaseUrl,
  });

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) {
    return LoginResponseDto(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      apiBaseUrl: json['api_base_url'] as String,
    );
  }
}

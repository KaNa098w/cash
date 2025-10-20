class LoginRequestDto {
  final String email;
  final String password;
  const LoginRequestDto({required this.email, required this.password});

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
  };
}

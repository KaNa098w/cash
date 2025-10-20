import 'package:flutter/material.dart';

class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Вход в кассу', style: t.headlineMedium!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Используй учётные данные сотрудника', style: t.bodyMedium!.copyWith(color: Colors.black54)),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';

class UsersStep extends StatelessWidget {
  final ThemeData theme;
  final PosProvisionResponse provision;
  final VoidCallback onChangeKey;
  final ValueChanged<PosUser> onSelect;

  const UsersStep({
    super.key,
    required this.theme,
    required this.provision,
    required this.onChangeKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final users = provision.users;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Касса: ${provision.name}',
                style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            // TextButton(onPressed: onChangeKey, child: const Text('Сменить ключ')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Выбери пользователя для входа:',
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (users.isEmpty)
          Text(
            'Пользователи не найдены',
            style: theme.textTheme.bodyMedium!.copyWith(color: Colors.redAccent),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final u = users[i];
                return UserTile(user: u, onTap: () => onSelect(u));
              },
            ),
          ),
        const SizedBox(height: 10),
        Text(
          '© ${DateTime.now().year} POS Desktop',
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

class UserTile extends StatelessWidget {
  final PosUser user;
  final VoidCallback onTap;

  const UserTile({super.key, required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = user.name.isNotEmpty ? user.name.trim().characters.first : 'U';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x22000000)),
          color: Colors.white,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFEFF6FF),
              child: Text(
                letter,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.emailAddress.isEmpty ? '—' : user.emailAddress,
                    style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

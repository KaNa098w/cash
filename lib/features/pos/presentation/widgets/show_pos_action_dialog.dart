import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import 'package:pos_desktop_clean/features/pos/presentation/state/auth_cubit.dart';
import 'package:window_manager/window_manager.dart';

Future<void> showPosActionsDialog(BuildContext context) {
  final actions = <_PosAction>[
    _PosAction('ВЫХОД ИЗ ПРОГРАММЫ', () {
      final router = GoRouter.of(context); // возьми router ДО pop()
      context.read<AuthCubit>().signOut(); // 1) снять авторизацию

      Navigator.of(context, rootNavigator: true).pop(); // 2) закрыть диалог

      // 3) можно не вызывать, redirect сам уведёт на /login.
      // Но если хочешь явно:
      Future.microtask(() => router.go('/login'));
    }),
    _PosAction('ЗАБЛОКИРОВАТЬ КАССУ', () {/* TODO */}),
    _PosAction('РАСПЕЧАТАТЬ ЧЕК\nПОСЛЕДНЕЙ ПРОДАЖИ', () {/* TODO */}),
    _PosAction('СИНХРОНИЗАЦИЯ', () {/* TODO */}),
    _PosAction('СВЕРНУТЬ', () async {
      // закрываем диалог, чтобы не держать route поверх
      Navigator.of(context, rootNavigator: true).pop();

      // только desktop
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await windowManager.minimize();
      }
    }),
    _PosAction('ПРОВЕРИТЬ ОБНОВЛЕНИЕ', () {/* TODO */}),
    _PosAction('ВЗНОС В КАССУ', () {/* TODO */}),
    _PosAction('РАСХОД', () {/* TODO */}),
    _PosAction('СДАТЬ СМЕНУ', () {/* TODO */}),
    _PosAction('ПРИНТЕР', () {/* TODO */}),
  ];

  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: AppTheme.greyB,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: LayoutBuilder(
              builder: (context, c) {
                // 4 колонки при ширине > 780, иначе 3
                final cols = c.maxWidth > 780 ? 4 : 3;
                return Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(6),
                        physics: NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 2.1,
                        ),
                        itemCount: actions.length,
                        itemBuilder: (context, i) =>
                            _ActionTile(action: actions[i]),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 240,
                        height: 64,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD45F4F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          child: const Text(
                            'ЗАКРЫТЬ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

class _PosAction {
  final String title;
  final VoidCallback onTap;
  const _PosAction(this.title, this.onTap);
}

class _ActionTile extends StatelessWidget {
  final _PosAction action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              action.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

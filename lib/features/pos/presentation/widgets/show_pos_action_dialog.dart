import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/di/api/service_locator.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';
import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/payment_remote_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/product_local_datasource.dart';
import 'package:pos_desktop_clean/features/pos/data/utils/app_theme.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_state.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/close_shift_bottom.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/deposit_to_cash_sheel.dart';

import 'package:window_manager/window_manager.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/close_shift_bottom.dart';

Future<void> showPosActionsDialog(BuildContext context) {
  final actions = <_PosAction>[
    _PosAction('ВЫХОД ИЗ ПРОГРАММЫ', () {
      Navigator.of(context, rootNavigator: true).pop();
      context.read<AuthCubit>().lockToCashiers();
    }),
    _PosAction('ЗАБЛОКИРОВАТЬ КАССУ', () {
      Navigator.of(context, rootNavigator: true).pop();
      context.read<AuthCubit>().lockToCashiers();
    }),
    _PosAction('РАСПЕЧАТАТЬ ЧЕК\nПОСЛЕДНЕЙ ПРОДАЖИ', () {/* TODO */}),
    _PosAction(
      'СИНХРОНИЗАЦИЯ',
      () async {
        Navigator.of(context, rootNavigator: true).pop(); // закрыть диалог

        // 1) берём key (обязательно)

        final local = sl<ProductLocalDataSource>();
        await local.clear(); // очистили Hive
        final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';

        await context.read<ProductsCubit>().loadFirstPage(
              key: key, // <-- замени на своё поле
              forceRefresh: true,
            );
      },
    ),
    _PosAction('СВЕРНУТЬ', () async {
      Navigator.of(context, rootNavigator: true).pop();

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
        await windowManager.setMinimizable(true);
        await windowManager.minimize();
        await windowManager.setMinimizable(false);
      }
    }),
    _PosAction('ПРОВЕРИТЬ ОБНОВЛЕНИЕ', () {/* TODO */}),
    _PosAction('ВЗНОС В КАССУ', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await showDepositToCashSheet(context, true);
    }),
    _PosAction('РАСХОД', () async {
      Navigator.of(context, rootNavigator: true).pop();
      await showDepositToCashSheet(context, false);
    }),
    _PosAction('СДАТЬ СМЕНУ', () async {
      Navigator.of(context, rootNavigator: true)
          .pop(); // закрыть actions dialog
      await showCloseShiftSheet(context); // открыть sheet с клавой
    }),
    _PosAction('ПРИНТЕР', () {/* TODO */}),
  ];

  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: ThemeColors.greyB,
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

Future<num?> _askCashAmount(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmText,
}) async {
  final ctrl = TextEditingController();
  final focus = FocusNode();

  num? parseAmount(String s) {
    final v = s.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }

  final result = await showDialog<num?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          focusNode: focus,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hint,
          ),
          onSubmitted: (_) {
            final amount = parseAmount(ctrl.text);
            if (amount == null || amount < 0) return;
            Navigator.of(ctx).pop(amount);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final amount = parseAmount(ctrl.text);
              if (amount == null || amount < 0) return;
              Navigator.of(ctx).pop(amount);
            },
            child: Text(confirmText),
          ),
        ],
      );
    },
  );

  ctrl.dispose();
  focus.dispose();

  return result;
}

class _PosAction {
  final String title;
  final FutureOr<void> Function() onTap;
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
        onTap: () async => action.onTap(),
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

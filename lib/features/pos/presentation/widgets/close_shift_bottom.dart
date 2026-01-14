import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/amount_keypad.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/auth/auth_bloc/auth_state.dart';

Future<void> showCloseShiftSheet(BuildContext context) async {
  final tokenProvider = context.read<AuthTokenProvider>();

  if (!tokenProvider.hasShiftId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Смена не открыта')),
    );
    return;
  }

  if (!tokenProvider.hasActiveUserId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не определён кассир (userId)')),
    );
    return;
  }

  final closed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CloseShiftSheet(),
  );

  // ✅ навигация только СНАРУЖИ шторки
  if (closed == true && context.mounted) {
    context.go('/login');
    // или если хочешь просто блокировку без /login:
    // context.read<AuthCubit>().lockToCashiers();
  }
}

class _CloseShiftSheet extends StatefulWidget {
  const _CloseShiftSheet();

  @override
  State<_CloseShiftSheet> createState() => _CloseShiftSheetState();
}

class _CloseShiftSheetState extends State<_CloseShiftSheet> {
  final _ctrl = TextEditingController(text: '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  num? _parseAmount(String s) {
    final v = s.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }

  Future<void> _submit() async {
    final amount = _parseAmount(_ctrl.text);
    if (amount == null || amount < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректную сумму')),
      );
      return;
    }

    // ✅ отправляем закрытие смены, дальше слушатель поймает AuthShiftClosed
    await context.read<AuthCubit>().closeSessionWithCash(
          closingCashAmount: amount,
        );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return BlocConsumer<AuthCubit, AuthState>(
      listenWhen: (prev, curr) =>
          curr is AuthFailure || curr is AuthShiftClosed,
      listener: (context, state) {
        if (state is AuthFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }

        if (state is AuthShiftClosed) {
          if (!mounted) return;
          Navigator.of(context).pop(true); // ✅ вернуть успех наружу
        }
      },

      // ✅ чтобы UI не прыгал от промежуточных стейтов (AuthProvisioned/AuthInitial)
      buildWhen: (prev, curr) =>
          curr is AuthClosingSession ||
          curr is AuthFailure ||
          prev is AuthClosingSession ||
          prev is AuthFailure,

      builder: (context, state) {
        final isLoading = state is AuthClosingSession;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF374151),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Сдать смену',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _ctrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      labelText: 'Сумма в кассе',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => isLoading ? null : _submit(),
                  ),

                  const SizedBox(height: 12),

                  AmountKeypad(
                    text: _ctrl.text,
                    onChanged: (t) {
                      setState(() {
                        _ctrl.text = t;
                        _ctrl.selection =
                            TextSelection.collapsed(offset: t.length);
                      });
                    },
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                  color: Colors.white.withOpacity(.35)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Отмена'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: isLoading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD45F4F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'СДАТЬ СМЕНУ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .4,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

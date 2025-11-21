// top_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

import '../state/pos_cubit.dart';
import 'show_pos_action_dialog.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF262B35),
      height: 57,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
        child: BlocBuilder<PosCubit, PosState>(
          buildWhen: (p, n) =>
              p.tickets != n.tickets ||
              p.activeTicketId != n.activeTicketId ||
              p.isHistoryMode != n.isHistoryMode,
          builder: (context, state) {
            final cubit = context.read<PosCubit>();
            final canCloseTickets = state.tickets.length > 1;

            return Row(
              children: [
                // вкладки слева
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _Chip(
                          text: 'История продаж',
                          icon: Icons.history,
                          active: state.isHistoryMode,
                          onTap: cubit.showHistory,
                        ),
                        const SizedBox(width: 5),

                        for (final t in state.tickets) ...[
                          _TicketTab(
                            text: 'Чек № ${t.id} | ${t.items.length} товаров',
                            active: !state.isHistoryMode &&
                                t.id == state.activeTicketId,
                            onTap: () => cubit.switchTicket(t.id),
                            showClose: canCloseTickets,
                            onClose: canCloseTickets
                                ? () => cubit.closeTicket(t.id)
                                : null,
                          ),
                          const SizedBox(width: 5),
                        ],

                        TextButton(
                          onPressed: cubit.createHoldTicket,
                          child: const Text(
                            '+ Отложка',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // иконки справа
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: SvgPicture.asset(
                        'assets/svg/bag.svg',
                        width: 20,
                        height: 20,
                        color: Colors.white70,
                      ),
                      tooltip: '',
                    ),
                    _divider(),
                    IconButton(
                      onPressed: () => showPosActionsDialog(context),
                      icon: SvgPicture.asset(
                        'assets/svg/elements.svg',
                        width: 20,
                        height: 20,
                        color: Colors.white70,
                      ),
                      tooltip: '',
                    ),
                    _divider(),
                    const SizedBox(width: 5),
                    const _StatusDot(),
                    const SizedBox(width: 12),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 62,
        color: Colors.black45,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}

class _TicketTab extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback? onTap;

  final bool showClose;
  final VoidCallback? onClose;

  const _TicketTab({
    required this.text,
    this.active = false,
    this.onTap,
    this.showClose = false,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFFF3F4F6) : const Color(0xFF536074);
    final textColor = active ? Colors.black : Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(color: textColor, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            if (showClose && onClose != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // чтобы клик по X не триггерил onTap вкладки
                  onClose?.call();
                },
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: active ? Colors.black54 : Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _Chip({
    required this.text,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFFF3F4F6) : const Color(0xFF536074);
    final iconColor = active ? Colors.black : Colors.white70;
    final textColor = iconColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: textColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: const [
            Text('Қанат C', style: TextStyle(color: Colors.white70)),
            Text('Кассир', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
        const SizedBox(width: 14),
        SvgPicture.asset(
          'assets/svg/lock.svg',
          width: 19.5,
          height: 20.5,
          color: Colors.white70,
        ),
        const SizedBox(width: 14),
        Container(
          width: 1,
          height: 62,
          color: Colors.black45,
          margin: const EdgeInsets.symmetric(horizontal: 8),
        ),
        const SizedBox(width: 14),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

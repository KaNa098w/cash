// top_bar.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

import 'show_pos_action_dialog.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth <= 1100;
        final barHeight = compact ? 80.0 : 85.0;
        final topPad = compact ? 14.0 : 30.0;
        final sidePad = compact ? 12.0 : 20.0;
        final tabGap = compact ? 8.0 : 5.0;
        final holdFont = compact ? 16.0 : 18.0;

        return Container(
          color: const Color(0xFF262B35),
          height: barHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(sidePad, topPad, 8, 0),
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
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _Chip(
                              text: 'История',
                              icon: 'assets/svg/history.svg',
                              active: state.isHistoryMode,
                              compact: compact,
                              onTap: cubit.showHistory,
                            ),
                            SizedBox(width: tabGap),
                            for (final t in state.tickets) ...[
                              _TicketTab(
                                text: '№${t.id} | ${t.items.length} тов',
                                active: !state.isHistoryMode &&
                                    t.id == state.activeTicketId,
                                compact: compact,
                                onTap: () => cubit.switchTicket(t.id),
                                showClose: !compact && canCloseTickets,
                                onClose: canCloseTickets
                                    ? () async {
                                        final ok = await _showTopBarConfirm(
                                          context,
                                          title: 'Закрыть отложку?',
                                          subtitle:
                                              'Текущая вкладка будет закрыта.',
                                          confirmText: 'Закрыть',
                                          confirmColor:
                                              const Color(0xFFD15850),
                                        );
                                        if (ok != true) return;
                                        cubit.closeTicket(t.id);
                                      }
                                    : null,
                              ),
                              SizedBox(width: tabGap),
                            ],
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                final ok = await _showTopBarConfirm(
                                  context,
                                  title: 'Создать отложку?',
                                  subtitle:
                                      'Будет создан новый отложенный чек.',
                                  confirmText: 'Создать',
                                  confirmColor: const Color(0xFF33CC99),
                                );
                                if (ok != true) return;
                                cubit.createHoldTicket();
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 10 : 12,
                                  vertical: compact ? 12 : 16,
                                ),
                                child: Text(
                                  '+ ОТЛОЖКА',
                                  style: TextStyle(
                                    color: const Color(0xFFFFFFFF),
                                    fontSize: holdFont,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _divider(compact: compact),
                        IconButton(
                          onPressed: () {},
                          icon: SvgPicture.asset(
                            'assets/svg/bag.svg',
                            width: compact ? 20 : 24,
                            height: compact ? 20 : 24,
                            color: Colors.white70,
                          ),
                          tooltip: '',
                        ),
                        _divider(compact: compact),
                        IconButton(
                          onPressed: () => showPosActionsDialog(context),
                          icon: SvgPicture.asset(
                            'assets/svg/elements.svg',
                            width: compact ? 20 : 24,
                            height: compact ? 20 : 24,
                            color: Colors.white70,
                          ),
                          tooltip: '',
                        ),
                        _divider(compact: compact),
                        SizedBox(width: compact ? 2 : 5),
                        _StatusDot(compact: compact),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _divider({required bool compact}) => Container(
        width: 1,
        height: compact ? 68 : 62,
        color: Colors.black45,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}

class _TicketTab extends StatelessWidget {
  final String text;
  final bool active;
  final bool compact;
  final VoidCallback? onTap;

  final bool showClose;
  final VoidCallback? onClose;

  const _TicketTab({
    required this.text,
    this.active = false,
    this.compact = false,
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
        constraints: compact
            ? const BoxConstraints(minWidth: 194)
            : const BoxConstraints(),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 16,
          vertical: compact ? 13 : 16,
        ),
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
              style: TextStyle(
                color: textColor,
                fontSize: compact ? 16 : 18,
                fontWeight: compact ? FontWeight.w600 : FontWeight.w500,
              ),
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
                  size: compact ? 16 : 18,
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
  final String icon; // <-- svg asset path
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _Chip({
    required this.text,
    required this.icon,
    required this.active,
    this.compact = false,
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
        constraints: compact
            ? const BoxConstraints(minWidth: 168)
            : const BoxConstraints(),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 12,
          vertical: compact ? 13 : 16,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
        ),
        child: Row(
          children: [
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: compact ? 16 : 18,
                fontWeight: compact ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            SvgPicture.asset(
              icon,
              width: compact ? 24 : 24,
              height: compact ? 24 : 24,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({super.key, this.compact = false});
  final bool compact;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> {
  bool _online = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshOnline();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshOnline();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshOnline() async {
    final online = await _hasInternet();
    if (!mounted || online == _online) return;
    setState(() => _online = online);
  }

  Future<bool> _hasInternet() async {
    if (kIsWeb) return true;
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(milliseconds: 900));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenProvider = context.read<AuthTokenProvider>();
    final cachierName = tokenProvider.activeUserName ?? 'Гость';
    final nameSize = widget.compact ? 16.0 : 16.0;
    final roleSize = widget.compact ? 12.0 : 12.0;
    final iconSize = widget.compact ? 20.0 : 24.0;
    final dividerHeight = widget.compact ? 68.0 : 62.0;
    final dotSize = widget.compact ? 9.0 : 10.0;

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cachierName,
                style: TextStyle(color: Colors.white70, fontSize: nameSize)),
            Text('Кассир',
                style: TextStyle(color: Colors.white70, fontSize: roleSize)),
          ],
        ),
        SizedBox(width: widget.compact ? 10 : 14),
        SvgPicture.asset(
          'assets/svg/lock.svg',
          width: iconSize,
          height: iconSize,
          color: Colors.white70,
        ),
        SizedBox(width: widget.compact ? 10 : 14),
        Container(
          width: 1,
          height: dividerHeight,
          color: Colors.black45,
          margin: const EdgeInsets.symmetric(horizontal: 8),
        ),
        SizedBox(width: widget.compact ? 10 : 14),
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: _online ? const Color(0xFF22C55E) : const Color(0xFFDC2626),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

Future<bool?> _showTopBarConfirm(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String confirmText,
  required Color confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final maxW = MediaQuery.sizeOf(ctx).width - 48;
      final dialogW = maxW.clamp(360.0, 620.0).toDouble();
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: dialogW,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: confirmColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            confirmText,
                            style: const TextStyle(fontWeight: FontWeight.w800),
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

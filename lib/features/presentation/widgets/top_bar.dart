// top_bar.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

import 'show_pos_action_dialog.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).width <= 900;
        final barHeight = compact ? 56.0 : 64.0;
        final topPad = compact ? 4.0 : 10.0;
        final sidePad = compact ? 10.0 : 20.0;
        final tabGap = compact ? 8.0 : 5.0;
        final holdFont = compact ? 15.0 : 16.0;

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
                                text: '${t.items.length} товар',
                                receiptLabel: const _ReceiptLabel(),
                                active: !state.isHistoryMode &&
                                    t.id == state.activeTicketId,
                                compact: compact,
                                onTap: () => cubit.switchTicket(t.id),
                                showClose: canCloseTickets,
                                onClose: canCloseTickets
                                    ? () => cubit.closeTicket(t.id)
                                    : null,
                              ),
                              SizedBox(width: tabGap),
                            ],
                            TextButton(
                              onPressed: cubit.createHoldTicket,
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
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!compact)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: SvgPicture.asset(
                              'assets/svg/bag.svg',
                              width: 24,
                              height: 24,
                              color: Colors.white70,
                            ),
                            tooltip: '',
                          ),
                          _divider(),
                          IconButton(
                            onPressed: () => showPosActionsDialog(context),
                            icon: SvgPicture.asset(
                              'assets/svg/elements.svg',
                              width: 24,
                              height: 24,
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
      },
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
  final Widget? receiptLabel;
  final bool active;
  final bool compact;
  final VoidCallback? onTap;

  final bool showClose;
  final VoidCallback? onClose;

  const _TicketTab({
    required this.text,
    this.receiptLabel,

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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 16,
          vertical: compact ? 8 : 10,
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
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (receiptLabel != null) receiptLabel!,
                Text(
                  text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: compact ? 15 : 16,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (showClose && onClose != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => onClose?.call(),
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

class _ReceiptLabel extends StatefulWidget {
  const _ReceiptLabel();

  @override
  State<_ReceiptLabel> createState() => _ReceiptLabelState();
}

class _ReceiptLabelState extends State<_ReceiptLabel> {
  int _nextNumber = 0;
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = GetIt.I<PosSyncService>().onOperationsSynced.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final n = await GetIt.I<PosSyncService>().peekNextLocalSaleNumber();
    if (mounted) setState(() => _nextNumber = n);
  }

  @override
  Widget build(BuildContext context) {
    if (_nextNumber == 0) return const SizedBox.shrink();
    return Text(
      '#$_nextNumber',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 12,
          vertical: compact ? 12 : 16,
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
                fontSize: compact ? 15 : 16,
                fontWeight: compact ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            SvgPicture.asset(
              icon,
              width: compact ? 20 : 24,
              height: compact ? 20 : 24,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({super.key});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> {
  bool _online = true;
  Timer? _timer;
  StreamSubscription<int>? _syncedSub;

  @override
  void initState() {
    super.initState();
    _refreshOnline();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshOnline();
    });
    _syncedSub = GetIt.I<PosSyncService>().onOperationsSynced.listen((count) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Синхронизировано: $count оп.'),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _syncedSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshOnline() async {
    final online = await _hasInternet();
    if (!mounted || online == _online) return;
    setState(() => _online = online);
    if (online) _autoSync();
  }

  Future<void> _autoSync() async {
    final auth = context.read<AuthTokenProvider>();
    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    if (key.isEmpty || deviceId.isEmpty) return;
    final repo = GetIt.I<SaleRepository>();
    await repo.syncPendingSales(key: key, deviceId: deviceId);
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

    return Row(
      children: [
        Column(
          children: [
            Text(cachierName,
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            Text('Кассир',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: () => context.read<AuthCubit>().lockToCashiers(),
          child: SvgPicture.asset(
            'assets/svg/lock.svg',
            width: 24,
            height: 24,
            color: Colors.white70,
          ),
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
          decoration: BoxDecoration(
            color: _online ? const Color(0xFF22C55E) : const Color(0xFFDC2626),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

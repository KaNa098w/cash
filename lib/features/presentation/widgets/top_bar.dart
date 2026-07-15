import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/service/marketplace_feature_gate.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/marketplace_orders/marketplace_orders_controller.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'hold_delete_confirm_dialog.dart';
import 'incoming_orders_dialog.dart';
import 'show_pos_action_dialog.dart';

double _topBarTabWidth(bool compact) => compact ? 122.0 : 126.0;

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).width <= 900;
        final barHeight = compact ? 60.0 : 68.0;
        final topPad = compact ? 8.0 : 14.0;
        final sidePad = compact ? 10.0 : 20.0;
        final tabGap = compact ? 12.0 : 8.0;
        final holdFont = compact ? 15.0 : 16.0;

        return Container(
          color: const Color(0xFF262B35),
          height: barHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(sidePad, 0, 8, 0),
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
                      child: Padding(
                        padding: EdgeInsets.only(top: topPad),
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
                                  active: !state.isHistoryMode &&
                                      t.id == state.activeTicketId,
                                  compact: compact,
                                  onTap: () => cubit.switchTicket(t.id),
                                  showClose: canCloseTickets,
                                  onClose: canCloseTickets
                                      ? () async {
                                          if (t.items.isEmpty) {
                                            cubit.closeTicket(t.id);
                                            return;
                                          }

                                          final shouldDelete =
                                              await showHoldDeleteConfirmDialog(
                                            context,
                                            ticketId: t.id,
                                            itemsCount: t.items.length,
                                          );
                                          if (!context.mounted ||
                                              shouldDelete != true) {
                                            return;
                                          }

                                          cubit.closeTicket(t.id);
                                        }
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
                    ),
                    const SizedBox(width: 12),
                    if (!compact)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _divider(),
                          AnimatedBuilder(
                            animation: MarketplaceFeatureGate.instance,
                            builder: (context, _) {
                              if (MarketplaceFeatureGate.instance.enabled) {
                                return const _MarketplaceOrdersButton();
                              }
                              return IconButton(
                                onPressed: null,
                                icon: SvgPicture.asset(
                                  'assets/svg/bag.svg',
                                  width: 24,
                                  height: 24,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                tooltip: 'Онлайн заказы',
                              );
                            },
                          ),
                          _divider(),
                          IconButton(
                            onPressed: () {
                              showPosActionsDialog(context);
                            },
                            icon: SvgPicture.asset(
                              'assets/svg/elements.svg',
                              width: 24,
                              height: 24,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
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
        height: 68,
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
    final bg = active ? const Color(0xFFF2F2F2) : const Color(0xFF536074);
    final textColor = active ? Colors.black : Colors.white70;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints.tightFor(width: _topBarTabWidth(compact)),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 16,
          vertical: compact ? 12 : 16,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
        ),
        child: showClose && onClose != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: compact ? 16 : 16,
                      fontWeight: compact ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      onClose?.call();
                    },
                    child: Icon(
                      Icons.close,
                      size: compact ? 18 : 18,
                      color: active ? Colors.black54 : Colors.white70,
                    ),
                  ),
                ],
              )
            : Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: compact ? 16 : 16,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
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
    final bg = active
        ? const Color.fromARGB(255, 255, 255, 255)
        : const Color(0xFF536074);
    final iconColor = active ? Colors.black : Colors.white;
    final textColor = iconColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints.tightFor(width: _topBarTabWidth(compact)),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 8,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 15 : 16,
                  fontWeight: compact ? FontWeight.w700 : FontWeight.w500,
                ),
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

class _MarketplaceOrdersButton extends StatefulWidget {
  const _MarketplaceOrdersButton();

  @override
  State<_MarketplaceOrdersButton> createState() =>
      _MarketplaceOrdersButtonState();
}

class _MarketplaceOrdersButtonState extends State<_MarketplaceOrdersButton> {
  late final MarketplaceOrdersController _controller;
  int _handledNotificationRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = GetIt.I<MarketplaceOrdersController>();
    _handledNotificationRevision = _controller.notificationRevision;
    _controller.addListener(_handleMarketplaceUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthTokenProvider>();
      unawaited(_controller.configure(
        posKey: auth.posKey ?? '',
        deviceId: auth.deviceId ?? '',
      ));
    });
  }

  void _handleMarketplaceUpdate() {
    if (!mounted ||
        _controller.notificationRevision == _handledNotificationRevision) {
      return;
    }
    _handledNotificationRevision = _controller.notificationRevision;
    final order = _controller.latestIncomingOrder;
    if (order == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Новый заказ №${order.displayNumber}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => showIncomingOrdersDialog(context),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleMarketplaceUpdate);
    unawaited(_controller.deactivate());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final count = _controller.notificationCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => showIncomingOrdersDialog(context),
              icon: SvgPicture.asset(
                'assets/svg/bag.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              tooltip: 'Онлайн заказы',
            ),
            if (count > 0)
              Positioned(
                right: 3,
                top: 5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF262B35)),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot();

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
    final cashierName = _shortCashierName(tokenProvider.activeUserName);

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 18, right: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cashierName,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
              const Text(
                'Кассир',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: () => context.read<AuthCubit>().lockToCashiers(),
          child: SvgPicture.asset(
            'assets/svg/lock.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 1,
          height: 68,
          color: Colors.black45,
          margin: const EdgeInsets.symmetric(horizontal: 8),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final changed = MarketplaceFeatureGate.instance.registerTap();
            if (!changed || !mounted) return;
            final enabled = MarketplaceFeatureGate.instance.enabled;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  enabled
                      ? 'Сервисы маркетплейса включены'
                      : 'Сервисы маркетплейса отключены',
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color:
                    _online ? const Color(0xFF22C55E) : const Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _shortCashierName(String? rawName) {
    final clean = (rawName ?? '').trim();
    if (clean.isEmpty) return 'Гость';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    final surnameInitial = parts[1].characters.first.toUpperCase();
    return '${parts.first} $surnameInitial';
  }
}

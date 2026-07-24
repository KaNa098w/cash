import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/features/presentation/pages/marketplace_orders/marketplace_orders_controller.dart';
import 'package:leemon_app/features/presentation/widgets/incoming_orders_dialog.dart';

class OrderNotificationDemo extends StatefulWidget {
  const OrderNotificationDemo({super.key});

  @override
  State<OrderNotificationDemo> createState() => _OrderNotificationDemoState();
}

class _OrderNotificationDemoState extends State<OrderNotificationDemo> {
  final List<_NotificationOrder> _orders = [];
  final Map<String, Timer> _timers = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final MarketplaceOrdersController _controller;
  int _handledNotificationRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = GetIt.I<MarketplaceOrdersController>();
    _handledNotificationRevision = _controller.notificationRevision;
    _controller.addListener(_handleMarketplaceUpdate);
  }

  void _handleMarketplaceUpdate() {
    if (!mounted) return;
    if (!_controller.hasMarketplaceIntegration) {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      if (_orders.isNotEmpty) setState(_orders.clear);
      return;
    }
    if (_controller.notificationRevision == _handledNotificationRevision) {
      return;
    }
    _handledNotificationRevision = _controller.notificationRevision;
    final order = _controller.latestIncomingOrder;
    if (order == null) return;
    _addOrder(_notificationFromMarketplaceOrder(order));
  }

  void _addOrder(_NotificationOrder order) {
    if (!mounted) return;
    unawaited(_playOrderSound());
    setState(() => _orders.insert(0, order));
    // On some desktop embedders an asynchronous socket/timer callback marks
    // the widget dirty but the next frame is not requested until the next
    // pointer event. Explicitly wake the renderer for incoming orders.
    SchedulerBinding.instance.ensureVisualUpdate();
    _timers[order.id] = Timer(
      const Duration(seconds: 5),
      () => _dismiss(order.id),
    );
  }

  _NotificationOrder _notificationFromMarketplaceOrder(
    MarketplaceOrder order,
  ) {
    final itemsCount = order.groupedItems.isNotEmpty
        ? order.groupedItems.fold<int>(
            0,
            (total, item) => total + item.requestedQuantity.round(),
          )
        : order.items.length;
    return _NotificationOrder(
      id: order.id,
      number: order.displayNumber,
      customer: order.customer.name.trim().isEmpty
          ? 'Покупатель'
          : order.customer.name,
      itemsCount: itemsCount,
      total: 'Маркетплейс',
      delivery: 'Новый',
    );
  }

  Future<void> _playOrderSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(
        BytesSource(_orderChime, mimeType: 'audio/wav'),
        mode: PlayerMode.mediaPlayer,
        volume: 1,
      );
    } catch (error) {
      debugPrint('Не удалось проиграть звук нового заказа: $error');
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  void _dismiss(String id) {
    _timers.remove(id)?.cancel();
    if (!mounted) return;
    setState(() => _orders.removeWhere((order) => order.id == id));
  }

  Future<void> _openOrder(_NotificationOrder order) async {
    _dismiss(order.id);
    await showIncomingOrdersDialog(context);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleMarketplaceUpdate);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.hasMarketplaceIntegration) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          Positioned(
            top: 16,
            right: 16,
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final order in _orders.take(4)) ...[
                  _OrderNotificationCard(
                    key: ValueKey(order.id),
                    order: order,
                    onTap: () => _openOrder(order),
                    onClose: () => _dismiss(order.id),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final Uint8List _orderChime = _createOrderChime();

Uint8List _createOrderChime() {
  const sampleRate = 44100;
  const durationSeconds = 0.72;
  final sampleCount = (sampleRate * durationSeconds).round();
  final dataSize = sampleCount * 2;
  final bytes = ByteData(44 + dataSize);

  void writeText(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeText(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  writeText(8, 'WAVE');
  writeText(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeText(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final time = i / sampleRate;
    final attack = math.min(1.0, time / 0.025);
    final release = math.pow(1 - time / durationSeconds, 2.2).toDouble();
    final secondTone = time < 0.16 ? 0.0 : 1.0;
    final first = math.sin(2 * math.pi * 659.25 * time);
    final second = math.sin(2 * math.pi * 987.77 * (time - 0.16));
    final shimmer = math.sin(2 * math.pi * 1318.51 * time) * 0.12;
    final signal = (first * 0.48 + second * 0.42 * secondTone + shimmer) *
        attack *
        release;
    bytes.setInt16(
      44 + i * 2,
      (signal.clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

class _OrderNotificationCard extends StatelessWidget {
  const _OrderNotificationCard({
    super.key,
    required this.order,
    required this.onTap,
    required this.onClose,
  });

  final _NotificationOrder order;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDelivery = order.delivery == 'Доставка';
    final accent =
        isDelivery ? const Color(0xFF2563EB) : const Color(0xFF9333EA);
    final badgeBackground =
        isDelivery ? const Color(0xFFDBEAFE) : const Color(0xFFF3E8FF);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 42, end: 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) => Transform.translate(
        offset: Offset(offset, 0),
        child: Opacity(opacity: (1 - offset / 42).clamp(0, 1), child: child),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(seconds: 5),
        builder: (context, progress, child) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white,
                    isDelivery
                        ? const Color(0xFFF4F8FF)
                        : const Color(0xFFFCF7FF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.24)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D0F172A),
                    blurRadius: 36,
                    spreadRadius: 4,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.35)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 10, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accent,
                                Color.lerp(accent, Colors.black, 0.22)!,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.3),
                                blurRadius: 13,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: SvgPicture.asset(
                            'assets/svg/bag.svg',
                            width: 23,
                            height: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Text(
                                          'Новый заказ',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '№ ${order.number}',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'только что',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${order.customer}  •  ${order.itemsCount} товара',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    order.total,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeBackground,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.16),
                                      ),
                                    ),
                                    child: Text(
                                      order.delivery,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Открыть  ›',
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: onClose,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          color: const Color(0xFF94A3B8),
                          tooltip: 'Закрыть',
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accent, accent.withValues(alpha: 0.55)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationOrder {
  const _NotificationOrder({
    required this.id,
    required this.number,
    required this.customer,
    required this.itemsCount,
    required this.total,
    required this.delivery,
  });

  final String id;
  final String number;
  final String customer;
  final int itemsCount;
  final String total;
  final String delivery;
}

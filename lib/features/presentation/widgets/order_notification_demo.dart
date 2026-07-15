import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class OrderNotificationDemo extends StatefulWidget {
  const OrderNotificationDemo({super.key});

  @override
  State<OrderNotificationDemo> createState() => _OrderNotificationDemoState();
}

class _OrderNotificationDemoState extends State<OrderNotificationDemo> {
  final List<_DemoOrder> _orders = [];
  final Map<int, Timer> _timers = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _nextOrderNumber = 1248;
  Timer? _secondDemoTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _addOrder();
      _secondDemoTimer = Timer(const Duration(milliseconds: 1400), _addOrder);
    });
  }

  void _addOrder() {
    if (!mounted) return;
    unawaited(_playOrderSound());
    final number = _nextOrderNumber++;
    final order = _DemoOrder(
      number: number,
      customer: number.isEven ? 'Алексей Смирнов' : 'Айгерим К.',
      itemsCount: number.isEven ? 4 : 2,
      total: number.isEven ? '12 450 ₸' : '6 790 ₸',
      delivery: number.isEven ? 'Доставка' : 'Самовывоз',
    );
    setState(() => _orders.insert(0, order));
    _timers[number] = Timer(
      const Duration(seconds: 5),
      () => _dismiss(number),
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

  void _dismiss(int number) {
    _timers.remove(number)?.cancel();
    if (!mounted) return;
    setState(() => _orders.removeWhere((order) => order.number == number));
  }

  Future<void> _openOrder(_DemoOrder order) async {
    _dismiss(order.number);
    await showDialog<void>(
      context: context,
      builder: (context) => _DemoOrderDialog(order: order),
    );
  }

  @override
  void dispose() {
    _secondDemoTimer?.cancel();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    key: ValueKey(order.number),
                    order: order,
                    onTap: () => _openOrder(order),
                    onClose: () => _dismiss(order.number),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: ElevatedButton.icon(
              onPressed: _addOrder,
              icon: const Icon(Icons.notifications_active_outlined, size: 19),
              label: const Text('Тест: новый заказ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 5,
              ),
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

  final _DemoOrder order;
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

class _DemoOrderDialog extends StatelessWidget {
  const _DemoOrderDialog({required this.order});

  final _DemoOrder order;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Заказ № ${order.number}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Макет карточки заказа',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 22),
            _detailRow('Клиент', order.customer),
            _detailRow('Получение', order.delivery),
            _detailRow('Позиций', '${order.itemsCount}'),
            _detailRow('К оплате', order.total, strong: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Перейти к заказу'),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child:
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoOrder {
  const _DemoOrder({
    required this.number,
    required this.customer,
    required this.itemsCount,
    required this.total,
    required this.delivery,
  });

  final int number;
  final String customer;
  final int itemsCount;
  final String total;
  final String delivery;
}

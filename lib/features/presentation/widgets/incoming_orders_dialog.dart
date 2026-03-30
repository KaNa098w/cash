import 'package:flutter/material.dart';

Future<void> showIncomingOrdersDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'incoming-orders',
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => const _IncomingOrdersDialog(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _IncomingOrdersDialog extends StatelessWidget {
  const _IncomingOrdersDialog();

  static const _orders = <_IncomingOrder>[
    _IncomingOrder(
      id: 'A-2401',
      customer: 'Айгерим С.',
      channel: 'Glovo',
      status: 'Новый',
      accent: Color(0xFF0F766E),
      eta: '12 мин',
      amount: '12 400 c',
      time: '14:32',
      items: ['Латте x2', 'Цезарь x1', 'Чизкейк x1'],
    ),
    _IncomingOrder(
      id: 'A-2402',
      customer: 'Руслан Н.',
      channel: 'Доставка',
      status: 'Срочно',
      accent: Color(0xFFB45309),
      eta: '7 мин',
      amount: '8 900 c',
      time: '14:36',
      items: ['Комбо бургер x2', 'Кола 1л x1'],
    ),
    _IncomingOrder(
      id: 'A-2403',
      customer: 'Самовывоз',
      channel: 'Instagram',
      status: 'Ожидает',
      accent: Color(0xFF1D4ED8),
      eta: '18 мин',
      amount: '6 300 c',
      time: '14:40',
      items: ['Паста x1', 'Суп дня x1', 'Лимонад x2'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 1100;

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: compact ? size.width - 32 : 1040,
            height: compact ? size.height - 48 : 700,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7F4EC),
                  Color(0xFFEFF5F8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(26, 22, 18, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1F2937),
                          Color(0xFF0F172A),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                          child: const Icon(
                            Icons.shopping_bag_outlined,
                            color: Color(0xFFFBBF24),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Поступившие заказы',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Временный макет для входящих заказов. Позже сюда подключим реальные данные.',
                                style: TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: compact
                          ? ListView(
                              children: [
                                const _OrdersStatsRow(),
                                const SizedBox(height: 16),
                                ..._orders.map((order) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _OrderCard(order: order),
                                    )),
                              ],
                            )
                          : Row(
                              children: [
                                SizedBox(
                                  width: 320,
                                  child: Column(
                                    children: [
                                      const _OrdersStatsRow(),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: ListView.separated(
                                          itemCount: _orders.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 12),
                                          itemBuilder: (_, index) =>
                                              _OrderCard(order: _orders[index]),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: _OrdersPreviewPanel(order: _orders.first),
                                ),
                              ],
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

class _OrdersStatsRow extends StatelessWidget {
  const _OrdersStatsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _StatChip(
            label: 'Новых',
            value: '03',
            accent: Color(0xFF0F766E),
            bg: Color(0xFFDFF7F0),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            label: 'Срочных',
            value: '01',
            accent: Color(0xFFB45309),
            bg: Color(0xFFFFF1D6),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            label: 'Сумма',
            value: '27 600',
            accent: Color(0xFF1D4ED8),
            bg: Color(0xFFE6F0FF),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.accent,
    required this.bg,
  });

  final String label;
  final String value;
  final Color accent;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final _IncomingOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: order.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  order.customer,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                order.time,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OrderPill(
                text: order.channel,
                fg: order.accent,
                bg: order.accent.withValues(alpha: 0.10),
              ),
              _OrderPill(
                text: order.status,
                fg: const Color(0xFF111827),
                bg: const Color(0xFFF3F4F6),
              ),
              _OrderPill(
                text: 'ETA ${order.eta}',
                fg: const Color(0xFF1D4ED8),
                bg: const Color(0xFFE8F0FF),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...order.items.take(2).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                order.id,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                order.amount,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersPreviewPanel extends StatelessWidget {
  const _OrdersPreviewPanel({required this.order});

  final _IncomingOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFF7E8),
                  Color(0xFFF3F8FF),
                ],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Заказ ${order.id}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${order.customer} • ${order.channel}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: order.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    order.status,
                    style: TextStyle(
                      color: order.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PreviewBlock(
                          label: 'Сумма',
                          value: order.amount,
                          bg: const Color(0xFFFFF7E8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PreviewBlock(
                          label: 'Время',
                          value: order.eta,
                          bg: const Color(0xFFEAF8F2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: _PreviewBlock(
                          label: 'Оплата',
                          value: 'Картой',
                          bg: Color(0xFFEAF1FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Состав заказа',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...order.items.map(
                                (item) => Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.receipt_long_outlined,
                                        color: Color(0xFF64748B),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    side: const BorderSide(
                                      color: Color(0xFFD1D5DB),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Отложить',
                                    style: TextStyle(
                                      color: Color(0xFF334155),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: const Color(0xFF111827),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Принять заказ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
    required this.label,
    required this.value,
    required this.bg,
  });

  final String label;
  final String value;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderPill extends StatelessWidget {
  const _OrderPill({
    required this.text,
    required this.fg,
    required this.bg,
  });

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _IncomingOrder {
  const _IncomingOrder({
    required this.id,
    required this.customer,
    required this.channel,
    required this.status,
    required this.accent,
    required this.eta,
    required this.amount,
    required this.time,
    required this.items,
  });

  final String id;
  final String customer;
  final String channel;
  final String status;
  final Color accent;
  final String eta;
  final String amount;
  final String time;
  final List<String> items;
}

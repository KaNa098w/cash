import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key});

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  late final List<_DebtCounterparty> _items = List.of(_initialItems);
  int? _selectedIndex = 0;

  static const _initialItems = <_DebtCounterparty>[
    _DebtCounterparty(
      name: 'ТОО Алем Trade',
      phone: '+7 777 240 18 90',
      amount: 20500,
      lastOperation: 'Продажа в долг',
      date: 'Сегодня, 14:20',
      tag: 'Магазин',
    ),
    _DebtCounterparty(
      name: 'Айгерим Сапарова',
      phone: '+7 701 558 44 21',
      amount: -16400,
      lastOperation: 'Переплата клиента',
      date: 'Вчера, 18:05',
      tag: 'Постоянный клиент',
    ),
    _DebtCounterparty(
      name: 'ИП Nur Supply',
      phone: '+7 705 120 90 11',
      amount: 78200,
      lastOperation: 'Накладная в долг',
      date: '20 апр, 11:35',
      tag: 'Поставщик',
    ),
    _DebtCounterparty(
      name: 'Руслан Н.',
      phone: '+7 747 016 70 33',
      amount: -5200,
      lastOperation: 'Возврат / аванс',
      date: '19 апр, 09:10',
      tag: 'Клиент',
    ),
    _DebtCounterparty(
      name: 'Green Market',
      phone: '+7 778 650 12 12',
      amount: 34700,
      lastOperation: 'Частичная оплата',
      date: '18 апр, 16:48',
      tag: 'Оптовик',
    ),
  ];

  _DebtCounterparty? get _selectedItem {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _items.length) return null;
    return _items[index];
  }

  Future<void> _adjustSelectedDebt({required bool subtract}) async {
    final selected = _selectedItem;
    final index = _selectedIndex;
    if (selected == null || index == null) return;

    final amount = await _showDebtAmountDialog(
      context,
      title: subtract ? 'Сколько вернул?' : 'Добавить долг',
      actionLabel: subtract ? 'Минусовать' : 'Плюсовать',
      accentColor: subtract ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
    );
    if (amount == null || amount <= 0 || !mounted) return;

    final nextAmount = selected.amount + (subtract ? -amount : amount);
    setState(() {
      _items[index] = selected.copyWith(
        amount: nextAmount,
        lastOperation: subtract ? 'Клиент вернул долг' : 'Добавили долг',
        date: 'Только что',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final receivable =
        _items.where((e) => e.amount > 0).fold<int>(0, (s, e) => s + e.amount);
    final payable =
        _items.where((e) => e.amount < 0).fold<int>(0, (s, e) => s + e.amount);
    final net = receivable + payable;
    final selectedItem = _selectedItem;

    Widget debtList({required bool twoColumns}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Контрагенты',
            subtitle: '${_items.length} записей',
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: twoColumns ? 2 : 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 88,
            ),
            itemBuilder: (context, index) {
              return _DebtCard(
                item: _items[index],
                selected: _selectedIndex == index,
                onTap: () {
                  setState(() => _selectedIndex = index);
                },
              );
            },
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              receivable: receivable,
              payable: payable,
              net: net,
              onBack: () => context.go('/pos'),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 28 : 16,
                      18,
                      wide ? 28 : 16,
                      28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Toolbar(),
                            const SizedBox(height: 12),
                            _SummaryBand(
                              receivable: receivable,
                              payable: payable,
                              net: net,
                            ),
                            const SizedBox(height: 12),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: debtList(twoColumns: false),
                                  ),
                                  const SizedBox(width: 18),
                                  SizedBox(
                                    width: 340,
                                    child: selectedItem == null
                                        ? const _NoDebtSelectionPanel()
                                        : _DebtActionPanel(
                                            item: selectedItem,
                                            onSubtract: () =>
                                                _adjustSelectedDebt(
                                              subtract: true,
                                            ),
                                            onAdd: () => _adjustSelectedDebt(
                                              subtract: false,
                                            ),
                                          ),
                                  ),
                                ],
                              )
                            else ...[
                              if (selectedItem != null) ...[
                                _DebtActionPanel(
                                  item: selectedItem,
                                  onSubtract: () =>
                                      _adjustSelectedDebt(subtract: true),
                                  onAdd: () =>
                                      _adjustSelectedDebt(subtract: false),
                                ),
                                const SizedBox(height: 12),
                              ],
                              debtList(twoColumns: constraints.maxWidth >= 720),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1D4ED8),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoDebtSelectionPanel extends StatelessWidget {
  const _NoDebtSelectionPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.touch_app_rounded,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Выберите контрагента',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'После выбора здесь появятся баланс и действия для изменения долга.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.receivable,
    required this.payable,
    required this.net,
    required this.onBack,
  });

  final int receivable;
  final int payable;
  final int net;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF2F343B),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 42,
                child: IconButton(
                  tooltip: 'Назад',
                  onPressed: onBack,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Долги',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatMoney(receivable)} к получению  /  ${_formatMoney(payable)} переплата',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              _NetBadge(amount: net),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final search = Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF6B7280)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Поиск контрагента',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ],
          ),
        );

        const filters = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(label: 'Все', selected: true),
            _FilterChip(label: 'Нам должны'),
            _FilterChip(label: 'Мы должны'),
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              search,
              const SizedBox(height: 8),
              filters,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 14),
            filters,
          ],
        );
      },
    );
  }
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({
    required this.receivable,
    required this.payable,
    required this.net,
  });

  final int receivable;
  final int payable;
  final int net;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final children = [
          _SummaryTile(
            label: 'Нам должны',
            value: _formatMoney(receivable),
            color: const Color(0xFF16A34A),
            icon: Icons.payments_rounded,
          ),
          _SummaryTile(
            label: 'Мы должны',
            value: _formatMoney(payable),
            color: const Color(0xFFDC2626),
            icon: Icons.request_quote_rounded,
          ),
          _SummaryTile(
            label: 'Баланс',
            value: _formatMoney(net),
            color: net >= 0 ? const Color(0xFF0F766E) : const Color(0xFFB91C1C),
            icon: Icons.account_balance_wallet_rounded,
          ),
        ];

        if (narrow) {
          return Column(
            children: [
              for (final child in children) ...[
                child,
                if (child != children.last) const SizedBox(height: 8),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final child in children) ...[
              Expanded(child: child),
              if (child != children.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtActionPanel extends StatelessWidget {
  const _DebtActionPanel({
    required this.item,
    required this.onSubtract,
    required this.onAdd,
  });

  final _DebtCounterparty item;
  final VoidCallback onSubtract;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final positive = item.amount >= 0;
    final color = positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusText = positive ? 'Нам должны' : 'Мы должны';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.person_rounded, color: color, size: 30),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _SmallPill(text: item.tag),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _formatMoney(item.amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          _DetailLine(icon: Icons.phone_rounded, text: item.phone),
          const SizedBox(height: 7),
          _DetailLine(
              icon: Icons.receipt_long_rounded, text: item.lastOperation),
          const SizedBox(height: 7),
          _DetailLine(icon: Icons.schedule_rounded, text: item.date),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DebtActionButton(
                  label: 'Вернул',
                  icon: Icons.remove_rounded,
                  color: const Color(0xFFDC2626),
                  onPressed: onSubtract,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DebtActionButton(
                  label: 'Добавить',
                  icon: Icons.add_rounded,
                  color: const Color(0xFF16A34A),
                  onPressed: onAdd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF374151),
            ),
          ),
        ),
      ],
    );
  }
}

class _DebtActionButton extends StatelessWidget {
  const _DebtActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _DebtCounterparty item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final positive = item.amount >= 0;
    final color = positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final softColor =
        positive ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            color: selected ? softColor : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                      color: color.withValues(alpha: 0.13),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 36,
                decoration: BoxDecoration(
                  color: softColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    positive ? '+' : '-',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _formatMoney(item.amount),
                          maxLines: 1,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: color,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _SmallPill(text: item.tag),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    this.selected = false,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2F343B) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFF2F343B) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: selected ? Colors.white : const Color(0xFF4B5563),
        ),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF4B5563),
        ),
      ),
    );
  }
}

class _NetBadge extends StatelessWidget {
  const _NetBadge({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    final positive = amount >= 0;
    final color = positive ? const Color(0xFF33CC99) : const Color(0xFFFF6B6B);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        _formatMoney(amount),
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _DebtCounterparty {
  const _DebtCounterparty({
    required this.name,
    required this.phone,
    required this.amount,
    required this.lastOperation,
    required this.date,
    required this.tag,
  });

  final String name;
  final String phone;
  final int amount;
  final String lastOperation;
  final String date;
  final String tag;

  _DebtCounterparty copyWith({
    int? amount,
    String? lastOperation,
    String? date,
  }) {
    return _DebtCounterparty(
      name: name,
      phone: phone,
      amount: amount ?? this.amount,
      lastOperation: lastOperation ?? this.lastOperation,
      date: date ?? this.date,
      tag: tag,
    );
  }
}

Future<int?> _showDebtAmountDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required Color accentColor,
}) {
  final controller = TextEditingController();

  int parseAmount() {
    final raw = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(raw) ?? 0;
  }

  void setQuickAmount(int amount) {
    controller.text = amount.toString();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  return showDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final amount = parseAmount();
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 26,
                      offset: Offset(0, 18),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Введите сумму',
                          hintStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF9CA3AF),
                          ),
                          suffixText: 'тг',
                          suffixStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF6B7280),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: accentColor, width: 1.6),
                          ),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final quick in const [5000, 10000, 20000])
                            _QuickAmountButton(
                              amount: quick,
                              onTap: () {
                                setQuickAmount(quick);
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF374151),
                                  side: const BorderSide(
                                    color: Color(0xFFD1D5DB),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Закрыть',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: amount > 0
                                    ? () => Navigator.of(context).pop(amount)
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFFE5E7EB),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  actionLabel,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
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
            ),
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

class _QuickAmountButton extends StatelessWidget {
  const _QuickAmountButton({
    required this.amount,
    required this.onTap,
  });

  final int amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: Text(
            _formatMoney(amount),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatMoney(int value) {
  final sign = value > 0
      ? '+'
      : value < 0
          ? '-'
          : '';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(' ');
    }
  }
  return '$sign${buffer.toString()}тг';
}

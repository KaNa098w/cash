import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/utils/sales_filter.dart';

class SalesSearchBar extends StatelessWidget {
  const SalesSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onOpenKeyboard,
    required this.onClear,
    required this.foundCount,
    this.selectedDate,
    this.onPickDate,
    this.onClearDate,
    this.statusFilter = SalesStatusFilter.all,
    this.onStatusFilterChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  final VoidCallback onSubmit;
  final VoidCallback onOpenKeyboard;
  final VoidCallback onClear;
  final int? foundCount;

  final DateTime? selectedDate;
  final VoidCallback? onPickDate;
  final VoidCallback? onClearDate;
  final SalesStatusFilter statusFilter;
  final ValueChanged<SalesStatusFilter>? onStatusFilterChanged;

  static const _accent = Color(0xFF456B5A);
  static const _accentLight = Color(0xFFEAF1ED);
  static const _grey = Color(0xFF6B7280);
  static const _greyBorder = Color(0xFFD7DED9);

  static const _months = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];

  String _formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = _months[d.month - 1];
    return '$day $month ${d.year}';
  }

  String _statusLabel(SalesStatusFilter filter) {
    return switch (filter) {
      SalesStatusFilter.all => 'Фильтр по статусу',
      SalesStatusFilter.cash => 'Наличные',
      SalesStatusFilter.card => 'Безналичные',
      SalesStatusFilter.debt => 'В долг',
      SalesStatusFilter.mixed => 'Смешанная',
      SalesStatusFilter.refunded => 'Возвраты',
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = selectedDate != null;
    final hasStatus = statusFilter != SalesStatusFilter.all;
    const topControlHeight = 36.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: topControlHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0x33000000),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => onSubmit(),
                        style: const TextStyle(fontSize: 18),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 7,
                            horizontal: 0,
                          ),
                          hintText: 'Поиск по номеру чека',
                          hintStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            letterSpacing: 0.26,
                            color: Color(0xFF999999),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 40),
                          suffixIconConstraints: const BoxConstraints(
                            minHeight: topControlHeight,
                            minWidth: 30,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (controller.text.trim().isNotEmpty)
                                IconButton(
                                  tooltip: 'Очистить',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 30,
                                    height: topControlHeight,
                                  ),
                                  icon: const Icon(Icons.close),
                                  onPressed: onClear,
                                ),
                              IconButton(
                                tooltip: 'Найти',
                                padding: const EdgeInsets.only(right: 4),
                                constraints: const BoxConstraints.tightFor(
                                  width: 30,
                                  height: topControlHeight,
                                ),
                                icon: SvgPicture.asset(
                                  'assets/svg/search.svg',
                                  width: 20,
                                  height: 20,
                                ),
                                onPressed: onSubmit,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: topControlHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0x33000000),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: IconButton(
                      tooltip: 'Клавитура',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        height: topControlHeight,
                        width: 46,
                      ),
                      icon: SvgPicture.asset(
                        'assets/svg/keyboard.svg',
                        width: 20,
                        height: 20,
                      ),
                      onPressed: onOpenKeyboard,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 46,
                decoration: BoxDecoration(
                  color: hasDate ? _accentLight : Colors.white,
                  border: Border.all(
                    color: hasDate ? _accent : _greyBorder,
                    width: 1.4,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onPickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: hasDate ? _accent : _grey,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            hasDate
                                ? _formatDate(selectedDate!)
                                : 'Фильтр по дате',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: hasDate ? _accent : _grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (hasDate) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onClearDate,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: _accent, width: 1.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 46,
                decoration: BoxDecoration(
                  color: hasStatus ? _accentLight : Colors.white,
                  border: Border.all(
                    color: hasStatus ? _accent : _greyBorder,
                    width: 1.4,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: PopupMenuButton<SalesStatusFilter>(
                  offset: const Offset(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: onStatusFilterChanged,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: SalesStatusFilter.cash,
                      child: Text('Наличные'),
                    ),
                    const PopupMenuItem(
                      value: SalesStatusFilter.card,
                      child: Text('Безналичные'),
                    ),
                    const PopupMenuItem(
                      value: SalesStatusFilter.debt,
                      child: Text('В долг'),
                    ),
                    const PopupMenuItem(
                      value: SalesStatusFilter.mixed,
                      child: Text('Смешанная'),
                    ),
                    const PopupMenuItem(
                      value: SalesStatusFilter.refunded,
                      child: Text('Возвраты'),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: hasStatus ? _accent : _grey,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _statusLabel(statusFilter),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: hasStatus ? _accent : _grey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: hasStatus ? _accent : _grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasStatus) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onStatusFilterChanged?.call(
                        SalesStatusFilter.all,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: _accent, width: 1.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

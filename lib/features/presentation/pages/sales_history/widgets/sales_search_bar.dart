import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

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

  static const _blue = Color(0xFF2563EB);
  static const _blueLight = Color(0xFFEFF6FF);
  static const _grey = Color(0xFF6B7280);
  static const _greyBorder = Color(0xFFD1D5DB);

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

  @override
  Widget build(BuildContext context) {
    final hasDate = selectedDate != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          // ── Search field block ────────────────────────────────────────
          SizedBox(
            width: 520,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
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
                            vertical: 12,
                            horizontal: 0,
                          ),
                          hintText: 'Поиск по номеру чека',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 40),
                          suffixIconConstraints:
                              const BoxConstraints(minHeight: 42, minWidth: 42),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (controller.text.trim().isNotEmpty)
                                IconButton(
                                  tooltip: 'Очистить',
                                  icon: const Icon(Icons.close),
                                  onPressed: onClear,
                                ),
                              IconButton(
                                tooltip: 'Найти',
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey, width: 1.2),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: IconButton(
                    tooltip: 'Клавиатура',
                    icon: SvgPicture.asset(
                      'assets/svg/keyboard.svg',
                      width: 20,
                      height: 20,
                    ),
                    onPressed: onOpenKeyboard,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ── Date chip ─────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 46,
            decoration: BoxDecoration(
              color: hasDate ? _blueLight : Colors.white,
              border: Border.all(
                color: hasDate ? _blue : _greyBorder,
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
                        color: hasDate ? _blue : _grey,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        hasDate ? _formatDate(selectedDate!) : 'Фильтр по дате',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hasDate ? _blue : _grey,
                        ),
                      ),
                      if (hasDate) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onClearDate,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: _blue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // const SizedBox(width: 12),
          // if (foundCount != null)
          //   Text(
          //     'Найдено: $foundCount',
          //     style: TextStyle(
          //       fontSize: 14,
          //       color: Colors.black.withValues(alpha: 0.65),
          //       fontWeight: FontWeight.w600,
          //     ),
          //   ),
        ],
      ),
    );
  }
}

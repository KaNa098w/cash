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
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  final VoidCallback onSubmit;
  final VoidCallback onOpenKeyboard;
  final VoidCallback onClear;

  /// null => не показывать
  final int? foundCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
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
          const SizedBox(width: 12),
          if (foundCount != null)
            Text(
              'Найдено: $foundCount',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withOpacity(0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

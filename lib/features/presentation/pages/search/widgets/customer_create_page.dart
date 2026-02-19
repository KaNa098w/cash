import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/presentation/pages/search/widgets/bottom_btn_widget.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/onscreen_keyboar_widget.dart';

import 'customer_create_dialog.dart'; // CustomerLite + showCustomerCreateDialog

Future<CustomerLite?> showCustomerPickerDialog(
  BuildContext context, {
  required List<CustomerLite> customers,
}) {
  return showDialog<CustomerLite?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CustomerPickerDialog(customers: customers),
  );
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({required this.customers});

  final List<CustomerLite> customers;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  late List<CustomerLite> _all;
  CustomerLite? _selected;

  OverlayEntry? _keyboardEntry;

  @override
  void initState() {
    super.initState();
    _all = List.of(widget.customers);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideKeyboard();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _showKeyboard() {
    if (_keyboardEntry != null) return;

    _keyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () =>
                _search, // ✅ функция, всегда актуальный ctrl
            onEnter: () {
              final items = _filtered;
              if (_selected == null && items.isNotEmpty) {
                setState(() => _selected = items.first);
              }
            },
            onClose: _hideKeyboard, // ✅ закрыть overlay клавиатуру
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_keyboardEntry!);
  }

  void _hideKeyboard() {
    _keyboardEntry?.remove();
    _keyboardEntry = null;
  }

  List<CustomerLite> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;

    final qPhone = q.replaceAll(' ', '');
    return _all.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.replaceAll(' ', '').contains(qPhone);
    }).toList();
  }

  Future<void> _onCreate() async {
    final auth = context.read<AuthTokenProvider>();
    final posKey = auth.posKey?.trim() ?? '';

    final created = await showCustomerCreateDialog(context, posKey: posKey);
    if (created == null) return;

    setState(() {
      _all.insert(0, created);
      _selected = created;
      _search.text = created.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 820,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              blurRadius: 26,
              offset: Offset(0, 18),
              color: Color(0x33000000),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // SEARCH ROW
            Row(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _searchFocus,
                    builder: (_, __) {
                      final focused = _searchFocus.hasFocus;
                      return Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: focused
                                ? const Color(0xFF111827)
                                : const Color.fromARGB(255, 181, 184, 189),
                            width: focused ? 2.5 : 2,
                          ),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _search,
                                focusNode: _searchFocus,
                                autofocus: true,
                                showCursor: true,
                                cursorWidth: 2,
                                cursorColor: Colors.black,
                                decoration: const InputDecoration(
                                  hintText: 'Введите имя клиента',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onTap: () => _searchFocus.requestFocus(),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const Icon(Icons.search, size: 22),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  width: 44,
                  child: OutlinedButton(
                    onPressed: _showKeyboard, // ✅ overlay, не блокирует фон
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Color.fromARGB(255, 189, 190, 191)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: SvgPicture.asset(
                      'assets/svg/keyboard.svg',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                      // colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn), // если нужно перекрасить
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // HEADER
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Имя',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Телефон',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Оборот',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // LIST
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final c = items[index];
                  final isActive = identical(_selected, c);

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _selected = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFEAF2FF)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              c.phone,
                              style: const TextStyle(fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _fmtMoneyKzt(c.balance),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // BOTTOM BUTTONS
            Row(
              children: [
                Expanded(
                  child: BottomBtn(
                    text: 'ЗАКРЫТЬ',
                    bg: const Color(0xFFBDBDBD),
                    onTap: () {
                      _hideKeyboard();
                      Navigator.of(context).pop(null);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BottomBtn(
                    text: 'СОЗДАТЬ',
                    bg: const Color(0xFF9E9E9E),
                    onTap: _onCreate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BottomBtn(
                    text: 'ВЫБРАТЬ',
                    bg: const Color(0xFF2DB7C8),
                    enabled: _selected != null,
                    onTap: () {
                      _hideKeyboard();
                      Navigator.of(context).pop(_selected);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtMoneyKzt(num v) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final frac = parts.length > 1 ? parts[1] : '00';

  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    final pos = intPart.length - i;
    buf.write(intPart[i]);
    if (pos > 1 && pos % 3 == 1) buf.write(' ');
  }

  return '${buf.toString()}.$frac ₸';
}

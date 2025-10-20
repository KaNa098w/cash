import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/show_pos_action_dialog.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading:
          false, // Optional: removes the default back button
      titleSpacing: 0, // Removes default padding for the title
      flexibleSpace: SafeArea(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.end, // This pushes the Row to the bottom
          children: [
            // Add padding to control spacing from the edges of the AppBar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  // The scrollable list of tabs, expanded to take available space
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _Chip(text: 'История продаж', icon: Icons.history),
                          SizedBox(width: 5),
                          _TicketTab(
                              text: 'Чек № 234567 | 10 товаров', active: true),
                          SizedBox(width: 5),
                          _TicketTab(text: 'Чек № 234567 | 10 товаров'),
                          SizedBox(width: 5),
                          TextButton(
                              onPressed: () {},
                              child: Text(
                                '+ Отложка',
                                style: TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400),
                              ))
                        ],
                      ),
                    ),
                  ),
                  // Spacer between the scrollable list and the action buttons
                  const SizedBox(width: 12),
                  // The action buttons on the right
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBtn(
                          icon: Icons.shopping_bag_outlined,
                          onPressed: () {/* TODO */}),
                      _IconBtn(
                        icon: Icons.now_widgets_rounded,
                        onPressed: () => showPosActionsDialog(context),
                      ),
                      _IconBtn(
                          icon: Icons.person_outline,
                          onPressed: () {/* TODO */}),
                      const SizedBox(width: 12),
                      const _StatusDot(),
                      const SizedBox(width: 12),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketTab extends StatelessWidget {
  final String text;
  final bool active;
  const _TicketTab({required this.text, this.active = false});

  @override
  Widget build(BuildContext context) {
    final bg = active ? Color(0xFFF3F4F6) : const Color(0xFF536074);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Text(text,
          style: TextStyle(
              color: active ? Colors.black : Colors.white70, fontSize: 12)),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Chip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF536074),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _IconBtn({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white70),
      tooltip: '', // без тултипа
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Қанат C', style: TextStyle(color: Colors.white70)),
        const SizedBox(width: 8),
        Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
                color: Colors.green, shape: BoxShape.circle)),
      ],
    );
  }
}

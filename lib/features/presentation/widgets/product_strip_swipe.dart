import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/features/data/utils/app_theme.dart';

class QuickProduct {
  final String title;
  final double price;
  const QuickProduct({required this.title, required this.price});
}

Future<QuickProduct?> showQuickProductsDialog(
  BuildContext context, {
  required List<QuickProduct> products,
}) {
  return showDialog<QuickProduct?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _QuickProductsDialog(products: products),
  );
}

class _QuickProductsDialog extends StatefulWidget {
  const _QuickProductsDialog({required this.products});

  final List<QuickProduct> products;

  @override
  State<_QuickProductsDialog> createState() => _QuickProductsDialogState();
}

class _QuickProductsDialogState extends State<_QuickProductsDialog> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ThemeColors.greyB, // ✅ серый фон как на скрине
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cols = w > 880
                  ? 6
                  : w > 720
                      ? 5
                      : w > 560
                          ? 4
                          : 3;

              return Column(
                children: [
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(6),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: widget.products.length,
                      itemBuilder: (context, i) {
                        final p = widget.products[i];
                        return _QuickProductCard(
                          title: p.title,
                          price: p.price,
                          selected: _selectedIndex == i,
                          onTap: () {
                            setState(() => _selectedIndex = i);
                            Navigator.of(context).pop(p); // ✅ выбрать и закрыть
                          },
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 170,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD45F4F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text(
                          'ЗАКРЫТЬ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuickProductCard extends StatefulWidget {
  const _QuickProductCard({
    required this.title,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final double price;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_QuickProductCard> createState() => _QuickProductCardState();
}

class _QuickProductCardState extends State<_QuickProductCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final showBlue = widget.selected || _hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 90,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // квадрат "картинки"
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white, // ✅ белый как на скрине
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        showBlue ? const Color(0xFF1D9BFF) : Colors.transparent,
                    width: showBlue ? 2 : 0,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.add, size: 26, color: Colors.black),
                ),
              ),
              const SizedBox(height: 10),

              // название
              SizedBox(
                width: 120,
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // цена (пилюля)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                      color: Colors.black.withOpacity(0.08),
                    ),
                  ],
                ),
                child: Text(
                  '${widget.price.toStringAsFixed(2)} ₸',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

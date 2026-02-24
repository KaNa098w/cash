import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/models/product_response.dart';
import 'package:pos_desktop_clean/features/data/utils/app_theme.dart';

Future<ProductModel?> showQuickProductsDialog(
  BuildContext context, {
  required List<ProductModel> products,
}) {
  return showDialog<ProductModel?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: ThemeColors.greyB,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                        itemCount: products.length,
                        itemBuilder: (context, i) {
                          final p = products[i];
                          return _QuickProductTile(
                            title: p.name,
                            price: p.sellingPrice,
                            onTap: () => Navigator.of(ctx).pop(p),
                          );
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 240,
                        height: 64,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD45F4F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          child: const Text(
                            'ЗАКРЫТЬ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
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
    },
  );
}

class _QuickProductTile extends StatelessWidget {
  const _QuickProductTile({
    required this.title,
    required this.price,
    required this.onTap,
  });

  final String title;
  final double price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeColors.white, // ✅ фон карточки как у диалога
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: _ProductCard(title: title, price: price),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.price,
  });

  final String title;
  final double price;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 100,
                  height: 100,
                  color: ThemeColors.white, // ✅ фон "картинки" greyB
                ),
              ),
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.add, size: 20, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SizedBox(
              width: 120,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                  height: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: ThemeColors.white, // ✅ фон цены тоже greyB
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${price.toStringAsFixed(2)} ₸',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}



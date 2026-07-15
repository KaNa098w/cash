import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/utils/money.dart';

Future<ProductModel?> showQuickProductsDialog(
  BuildContext context, {
  required List<ProductModel> products,
}) {
  return showDialog<ProductModel?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFFF6F7F9),
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width > 880
                  ? 6
                  : width > 720
                      ? 5
                      : width > 560
                          ? 4
                          : 3;

              return Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Быстрые товары',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Выберите товар для добавления в корзину',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: products.isEmpty
                        ? const _EmptyQuickProducts()
                        : GridView.builder(
                            padding: const EdgeInsets.all(6),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return _QuickProductTile(
                                product: product,
                                onTap: () => Navigator.of(ctx).pop(product),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _QuickProductTile extends StatelessWidget {
  const _QuickProductTile({required this.product, required this.onTap});

  final ProductModel product;
  final VoidCallback onTap;

  String get _quantityLabel {
    final value = ProductModel.isPiecesMeasurementUnit(product.measurementUnit)
        ? product.quantity.round().toString()
        : product.quantity
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.?0+$'), '');
    return '$value ${product.measurementUnit}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: _ProductImage(url: product.coverUrl),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _quantityLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    money(product.effectivePrice),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF456B5A),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final safeUrl = url?.trim() ?? '';
    final uri = Uri.tryParse(safeUrl);
    if (uri == null || !uri.isAbsolute) return const _NoPhoto();

    return Image.network(
      safeUrl,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _NoPhoto(),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const ColoredBox(
              color: Color(0xFFF1F3F5),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF1F3F5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 30, color: Color(0xFF9CA3AF)),
            SizedBox(height: 6),
            Text(
              'Нет фото',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyQuickProducts extends StatelessWidget {
  const _EmptyQuickProducts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF9CA3AF)),
          SizedBox(height: 12),
          Text(
            'Быстрые товары не найдены',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

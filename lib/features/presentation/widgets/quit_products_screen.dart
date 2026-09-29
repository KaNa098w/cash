import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';

final _quickProductsMemory = <String, List<ProductModel>>{};

Future<ProductModel?> showQuickProductsDialog(
  BuildContext context, {
  required String key,
  required String deviceId,
}) {
  return showDialog<ProductModel?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _QuickProductsDialog(posKey: key, deviceId: deviceId),
  );
}

class _QuickProductsDialog extends StatefulWidget {
  const _QuickProductsDialog({required this.posKey, required this.deviceId});

  final String posKey;
  final String deviceId;

  @override
  State<_QuickProductsDialog> createState() => _QuickProductsDialogState();
}

class _QuickProductsDialogState extends State<_QuickProductsDialog> {
  List<ProductModel> products = const [];
  bool loading = true;
  StreamSubscription<void>? subscription;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final cached = _quickProductsMemory[widget.posKey];
    if (cached != null) {
      products = cached;
      loading = false;
    }
    final sync = sl<PosSyncService>();
    subscription = sync.onProductsChanged.listen((_) => _loadLocal());
    _loadLocal();
    if (widget.deviceId.isNotEmpty) {
      unawaited(sync
          .pullOnce(
            key: widget.posKey,
            deviceId: widget.deviceId,
            refreshPosInfoAfterPull: false,
          )
          .catchError((Object _) {}));
    }
  }

  Future<void> _loadLocal() async {
    final generation = ++_loadGeneration;
    try {
      final items = (await sl<PosSyncService>().loadFavoriteProducts())
          .where((product) => !product.isUniversal)
          .toList(growable: false);
      if (!mounted || generation != _loadGeneration) return;
      final oldSignature = jsonEncode(products.map((p) => p.toJson()).toList());
      final newSignature = jsonEncode(items.map((p) => p.toJson()).toList());
      _quickProductsMemory[widget.posKey] = items;
      if (oldSignature != newSignature || loading) {
        setState(() {
          products = items;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
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
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : products.isEmpty
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
                                      onTap: () =>
                                          Navigator.of(context).pop(product),
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

class _ProductImage extends StatefulWidget {
  const _ProductImage({required this.url});

  final String? url;

  @override
  State<_ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<_ProductImage> {
  FileInfo? _file;
  StreamSubscription<FileResponse>? _subscription;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _subscription?.cancel();
      _file = null;
      _load();
    }
  }

  void _load() {
    final url = widget.url?.trim() ?? '';
    if (kIsWeb || Uri.tryParse(url)?.isAbsolute != true) return;
    _subscription = DefaultCacheManager().getFileStream(url).listen(
      (response) {
        if (response is FileInfo && mounted) {
          if (_file?.file.path == response.file.path) {
            FileImage(response.file).evict();
          }
          setState(() => _file = response);
        }
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeUrl = widget.url?.trim() ?? '';
    final uri = Uri.tryParse(safeUrl);
    if (uri == null || !uri.isAbsolute) return const _NoPhoto();

    if (!kIsWeb) {
      final file = _file?.file;
      return file == null
          ? const ColoredBox(
              color: Color(0xFFF1F3F5),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Image.file(
              file,
              key: ValueKey(file.path),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _NoPhoto(),
            );
    }

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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/models/product_response.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_state.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/customer_create_page.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/onscreen_keyboar_widget.dart';
import '../state/pos_cubit.dart';
import 'package:pos_desktop_clean/features/pos/data/utils/app_theme.dart';

class SearchBar extends StatefulWidget {
  const SearchBar({super.key});

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();

  OverlayEntry? _chooserEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
      _ensureValidSelection();
    });
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _ensureValidSelection();
      } else {
        Future.microtask(() => _focusNode.requestFocus());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _removeChooser();
    super.dispose();
  }

  void _ensureValidSelection() {
    final sel = _controller.selection;
    if (sel.start < 0 || sel.end < 0) {
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  void _openKeyboard() async {
    // прячем список товаров, чтобы не мешал
    _removeChooser();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, // ← ВАЖНО
      builder: (_) {
        return OnScreenKeyboardSheet(
          controller: _controller,
          onEnter: () {
            Navigator.of(context).pop();
            _doSearch();
          },
        );
      },
    );

    // после закрытия верни фокус в поле
    if (mounted) {
      _focusNode.requestFocus();
      _ensureValidSelection();
    }
  }

  void _removeChooser() {
    _chooserEntry?.remove();
    _chooserEntry = null;
  }

  void _doSearch() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      _removeChooser();
      return;
    }

    final productsCubit = context.read<ProductsCubit>();
    final state = productsCubit.state;

    if (state is! ProductsLoaded) {
      debugPrint('🔴 ProductsCubit state не Loaded: $state');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Товары ещё не загружены')),
      );
      return;
    }

    final all = state.products;
    debugPrint('📦 Всего товаров в памяти: ${all.length}');

    final q = query.toLowerCase();

    final matches = all.where((p) {
      final name = p.name.toLowerCase();
      final barcodeStr = p.barcode?.toString() ?? '';
      final localCodeStr = p.localBarcode?.toString() ?? '';

      if (name.contains(q)) return true;
      if (barcodeStr.contains(q)) return true;
      if (localCodeStr.contains(q)) return true;

      return false;
    }).toList();

    debugPrint('🔎 Найдено совпадений: ${matches.length}');

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Товар не найден: "$query"')),
      );
      _removeChooser();
      return;
    }

    _showProductChooser(matches);
  }

  void _showProductChooser(List<ProductModel> products) {
    _removeChooser();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _chooserEntry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final theme = Theme.of(ctx);

        final fieldBox =
            _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final fieldSize = fieldBox?.size;
        final fieldHeight = fieldSize?.height ?? 56.0;
        final fieldWidth = fieldSize?.width ?? 400.0;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeChooser,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, fieldHeight + 4),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: fieldWidth,
                  constraints: BoxConstraints(
                    maxHeight: size.height * 0.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Padding(
                      //   padding: const EdgeInsets.symmetric(
                      //     horizontal: 12,
                      //     vertical: 8,
                      //   ),
                      //   child: Row(
                      //     children: [
                      //       Expanded(
                      //         child: Text(
                      //           'Выберите товар',
                      //           style: theme.textTheme.titleSmall?.copyWith(
                      //             fontWeight: FontWeight.bold,
                      //           ),
                      //         ),
                      //       ),
                      //       IconButton(
                      //         tooltip: 'Закрыть',
                      //         icon: const Icon(Icons.close),
                      //         onPressed: _removeChooser,
                      //       ),
                      //     ],
                      //   ),
                      // ),
                      // const Divider(height: 1),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: products.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final p = products[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                p.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                [
                                  if (p.barcode != null) 'ШК: ${p.barcode}',
                                  if (p.localBarcode != null)
                                    'Код: ${p.localBarcode}',
                                  'Ед.: ${p.measurementUnit}',
                                ].where((e) => e.isNotEmpty).join(' • '),
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text(
                                p.sellingPrice.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: () {
                                context.read<PosCubit>().addFromProductModel(p);
                                _controller.clear();
                                _removeChooser();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_chooserEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(2),
            child: CompositedTransformTarget(
              link: _layerLink,
              child: Container(
                key: _fieldKey,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ThemeColors.grey, width: 15),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  onSubmitted: (_) => _doSearch(),
                  onChanged: (_) {
                    // если стер текст — прячем список
                    if (_controller.text.trim().isEmpty) {
                      _removeChooser();
                    }
                  },
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 0,
                    ),
                    hintText: 'Введите наименование товара или код товара',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    suffixIconConstraints: const BoxConstraints(
                      minHeight: 32,
                      minWidth: 32,
                    ),
                    suffixIcon: SizedBox(
                      width: 80,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Экранная клавиатура',
                            icon: const Icon(Icons.keyboard),
                            onPressed: _openKeyboard,
                          ),
                          IconButton(
                            tooltip: 'Найти',
                            icon: const Icon(Icons.search),
                            onPressed: _doSearch,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ThemeColors.grey, width: 15),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CustomerCreatePage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: const Text('Покупатель'),
            ),
          ),
        ),
      ],
    );
  }
}

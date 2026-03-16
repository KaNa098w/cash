import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_state.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_dialog.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_page.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import '../products/state/pos_cubit.dart';

class SearchBar extends StatefulWidget {
  const SearchBar({super.key});

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _allowAutoRefocus = true;
  bool _disableSearchFieldForIpad = false;

  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  bool _keyboardOpen = false;
  Timer? _scanDebounce;
  Timer? _typingDebounce;
  OverlayEntry? _chooserEntry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      _disableSearchFieldForIpad = false;
      return;
    }
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    _disableSearchFieldForIpad = shortestSide >= 600;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disableSearchFieldForIpad && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
      _ensureValidSelection();
    });
    _focusNode.addListener(() {
      if (_disableSearchFieldForIpad || !_allowAutoRefocus) return;

      if (_focusNode.hasFocus) {
        _ensureValidSelection();
      } else {
        Future.microtask(() {
          if (mounted && _allowAutoRefocus && !_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
        });
      }
    });
  }

  void _onControllerTextChanged() {
    _onQueryChanged('');
  }

  void _onQueryChanged(String _) {
    final raw = _controller.text;

    // сканеры часто шлют \n/\r в конце
    if (raw.contains('\n') || raw.contains('\r')) {
      final cleaned = raw.replaceAll(RegExp(r'[\r\n]+'), '');
      _controller.text = cleaned;
      _controller.selection = TextSelection.collapsed(offset: cleaned.length);
      _doSearch();
      return;
    }

    final q = raw.trim();
    if (q.isEmpty) {
      _typingDebounce?.cancel();
      _removeChooser();
      return;
    }

    // если похоже на штрихкод — делаем быстрый автосабмит
    if (RegExp(r'^\d{8,}$').hasMatch(q)) {
      _typingDebounce?.cancel();
      _scanDebounce?.cancel();
      _scanDebounce = Timer(const Duration(milliseconds: 80), _doSearch);
      return;
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 220), _doSearch);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _removeChooser();
    super.dispose();
    _scanDebounce?.cancel();
    _typingDebounce?.cancel();
  }

  Future<T?> _runWithDialogFocus<T>(Future<T?> Function() open) async {
    // Снимаем фокус и запрещаем авто-возврат фокуса
    _allowAutoRefocus = false;
    _removeChooser();

    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();

    try {
      return await open();
    } finally {
      // Возвращаем поведение обратно
      _allowAutoRefocus = true;

      if (mounted) {
        // Дать кадр на закрытие диалога
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_disableSearchFieldForIpad) {
            _focusNode.requestFocus();
            _ensureValidSelection();
          }
        });
      }
    }
  }

  void _openKeyboard() {
    if (_keyboardOpen) return;
    _keyboardOpen = true;

    _runWithDialogFocus(() {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.15),
        builder: (ctx) {
          return OnScreenKeyboardSheet(
            controllerGetter: () => _controller,
            onEnter: _doSearch,
            onClose: () => Navigator.of(ctx).pop(),
          );
        },
      );
    }).whenComplete(() {
      _keyboardOpen = false;
    });
  }

  Future<void> _openCameraScanner() async {
    String? extractCode(BarcodeCapture capture) {
      for (final b in capture.barcodes) {
        final v = b.rawValue?.trim() ?? '';
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    final scanned = await _runWithDialogFocus(() async {
      bool handled = false;

      return showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.black,
        builder: (ctx) {
          final h = MediaQuery.of(ctx).size.height * 0.76;
          return SafeArea(
            child: SizedBox(
              height: h,
              child: Stack(
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      if (handled) return;
                      final code = extractCode(capture);
                      if (code == null) return;
                      handled = true;
                      Navigator.of(ctx).pop(code);
                    },
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });

    if (!mounted) return;
    final code = (scanned ?? '').trim();
    if (code.isEmpty) return;
    _controller.text = code;
    _controller.selection = TextSelection.collapsed(offset: code.length);
    _doSearch();
  }

  void _ensureValidSelection() {
    final sel = _controller.selection;
    if (sel.start < 0 || sel.end < 0) {
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Товары ещё не загружены')),
      );
      return;
    }

    final all = state.products;
    final q = query.toLowerCase();

    final matches = all.where((p) {
      final name = p.name.toLowerCase();
      final barcodeStr = (p.barcode?.toString() ?? '').toLowerCase();
      final localCodeStr = (p.localBarcode?.toString() ?? '').toLowerCase();

      // ✅ если похоже на штрихкод — лучше искать точным совпадением
      final isBarcodeLike = RegExp(r'^\d{8,}$').hasMatch(query);

      if (isBarcodeLike) {
        if (barcodeStr == q) return true;
        if (localCodeStr == q) return true;
        return false;
      }

      // обычный поиск по имени/частичному совпадению
      if (name.contains(q)) return true;
      if (barcodeStr.contains(q)) return true;
      if (localCodeStr.contains(q)) return true;
      return false;
    }).toList();

    if (matches.isEmpty) {
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Товар не найден: "$query"')),
      // );
      _removeChooser();
      return;
    }

    // ✅ если найден 1 товар — сразу добавляем в продажу
    if (matches.length == 1) {
      final p = matches.first;
      context.read<PosCubit>().addFromProductModel(p);

      _controller.clear();
      _removeChooser();
      if (!_disableSearchFieldForIpad) _focusNode.requestFocus();
      return;
    }

    // ✅ если несколько — показываем chooser (как раньше)
    _showProductChooser(matches);
  }

  void _showProductChooser(List<ProductModel> products) {
    _removeChooser();

    final overlay = Overlay.of(context);

    _chooserEntry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;

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
              offset: Offset(0, fieldHeight + 6),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: fieldWidth,
                  constraints: BoxConstraints(
                    maxHeight: size.height * 0.6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: products.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 0.1),
                          itemBuilder: (_, index) {
                            final p = products[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                '${p.name} (${p.quantity})',
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                [
                                  if (p.barcode != null) 'ШК: ${p.barcode}',
                                  // if (p.localBarcode != null)
                                  //   'Код: ${p.localBarcode}',
                                  // 'Ед.: ${p.measurementUnit}',
                                ].where((e) => e.isNotEmpty).join(' • '),
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text(
                                '${p.sellingPrice.toStringAsFixed(2)} т',
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
    final isMobileCameraCapable = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactDesktop = screenWidth <= 1100;
    final customerGapWidth = compactDesktop ? 8.0 : 12.0;
    final buyerBtnFontSize = compactDesktop ? 16.0 : 18.0;

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(2),
            child: CompositedTransformTarget(
              link: _layerLink,
              child: Container(
                key: _fieldKey,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: !_disableSearchFieldForIpad,
                  canRequestFocus: !_disableSearchFieldForIpad,
                  readOnly: _disableSearchFieldForIpad,
                  showCursor: !_disableSearchFieldForIpad,
                  enableInteractiveSelection: !_disableSearchFieldForIpad,
                  onSubmitted: (_) => _doSearch(),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 18),
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
                      minHeight: 42,
                      minWidth: 42,
                    ),
                    suffixIcon: SizedBox(
                      // width: 80,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // IconButton(
                          //   tooltip: 'Экранная клавиатура',
                          //   icon: const Icon(Icons.keyboard),
                          //   onPressed: _openKeyboard,
                          // ),
                          IconButton(
                            tooltip: 'Найти',
                            icon: SvgPicture.asset(
                              'assets/svg/search.svg',
                              width: 20,
                              height: 20,
                            ),
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
        SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey, width: 1.2),
            borderRadius: BorderRadius.circular(7),
          ),
          child: IconButton(
            tooltip: 'Клавитура',
            icon: SvgPicture.asset(
              'assets/svg/keyboard.svg',
              width: 20,
              height: 20,
            ),
            onPressed: _openKeyboard,
          ),
        ),
        if (isMobileCameraCapable) ...[
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey, width: 1.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: IconButton(
              tooltip: 'Сканер штрихкода',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _openCameraScanner,
            ),
          ),
        ],
        const SizedBox(width: 16),
        OutlinedButton(
          onPressed: () async {
            final auth = context.read<AuthTokenProvider>();
            final posKey = auth.posKey?.trim() ?? '';
            if (posKey.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('posKey пустой')),
              );
              return;
            }

            try {
              final ds = sl<CustomersRemoteDataSource>();

              // ✅ загрузили клиентов
              final dtos = await ds.listCustomers(key: posKey);

              final customers = dtos
                  .map((e) => CustomerLite(
                        id: e.id,
                        name: e.name,
                        phone: e.phone,
                        balance: 0,
                      ))
                  .toList();

              final selected = await _runWithDialogFocus(() {
                return showCustomerPickerDialog(
                  context,
                  customers: customers,
                );
              });

              if (selected == null) return;
              context.read<PosCubit>().setCustomerForActiveTicket(
                    PosCustomer(
                      id: selected.id,
                      name: selected.name,
                      phone: selected.phone,
                    ),
                  );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Не удалось загрузить клиентов: $e'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black, width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          child: Text(
            'Покупатель',
            style: TextStyle(fontSize: buyerBtnFontSize),
          ),
        ),
        SizedBox(width: 200),
        BlocBuilder<PosCubit, PosState>(
          buildWhen: (prev, next) =>
              prev.activeTicket.customer != next.activeTicket.customer,
          builder: (context, state) {
            final c = state.activeTicket.customer;
            if (c == null) {
              return const Text(
                ' ',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBD7FF)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, size: 18),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      c.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () =>
                        context.read<PosCubit>().clearCustomerForActiveTicket(),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

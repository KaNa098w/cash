import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:leemon_app/features/presentation/pages/search/search_keyboard_controller.dart';
import 'package:leemon_app/features/presentation/widgets/conversion_product_dialog.dart';
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
  bool _openingCustomerPicker = false;
  DateTime? _lastHardwareDigitAt;
  String? _pendingHardwareDigit;
  bool _hardwareScanMode = false;
  Timer? _hardwareScanResetTimer;

  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  bool _keyboardOpen = false;
  OverlayEntry? _keyboardEntry;
  Timer? _scanDebounce;
  Timer? _typingDebounce;
  OverlayEntry? _chooserEntry;
  Timer? _routeFocusRestoreTimer;
  List<ProductModel> _chooserProducts = const [];
  int _chooserSelectedIndex = 0;

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
        _routeFocusRestoreTimer?.cancel();
        _routeFocusRestoreTimer = null;
        _ensureValidSelection();
      } else {
        _closeKeyboard();
        _removeChooser();
        _scheduleSearchFocusRestore();
      }
    });
    searchKeyboardCloseSignal.addListener(_handleExternalKeyboardCloseRequest);
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
    searchKeyboardCloseSignal.removeListener(
      _handleExternalKeyboardCloseRequest,
    );
    _closeKeyboard();
    _controller.dispose();
    _focusNode.dispose();
    _removeChooser();
    super.dispose();
    _scanDebounce?.cancel();
    _typingDebounce?.cancel();
    _hardwareScanResetTimer?.cancel();
    _routeFocusRestoreTimer?.cancel();
  }

  void _handleExternalKeyboardCloseRequest() {
    if (!mounted) return;
    _dismissSearchKeyboard();
  }

  bool get _isRouteCurrent => ModalRoute.of(context)?.isCurrent ?? true;
  bool get _isHistoryMode => context.read<PosCubit>().state.isHistoryMode;

  void _scheduleSearchFocusRestore() {
    if (!mounted ||
        _disableSearchFieldForIpad ||
        !_allowAutoRefocus ||
        _isHistoryMode) {
      return;
    }

    if (_isRouteCurrent) {
      _routeFocusRestoreTimer?.cancel();
      _routeFocusRestoreTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _disableSearchFieldForIpad ||
            !_allowAutoRefocus ||
            _isHistoryMode ||
            !_isRouteCurrent ||
            _focusNode.hasFocus) {
          return;
        }
        _focusNode.requestFocus();
        _ensureValidSelection();
      });
      return;
    }

    _routeFocusRestoreTimer ??=
        Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted || _disableSearchFieldForIpad || !_allowAutoRefocus) {
        timer.cancel();
        _routeFocusRestoreTimer = null;
        return;
      }
      if (_isHistoryMode || !_isRouteCurrent) return;
      timer.cancel();
      _routeFocusRestoreTimer = null;
      if (_focusNode.hasFocus) return;
      _focusNode.requestFocus();
      _ensureValidSelection();
    });
  }

  Future<T?> _runWithDialogFocus<T>(
    Future<T?> Function() open, {
    bool restoreFocus = true,
  }) async {
    // Снимаем фокус и запрещаем авто-возврат фокуса
    _allowAutoRefocus = false;
    _removeChooser();

    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();

    try {
      return await open();
    } finally {
      // Возвращаем поведение обратно
      _allowAutoRefocus = restoreFocus;

      if (mounted && restoreFocus) {
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
    _allowAutoRefocus = true;
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
      _ensureValidSelection();
    }
    if (_keyboardOpen) return;
    _keyboardOpen = true;

    _keyboardEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: double.infinity,
              child: OnScreenKeyboardSheet(
                controllerGetter: () => _controller,
                onEnter: _doSearch,
                onClose: _dismissSearchKeyboard,
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_keyboardEntry!);
  }

  void _closeKeyboard() {
    if (!_keyboardOpen && _keyboardEntry == null) return;
    _keyboardOpen = false;
    _keyboardEntry?.remove();
    _keyboardEntry = null;
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

  void _restoreSearchFocus() {
    if (!mounted || _disableSearchFieldForIpad) return;
    _allowAutoRefocus = true;
    _scheduleSearchFocusRestore();
  }

  void _dismissSearchKeyboard() {
    _allowAutoRefocus = false;
    _closeKeyboard();
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    _removeChooser();
  }

  void _insertSearchText(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final newText = value.text.replaceRange(start, end, text);
    final newOffset = start + text.length;

    _controller.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }

  void _replaceSearchText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  void _scheduleHardwareScanReset() {
    _hardwareScanResetTimer?.cancel();
    _hardwareScanResetTimer = Timer(
      const Duration(milliseconds: 180),
      _resetHardwareScanState,
    );
  }

  void _resetHardwareScanState() {
    _lastHardwareDigitAt = null;
    _pendingHardwareDigit = null;
    _hardwareScanMode = false;
    _hardwareScanResetTimer?.cancel();
    _hardwareScanResetTimer = null;
  }

  void _startHardwareScan() {
    final now = DateTime.now();
    _lastHardwareDigitAt = now;
    _hardwareScanMode = true;
    _scheduleHardwareScanReset();
  }

  void _backspaceSearchText() {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;

    if (start != end) {
      _controller.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
        composing: TextRange.empty,
      );
      return;
    }

    if (start == 0) return;

    _controller.value = value.copyWith(
      text: value.text.replaceRange(start - 1, start, ''),
      selection: TextSelection.collapsed(offset: start - 1),
      composing: TextRange.empty,
    );
  }

  String? _digitFromPhysicalKey(PhysicalKeyboardKey key) {
    final digits = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.digit0: '0',
      PhysicalKeyboardKey.digit1: '1',
      PhysicalKeyboardKey.digit2: '2',
      PhysicalKeyboardKey.digit3: '3',
      PhysicalKeyboardKey.digit4: '4',
      PhysicalKeyboardKey.digit5: '5',
      PhysicalKeyboardKey.digit6: '6',
      PhysicalKeyboardKey.digit7: '7',
      PhysicalKeyboardKey.digit8: '8',
      PhysicalKeyboardKey.digit9: '9',
      PhysicalKeyboardKey.numpad0: '0',
      PhysicalKeyboardKey.numpad1: '1',
      PhysicalKeyboardKey.numpad2: '2',
      PhysicalKeyboardKey.numpad3: '3',
      PhysicalKeyboardKey.numpad4: '4',
      PhysicalKeyboardKey.numpad5: '5',
      PhysicalKeyboardKey.numpad6: '6',
      PhysicalKeyboardKey.numpad7: '7',
      PhysicalKeyboardKey.numpad8: '8',
      PhysicalKeyboardKey.numpad9: '9',
    };

    return digits[key];
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (_disableSearchFieldForIpad ||
        !_focusNode.hasFocus ||
        !_isRouteCurrent ||
        _isHistoryMode) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final logicalKey = event.logicalKey;
    if (_chooserEntry != null && _chooserProducts.isNotEmpty) {
      if (logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveChooserSelection(1);
        return KeyEventResult.handled;
      }

      if (logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveChooserSelection(-1);
        return KeyEventResult.handled;
      }

      if (logicalKey == LogicalKeyboardKey.enter ||
          logicalKey == LogicalKeyboardKey.numpadEnter) {
        _resetHardwareScanState();
        final product = _chooserProducts[_chooserSelectedIndex];
        unawaited(_selectChooserProduct(product));
        return KeyEventResult.handled;
      }
    }

    final digit = _digitFromPhysicalKey(event.physicalKey);
    if (digit != null) {
      final now = DateTime.now();
      final last = _lastHardwareDigitAt;
      final isRapidContinuation = last != null &&
          now.difference(last) <= const Duration(milliseconds: 45);

      if (_hardwareScanMode) {
        _lastHardwareDigitAt = now;
        _scheduleHardwareScanReset();
        _insertSearchText(digit);
        return KeyEventResult.handled;
      }

      if (isRapidContinuation && _pendingHardwareDigit != null) {
        _startHardwareScan();
        _replaceSearchText('${_pendingHardwareDigit!}$digit');
        _pendingHardwareDigit = null;
        return KeyEventResult.handled;
      }

      _pendingHardwareDigit = digit;
      _lastHardwareDigitAt = now;
      _scheduleHardwareScanReset();
      return KeyEventResult.ignored;
    }

    if (event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter) {
      _resetHardwareScanState();
      _doSearch();
      return KeyEventResult.handled;
    }

    if (event.physicalKey == PhysicalKeyboardKey.backspace) {
      if (_hardwareScanMode) {
        _resetHardwareScanState();
        _backspaceSearchText();
        return KeyEventResult.handled;
      }
      _pendingHardwareDigit = null;
      _lastHardwareDigitAt = null;
      return KeyEventResult.ignored;
    }

    _pendingHardwareDigit = null;
    _lastHardwareDigitAt = null;
    return KeyEventResult.ignored;
  }

  void _removeChooser() {
    _chooserEntry?.remove();
    _chooserEntry = null;
    _chooserProducts = const [];
    _chooserSelectedIndex = 0;
  }

  void _moveChooserSelection(int delta) {
    if (_chooserEntry == null || _chooserProducts.isEmpty) return;

    final nextIndex = (_chooserSelectedIndex + delta).clamp(
      0,
      _chooserProducts.length - 1,
    );
    if (nextIndex == _chooserSelectedIndex) return;

    _chooserSelectedIndex = nextIndex;
    _chooserEntry?.markNeedsBuild();
  }

  Future<void> _selectChooserProduct(ProductModel product) async {
    _removeChooser();
    _closeKeyboard();
    final added = await _runWithDialogFocus(
      () => addProductToCartWithConversionFlow(context, product),
      restoreFocus: false,
    );
    if (!mounted) return;
    if (added != true) return;

    _controller.clear();
    _removeChooser();
    _restoreSearchFocus();
  }

  Future<void> _doSearch() async {
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
      _removeChooser();
      _closeKeyboard();
      final added = await _runWithDialogFocus(
        () => addProductToCartWithConversionFlow(context, p),
        restoreFocus: false,
      );
      if (!mounted) return;
      if (added != true) return;

      _controller.clear();
      _removeChooser();
      _restoreSearchFocus();
      return;
    }

    // ✅ если несколько — показываем chooser (как раньше)
    _showProductChooser(matches);
  }

  void _showProductChooser(List<ProductModel> products) {
    _removeChooser();
    _chooserProducts = products;
    _chooserSelectedIndex = 0;

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
                            final selected = index == _chooserSelectedIndex;
                            final qtyLabel = (() {
                              final shown = (p.conversionValue != null &&
                                      p.conversionValue! > 0)
                                  ? p.quantity * p.conversionValue!
                                  : p.quantity;
                              return ProductModel.isPiecesMeasurementUnit(
                                p.measurementUnit,
                              )
                                  ? shown.round().toString()
                                  : shown
                                      .toStringAsFixed(2)
                                      .replaceFirst(RegExp(r'\\.?0+\$'), '');
                            })();
                            return MouseRegion(
                              onEnter: (_) {
                                if (_chooserSelectedIndex == index) return;
                                _chooserSelectedIndex = index;
                                _chooserEntry?.markNeedsBuild();
                              },
                              child: Container(
                                color: Colors.transparent,
                                child: ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  title: Text(
                                    '${_shortProductNameKeepEnd(p.name, maxChars: 42)} ($qtyLabel ${p.measurementUnit})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                  /* subtitle: Text(
                                [
                                  if (p.barcode != null) '${p.barcode}',
                                  // if (p.localBarcode != null)
                                  //   'Код: ${p.localBarcode}',
                                  // 'Ед.: ${p.measurementUnit}',
                                ].where((e) => e.isNotEmpty).join(' • '),
                                style: const TextStyle(fontSize: 11),
                              ), */
                                  trailing: Text(
                                    '${p.sellingPrice.toStringAsFixed(2)} т',
                                    style: TextStyle(
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 16,
                                      color: Colors.black,
                                    ),
                                  ),
                                  onTap: () async {
                                    await _selectChooserProduct(p);
                                  },
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 2,
                                  ),
                                ),
                              ),
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

    final routeEntries = ModalRoute.of(context)?.overlayEntries;
    final currentRouteTopEntry =
        routeEntries?.isNotEmpty == true ? routeEntries!.last : null;

    if (_keyboardEntry != null) {
      overlay.insert(_chooserEntry!, below: _keyboardEntry);
    } else if (_keyboardOpen && currentRouteTopEntry != null) {
      overlay.insert(_chooserEntry!, above: currentRouteTopEntry);
    } else {
      overlay.insert(_chooserEntry!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHistoryMode =
        context.select((PosCubit cubit) => cubit.state.isHistoryMode);
    final searchCanRequestFocus = !_disableSearchFieldForIpad && !isHistoryMode;

    if (searchCanRequestFocus && !_focusNode.hasFocus) {
      _scheduleSearchFocusRestore();
    }

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
                child: Focus(
                  onKeyEvent: _handleSearchKeyEvent,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: searchCanRequestFocus,
                    canRequestFocus: searchCanRequestFocus,
                    readOnly: _disableSearchFieldForIpad || isHistoryMode,
                    showCursor: searchCanRequestFocus,
                    enableInteractiveSelection:
                        !_disableSearchFieldForIpad && !isHistoryMode,
                    onTap: _restoreSearchFocus,
                    onTapOutside: (_) => _restoreSearchFocus(),
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
            if (_openingCustomerPicker) return;
            _openingCustomerPicker = true;
            final auth = context.read<AuthTokenProvider>();
            final posKey = auth.posKey?.trim() ?? '';
            if (posKey.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('posKey пустой')),
              );
              _openingCustomerPicker = false;
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
            } finally {
              _openingCustomerPicker = false;
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

String _shortProductNameKeepEnd(String name, {int maxChars = 40}) {
  final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= maxChars) return normalized;

  final parts = normalized.split(' ');
  if (parts.length < 2) {
    return '${normalized.substring(0, maxChars - 3)}...';
  }

  final tail = parts.last;
  final prefixBudget = maxChars - 3 - tail.length;
  if (prefixBudget <= 1) {
    final endLen = (maxChars - 3).clamp(1, tail.length);
    return '...${tail.substring(tail.length - endLen)}';
  }

  var prefix = normalized.substring(0, prefixBudget).trimRight();
  final lastSpace = prefix.lastIndexOf(' ');
  if (lastSpace > 8) {
    prefix = prefix.substring(0, lastSpace).trimRight();
  }

  return '$prefix...$tail';
}

import 'package:leemon_app/core/models/fiscalization_mode.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leemon_app/core/models/marking_check.dart';
import 'package:leemon_app/core/models/product_response.dart'; // ProductModel
import 'package:leemon_app/features/domain/entities/cart_item.dart';
import 'package:leemon_app/features/domain/entities/payment.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';

part 'pos_state.dart';

class PosCubit extends Cubit<PosState> {
  final Map<int, Object> _paymentOperations = {};
  bool get hasPaymentOperations => _paymentOperations.isNotEmpty;

  bool get paymentOperationInProgress =>
      _paymentOperations.containsKey(state.activeTicketId);

  /// The lock belongs to one attempt on one ticket, never to the whole POS.
  /// Background sync does not acquire this lock.
  Object? beginPaymentOperation() {
    final ticketId = state.activeTicketId;
    if (_paymentOperations.containsKey(ticketId)) return null;
    final token = Object();
    _paymentOperations[ticketId] = token;
    return token;
  }

  void endPaymentOperation(int ticketId, Object token) {
    // A late finally from an old panel must not unlock a newer payment.
    if (identical(_paymentOperations[ticketId], token)) {
      _paymentOperations.remove(ticketId);
    }
  }

  String _markingScope = '';
  String get markingScope => _markingScope;
  set markingScope(String value) {
    if (value == _markingScope) return;
    _markingScope = value;
    invalidateMarkingCheck();
  }

  String? lastMarkingCheckAttempt;
  String? _checkedSnapshot;
  MarkingCheckResponse? _markingResponse;
  bool get requiresMarkingCheck => state.items.any((item) =>
      item.product.requiresMarking ||
      item.markCodes.isNotEmpty ||
      item.markingCheck?.requiresMarking == true);

  // Old unresolved requests must still be reconciled online. New ordinary
  // sales persist their background mode together with the original payload.
  bool get requiresOnlinePayment {
    final checkout = state.activeTicket.checkout;
    return requiresMarkingCheck ||
        (checkout != null && checkout['requires_online'] != false);
  }

  String get markingSnapshot => jsonEncode([
        markingScope,
        state.activeTicketId,
        state.items.map((item) => item.toJson()).toList()
      ]);
  bool get markingCheckPassed =>
      state.items.isNotEmpty &&
      (!requiresMarkingCheck ||
          (_checkedSnapshot == markingSnapshot &&
              (_markingResponse?.canPay ?? false)));

  void applyMarkingCheck(String snapshot, MarkingCheckResponse response) {
    if (snapshot != markingSnapshot) return;
    if (state.items.any((item) =>
        !response.items.any((result) => result.productId == item.product.id))) {
      return;
    }
    _checkedSnapshot = snapshot;
    _markingResponse = response;
    final results = {for (final item in response.items) item.productId: item};
    final tickets = state.tickets
        .map((ticket) => ticket.id == state.activeTicketId
            ? ticket.copyWith(
                items: ticket.items
                    .map((item) => item.copyWith(
                        markingCheck: results[item.product.id],
                        clearMarkingCheck:
                            !results.containsKey(item.product.id)))
                    .toList())
            : ticket)
        .toList();
    emit(state.copyWith(tickets: tickets));
  }

  void invalidateMarkingCheck() {
    _checkedSnapshot = null;
    _markingResponse = null;
  }

  void beginMarkingCheck() {
    invalidateMarkingCheck();
    lastMarkingCheckAttempt = markingSnapshot;
    emit(state.copyWith(
        tickets: state.tickets
            .map((ticket) => ticket.copyWith(
                items: ticket.items
                    .map((item) => item.copyWith(clearMarkingCheck: true))
                    .toList()))
            .toList()));
  }

  static const _kPersistedStateKey = 'persisted_pos_state_v1';
  final PosRepository repo;
  Timer? _persistDebounce;
  PosState? _pendingPersistState;
  Future<void> _persistQueue = Future<void>.value();

  PosCubit(this.repo) : super(PosState.initial()) {
    unawaited(_restorePersistedState());
  }

  void _logAddedProductToCart({
    required Product product,
    required double addedQty,
    required double cartQty,
    required bool discountApplied,
  }) {
    final payload = <String, dynamic>{
      'event': 'product_added_to_cart',
      'product': product.toJson(),
      'added_qty': addedQty,
      'cart_qty': cartQty,
      'effective_unit_price': discountApplied && product.priceAfterDiscount > 0
          ? product.priceAfterDiscount
          : product.price,
      'discount_applied': discountApplied,
    };

    developer.log(
      const JsonEncoder.withIndent('  ').convert(payload),
      name: 'PosCubit',
    );
  }

  void _emitAndPersist(PosState nextState) {
    if (!_sameCartContents(nextState.items, state.items) ||
        nextState.activeTicketId != state.activeTicketId) {
      invalidateMarkingCheck();
      nextState = nextState.copyWith(
          tickets: nextState.tickets
              .map((ticket) => ticket.copyWith(
                  items: ticket.items
                      .map((item) => item.copyWith(clearMarkingCheck: true))
                      .toList()))
              .toList());
    }
    emit(nextState);
    _schedulePersistState(nextState);
  }

  // Payment input frequently emits states with the very same basket. Compare
  // its data directly instead of serializing it twice on every key press.
  // Marking results are deliberately excluded, as in CartItem.toJson().
  static bool _sameCartContents(List<CartItem> a, List<CartItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.product != right.product ||
          left.qty != right.qty ||
          left.discount != right.discount ||
          left.customUnitPrice != right.customUnitPrice ||
          left.discountApplied != right.discountApplied ||
          !const ListEquality<String>().equals(left.markCodes, right.markCodes)) {
        return false;
      }
    }
    return true;
  }

  void _schedulePersistState(PosState state) {
    _pendingPersistState = state;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_flushPersistedState()),
    );
  }

  Future<void> _flushPersistedState() {
    final stateToPersist = _pendingPersistState;
    _pendingPersistState = null;
    if (stateToPersist == null) return Future<void>.value();

    _persistQueue = _persistQueue.then((_) => _persistState(stateToPersist));
    return _persistQueue;
  }

  Future<void> flushPendingState() {
    _persistDebounce?.cancel();
    return _flushPersistedState();
  }

  Future<void> _persistState(PosState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPersistedStateKey, jsonEncode(state.toJson()));
    } catch (error, stackTrace) {
      developer.log(
        'Failed to persist POS state',
        name: 'PosCubit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _restorePersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPersistedStateKey);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final restored = PosState.fromJson(decoded);
      super.emit(restored);
    } catch (error, stackTrace) {
      // A partially written preferences file after a power loss must not
      // escape from this unawaited startup task or prevent the empty cart from
      // being usable. SharedPreferences recovery is handled centrally.
      developer.log(
        'Failed to restore persisted POS state',
        name: 'PosCubit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> resetAllLocalState() async {
    _persistDebounce?.cancel();
    _pendingPersistState = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPersistedStateKey);
    emit(PosState.initial());
  }

  @override
  Future<void> close() async {
    await flushPendingState();
    return super.close();
  }

  List<PosTicket> _updateActiveTicketItems(
    List<CartItem> Function(List<CartItem>) updater, {
    bool correctingCheckoutMarking = false,
  }) {
    if (state.activeTicket.invoiceCheckout != null) return state.tickets;
    if (state.activeTicket.checkout != null &&
        !(correctingCheckoutMarking &&
            state.activeTicket.checkout!['needs_marking_check'] == true)) {
      return state.tickets;
    }
    final tickets = [...state.tickets];
    final idx = tickets.indexWhere((t) => t.id == state.activeTicketId);

    if (idx == -1) {
      final newItems = updater(const []);
      tickets.add(PosTicket(id: state.activeTicketId, items: newItems));
    } else {
      final ticket = tickets[idx];
      final newItems = updater(ticket.items);
      tickets[idx] = ticket.copyWith(items: newItems);
    }

    return tickets;
  }

  Product _mapProductModelToProduct(ProductModel m) {
    final id =
        (m.id?.toString().isNotEmpty ?? false) ? m.id!.toString() : m.name;

    return Product(
      id: id,
      name: m.name,
      price: m.sellingPrice,
      arrivalCost: m.arrivalCost,
      vat: 0,
      quantity: m.quantity,
      measurementUnit: m.measurementUnit,
      coverUrl: m.coverUrl,
      images: m.images,
      conversionValue: m.conversionValue,
      conversionUnit: m.conversionUnit,
      isUniversal: m.isUniversal,
      requiresMarking: m.requiresMarking,
      gtin: m.gtin,
      ntin: m.ntin,
      discountType: m.discountType,
      discountPercent: m.discountPercent,
      priceAfterDiscount: m.priceAfterDiscount,
    );
  }

  String ensureClientSaleId() {
    final existing = state.activeTicket.clientSaleId;
    if (existing != null) return existing;
    final id = const Uuid().v4();
    _emitAndPersist(state.copyWith(
        tickets: state.tickets
            .map((t) =>
                t.id == state.activeTicketId ? t.copyWith(clientSaleId: id) : t)
            .toList()));
    return id;
  }

  Future<void> saveCheckout(Map<String, dynamic> checkout, {int? ticketId}) async {
    final targetId = ticketId ?? state.activeTicketId;
    final ticket = state.tickets.firstWhere((t) => t.id == targetId);
    if (ticket.invoiceCheckout != null) {
      throw StateError('Сначала завершите выставление счёта');
    }
    _emitAndPersist(state.copyWith(
        tickets: state.tickets
            .map((t) => t.id == targetId
                ? t.copyWith(checkout: checkout)
                : t)
            .toList()));
    await flushPendingState();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _kPersistedStateKey, jsonEncode(state.toJson()))) {
      throw StateError('Не удалось сохранить оплату на устройстве');
    }
  }

  Future<void> saveInvoiceCheckout(
      int ticketId, Map<String, dynamic> value) async {
    final ticket = state.tickets.firstWhere((t) => t.id == ticketId);
    if (ticket.checkout != null) {
      throw StateError('Сначала завершите текущую оплату');
    }
    if (ticket.invoiceCheckout != null &&
        jsonEncode(ticket.invoiceCheckout) != jsonEncode(value)) {
      throw StateError(
          'Сохранённый запрос счёта нельзя изменять до получения результата');
    }
    _emitAndPersist(state.copyWith(
        tickets: state.tickets
            .map((t) =>
                t.id == ticketId ? t.copyWith(invoiceCheckout: value) : t)
            .toList()));
    await flushPendingState();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _kPersistedStateKey, jsonEncode(state.toJson()))) {
      throw StateError('Не удалось сохранить счёт на устройстве');
    }
  }

  void releaseInvoiceCheckout(int ticketId) {
    _emitAndPersist(state.copyWith(
        tickets: state.tickets
            .map((t) =>
                t.id == ticketId ? t.copyWith(clearInvoiceCheckout: true) : t)
            .toList()));
  }

  /// Only discard a request known never to have reached either payment system.
  Future<void> recoverPaymentDraft() async {
    if (paymentOperationInProgress) {
      throw StateError('Дождитесь результата текущей оплаты');
    }
    final ticket = state.activeTicket;
    if (ticket.invoiceCheckout != null) {
      throw StateError(
          'Сначала проверьте результат выставления счёта в разделе «Счета»');
    }
    final checkout = ticket.checkout;
    if (checkout != null) {
      if (checkout['sale_request_started'] != false ||
          checkout['kaspi_payment'] != null) {
        throw StateError(
            'Результат оплаты ещё не подтверждён. Откройте оплату этого чека и нажмите «ОПЛАТА» для завершения сохранённого запроса.');
      }
      final sale = checkout['sale'];
      final saleId = sale is Map ? sale['localId'] : null;
      if (saleId == null) {
        throw StateError('Не удалось определить сохранённую оплату');
      }
      final prefs = await SharedPreferences.getInstance();
      final journal = prefs.getString('kaspi.payment.$saleId');
      if (journal != null) {
        final record = jsonDecode(journal);
        if (record is! Map || record['status'] != 'fail') {
          throw StateError(
              'Сначала проверьте результат сохранённой операции Kaspi через оплату этого чека');
        }
      }
    }
    // Recheck after storage access: the user may have started an operation.
    if (paymentOperationInProgress || state.activeTicket != ticket) {
      throw StateError('Состояние чека изменилось. Повторите восстановление');
    }
    _emitAndPersist(state.copyWith(
      paymentKind: PaymentKind.cash,
      received: 0,
      tickets: state.tickets
          .map((t) => t.id == ticket.id ? t.copyWith(clearCheckout: true) : t)
          .toList(),
    ));
    await flushPendingState();
  }

  void releaseCheckout({int? ticketId}) {
    final targetId = ticketId ?? state.activeTicketId;
    _emitAndPersist(state.copyWith(
        tickets: state.tickets
            .map((t) => t.id == targetId
                ? t.copyWith(clearCheckout: true)
                : t)
            .toList()));
  }

  Future<void> releaseDeletedSale(String clientSaleId) async {
    if (clientSaleId.isEmpty) return;
    var changed = false;
    var activeChanged = false;
    final tickets = state.tickets.map((ticket) {
      final sale = ticket.checkout?['sale'];
      final frozenId = sale is Map ? sale['localId']?.toString() : null;
      if (ticket.clientSaleId != clientSaleId && frozenId != clientSaleId) {
        return ticket;
      }
      changed = true;
      activeChanged |= ticket.id == state.activeTicketId;
      return PosTicket(
        id: ticket.id,
        items: ticket.items,
        customer: ticket.customer,
        fiscalizationMode: ticket.fiscalizationMode,
        invoiceCheckout: ticket.invoiceCheckout,
      );
    }).toList();
    if (!changed) return;
    _emitAndPersist(state.copyWith(
      tickets: tickets,
      paymentKind: activeChanged ? PaymentKind.cash : state.paymentKind,
      received: activeChanged ? 0 : state.received,
    ));
    await flushPendingState();
  }

  void completeCheckout(int ticketId) {
    if (state.activeTicketId == ticketId) {
      clearAfterPayment(closeCompletedTicket: true);
      return;
    }
    _emitAndPersist(state.copyWith(
        tickets: state.tickets.where((t) => t.id != ticketId).toList()));
  }

  void clearAfterPayment({bool closeCompletedTicket = false}) {
    if (!closeCompletedTicket && state.activeTicket.hasPendingCheckout) return;
    final tickets = [...state.tickets];
    final idx = tickets.indexWhere((t) => t.id == state.activeTicketId);
    if (idx == -1) return;

    var activeTicketId = state.activeTicketId;
    if (closeCompletedTicket && tickets.length > 1) {
      tickets.removeAt(idx);
      activeTicketId = idx > 0 ? tickets[idx - 1].id : tickets.first.id;
    } else {
      tickets[idx] = PosTicket(id: tickets[idx].id);
    }

    _emitAndPersist(state.copyWith(
      tickets: tickets,
      activeTicketId: activeTicketId,
      received: 0,
      paymentKind: PaymentKind.cash,
      selectedItemIndex: null,
      clearSelection: true,
    ));
  }

  void setCustomerForActiveTicket(PosCustomer customer) {
    if (state.activeTicket.hasPendingCheckout) return;
    final tid = state.activeTicketId;

    final updated = state.tickets.map((t) {
      if (t.id != tid) return t;
      return t.copyWith(customer: customer);
    }).toList();

    _emitAndPersist(state.copyWith(tickets: updated));
  }

  void clearCustomerForActiveTicket() {
    if (state.activeTicket.hasPendingCheckout) return;
    final tid = state.activeTicketId;

    final updated = state.tickets.map((t) {
      if (t.id != tid) return t;
      return t.copyWith(clearCustomer: true);
    }).toList();

    _emitAndPersist(state.copyWith(tickets: updated));
  }

  void selectItem(int index) {
    if (index < 0 || index >= state.items.length) return;
    _emitAndPersist(state.copyWith(selectedItemIndex: index));
  }

  void add(Product p) {
    addWithQty(p, 1);
  }

  bool _shouldApplyServerDiscount(Product product) {
    return product.discountType == 'fixed' &&
        product.priceAfterDiscount > 0 &&
        product.priceAfterDiscount < product.price;
  }

  void addWithQty(
    Product p,
    double qty, {
    List<String> markCodes = const <String>[],
  }) {
    if (qty <= 0 || !qty.isFinite) return;
    if (p.requiresMarking && qty != qty.roundToDouble()) return;

    final normalizedMarkCodes =
        markCodes.where((code) => code.isNotEmpty).toList(growable: false);
    if (markCodes.isNotEmpty) {
      final incomingCodes = normalizedMarkCodes.toSet();
      final existingCodes = state.items
          .expand((item) => item.markCodes)
          .where((code) => code.isNotEmpty)
          .toSet();
      if (normalizedMarkCodes.length != markCodes.length ||
          incomingCodes.length != normalizedMarkCodes.length ||
          incomingCodes.any(existingCodes.contains)) {
        // Last line of defense against duplicate scanner events. Cart updates
        // are synchronous, so a repeated event cannot add quantity twice.
        return;
      }
    }

    int? selectedIndex; // какой индекс выбрать после добавления/увеличения
    double? updatedCartQty;
    bool? updatedDiscountApplied;

    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      final idx = list.indexWhere((e) => e.product.id == p.id);

      if (idx >= 0) {
        final it = list[idx];
        list[idx] = it.copyWith(
          qty: it.qty + qty,
          discountApplied: it.discountApplied || _shouldApplyServerDiscount(p),
          markCodes: [...it.markCodes, ...normalizedMarkCodes],
        );
        updatedCartQty = list[idx].qty;
        updatedDiscountApplied = list[idx].discountApplied;
        selectedIndex = idx;
      } else {
        list.add(CartItem(
          product: p,
          qty: qty,
          discountApplied: _shouldApplyServerDiscount(p),
          markCodes: normalizedMarkCodes,
        ));
        updatedCartQty = list.last.qty;
        updatedDiscountApplied = list.last.discountApplied;
        selectedIndex = list.length - 1;
      }

      return list;
    });

    _emitAndPersist(state.copyWith(
      tickets: tickets,
      selectedItemIndex: selectedIndex,
    ));

    _logAddedProductToCart(
      product: p,
      addedQty: qty,
      cartQty: updatedCartQty ?? qty,
      discountApplied: updatedDiscountApplied ?? false,
    );
  }

  void addFromProductModel(
    ProductModel m, {
    double qty = 1,
    List<String> markCodes = const <String>[],
  }) {
    final product = _mapProductModelToProduct(m);
    addWithQty(product, qty, markCodes: markCodes);
  }

  /// Replaces every cart line with the exact quantity in measurement_unit.
  void setConvertedProductQuantity(ProductModel model, double qty) {
    if (qty <= 0 || qty.isNaN || qty.isInfinite) return;
    final product = _mapProductModelToProduct(model);
    int? selectedIndex;
    final tickets = _updateActiveTicketItems((items) {
      final list = items
          .where((item) => item.product.id != product.id)
          .toList(growable: true);
      list.add(CartItem(
        product: product,
        qty: qty,
        discountApplied: _shouldApplyServerDiscount(product),
      ));
      selectedIndex = list.length - 1;
      return list;
    });
    _emitAndPersist(state.copyWith(
      tickets: tickets,
      selectedItemIndex: selectedIndex,
    ));
  }

  void addUniversalProduct(ProductModel m, {required double price}) {
    if (price <= 0 || price.isNaN || price.isInfinite) return;

    final product = _mapProductModelToProduct(m).copyWith(
      name: 'Универсальный продукт',
      price: double.parse(price.toStringAsFixed(2)),
      quantity: 0,
      measurementUnit: 'шт.',
      clearConversionValue: true,
      clearConversionUnit: true,
      isUniversal: true,
      discountType: 'forbidden',
      discountPercent: 0,
      priceAfterDiscount: 0,
    );

    int? selectedIndex;
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      list.add(CartItem(product: product, qty: 1, discountApplied: false));
      selectedIndex = list.length - 1;
      return list;
    });

    _emitAndPersist(state.copyWith(
      tickets: tickets,
      selectedItemIndex: selectedIndex,
    ));
  }

  void setPrice(int index, double price) {
    if (index < 0 || index >= state.items.length) return;
    if (price <= 0 || price.isNaN || price.isInfinite) return;

    final normalizedPrice = double.parse(price.toStringAsFixed(2));
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        final current = list[index];
        if (current.product.isUniversal) {
          list[index] = current.copyWith(
            product: current.product.copyWith(price: normalizedPrice),
            discount: 0,
            clearCustomUnitPrice: true,
            discountApplied: false,
          );
        } else {
          list[index] = current.copyWith(
            customUnitPrice: normalizedPrice,
            discount: 0,
            discountApplied: false,
          );
        }
      }
      return list;
    });

    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  void setMarkCodes(int index, List<String> codes,
      {bool correctingCheckoutMarking = false}) {
    if (index < 0 || index >= state.items.length) return;
    final normalized =
        codes.where((code) => code.isNotEmpty).toList(growable: false);
    final others = <String>{
      for (var i = 0; i < state.items.length; i++)
        if (i != index) ...state.items[i].markCodes
    };
    if (normalized.length != codes.length ||
        normalized.toSet().length != normalized.length ||
        normalized.any(others.contains)) {
      return;
    }
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      list[index] = list[index].copyWith(markCodes: normalized);
      return list;
    }, correctingCheckoutMarking: correctingCheckoutMarking);
    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  void updateProductFromModel(int index, ProductModel model) {
    if (index < 0 || index >= state.items.length) return;
    final productId = (model.id ?? '').trim();
    if (productId.isEmpty) return;

    final updatedProduct = _mapProductModelToProduct(model);
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        final current = list[index];
        if (current.product.id == productId) {
          list[index] = current.copyWith(
            product: updatedProduct,
            discount: 0,
            clearCustomUnitPrice: true,
            discountApplied: _shouldApplyServerDiscount(updatedProduct),
          );
        }
      }
      return list;
    });

    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  void clearCustomPrice(int index) {
    if (index < 0 || index >= state.items.length) return;
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        final current = list[index];
        if (!current.product.isUniversal) {
          list[index] = current.copyWith(clearCustomUnitPrice: true);
        }
      }
      return list;
    });

    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  void removeAt(int index) {
    final itemsBefore = state.items;
    if (index < 0 || index >= itemsBefore.length) return;

    if (state.activeTicket.hasPendingCheckout) {
      // Keep the immutable payment request under its original ticket ID.
      // Editing a basket must never change an already submitted sale.
      final ticket = state.activeTicket;
      final newId = state.tickets.map((t) => t.id).reduce(
                (a, b) => a > b ? a : b,
              ) +
          1;
      final remaining = List<CartItem>.from(itemsBefore)..removeAt(index);
      _emitAndPersist(state.copyWith(
        tickets: [
          ...state.tickets,
          PosTicket(
            id: newId,
            items: remaining,
            customer: ticket.customer,
            fiscalizationMode: ticket.fiscalizationMode,
          ),
        ],
        activeTicketId: newId,
        paymentKind: PaymentKind.cash,
        received: 0,
        clearSelection: true,
      ));
      return;
    }

    final prevSelected = state.selectedItemIndex;
    int? newSelected = prevSelected;

    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        list.removeAt(index);
      }
      return list;
    });

    if (prevSelected != null) {
      if (prevSelected == index) {
        final newLength = itemsBefore.length - 1;
        if (newLength == 0) {
          newSelected = null;
        } else {
          newSelected = index > 0 ? index - 1 : 0;
        }
      } else if (prevSelected > index) {
        newSelected = prevSelected - 1;
      }
    }

    _emitAndPersist(state.copyWith(
      tickets: tickets,
      selectedItemIndex: newSelected,
    ));
  }

  void setQty(int index, double qty) {
    if (index < 0 || index >= state.items.length || !qty.isFinite) return;
    if (state.items[index].product.requiresMarking &&
        qty != qty.roundToDouble()) {
      return;
    }

    if (qty <= 0) {
      removeAt(index);
      return;
    }

    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        final current = list[index];
        final normalizedQty =
            current.product.requiresMarking || current.product.isUniversal
                ? qty
                : current.product.allowsPartialPackages ||
                        ProductModel.isPiecesMeasurementUnit(
                            current.product.measurementUnit)
                    ? qty.roundToDouble()
                    : current.product.hasConversion
                        ? _normalizeToWholePackages(
                            qty,
                            current.product.conversionValue!,
                          )
                        : qty;
        list[index] = current.copyWith(
          qty: normalizedQty,
          markCodes: current.markCodes,
        );
      }
      return list;
    });

    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  // Увеличить количество у выбранной позиции
  void incrementSelectedQty() {
    final idx = state.selectedItemIndex;
    if (idx == null) return;
    final items = state.items;
    if (idx < 0 || idx >= items.length) return;

    final current = items[idx];
    final step =
        current.product.hasConversion && !current.product.allowsPartialPackages
            ? current.product.conversionValue!
            : 1.0;
    setQty(idx, current.qty + step);
  }

  // Уменьшить количество у выбранной позиции
  void decrementSelectedQty() {
    final idx = state.selectedItemIndex;
    if (idx == null) return;
    final items = state.items;
    if (idx < 0 || idx >= items.length) return;

    final current = items[idx];
    final step =
        current.product.hasConversion && !current.product.allowsPartialPackages
            ? current.product.conversionValue!
            : 1.0;
    final newQty = current.qty - step;
    setQty(idx, newQty);
  }

  static double _normalizeToWholePackages(
    double quantity,
    double conversionValue,
  ) {
    final ratio = double.parse(
      (quantity / conversionValue).toStringAsFixed(9),
    );
    return double.parse(
      (ratio.ceil() * conversionValue).toStringAsFixed(3),
    );
  }

  double get total => state.items.fold<double>(0, (p, e) => p + e.sum);

  double get discountSum => state.items.fold<double>(0, (p, e) {
        if (e.product.isUniversal) return p;
        if (e.discountApplied && e.product.priceAfterDiscount > 0) {
          return p +
              (e.product.price - e.product.priceAfterDiscount) *
                  e.billableQuantity;
        }
        return p + (e.product.price * e.billableQuantity) * (e.discount / 100);
      });

  bool _hasAvailableProductDiscount(CartItem item) {
    return item.product.discountPercent > 0 &&
        item.product.priceAfterDiscount > 0 &&
        item.product.priceAfterDiscount < item.product.price;
  }

  void applyAvailableDiscount(int index) {
    final items = state.items;
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (item.product.isUniversal) return;
    if (item.product.discountType != 'automatic') return;
    if (item.discountApplied || !_hasAvailableProductDiscount(item)) return;

    final tickets = _updateActiveTicketItems((ticketItems) {
      final list = List<CartItem>.from(ticketItems);
      if (index >= 0 && index < list.length) {
        list[index] = list[index].copyWith(
          discount: 0,
          clearCustomUnitPrice: true,
          discountApplied: true,
        );
      }
      return list;
    });
    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  int get availableDiscountCount => state.items
      .where(
        (item) =>
            !item.product.isUniversal &&
            item.product.discountType == 'automatic' &&
            !item.discountApplied &&
            _hasAvailableProductDiscount(item),
      )
      .length;

  void applyAllAvailableDiscounts() {
    if (availableDiscountCount == 0) return;

    final tickets = _updateActiveTicketItems((ticketItems) {
      return ticketItems.map((item) {
        final canApply = !item.product.isUniversal &&
            item.product.discountType == 'automatic' &&
            !item.discountApplied &&
            _hasAvailableProductDiscount(item);
        if (!canApply) return item;
        return item.copyWith(
          discount: 0,
          clearCustomUnitPrice: true,
          discountApplied: true,
        );
      }).toList(growable: false);
    });
    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  void removeAvailableDiscount(int index) {
    final items = state.items;
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (item.product.isUniversal) return;
    if (item.product.discountType != 'automatic') return;
    if (!item.discountApplied) return;

    final tickets = _updateActiveTicketItems((ticketItems) {
      final list = List<CartItem>.from(ticketItems);
      if (index >= 0 && index < list.length) {
        list[index] = list[index].copyWith(
          discountApplied: false,
        );
      }
      return list;
    });
    _emitAndPersist(state.copyWith(tickets: tickets));
  }

  void setFiscalizationMode(FiscalizationMode mode) {
    if (state.activeTicket.hasPendingCheckout) return;
    _emitAndPersist(state.copyWith(
        tickets: state.tickets
            .map((t) => t.id == state.activeTicketId
                ? t.copyWith(fiscalizationMode: mode)
                : t)
            .toList()));
  }

  void setPaymentKind(PaymentKind kind) {
    if (state.activeTicket.hasPendingCheckout) return;
    _emitAndPersist(state.copyWith(paymentKind: kind));
  }

  /// An explicit payment selection starts an editable draft. Keep any earlier
  /// submitted request under its original ID so its outcome is not lost.
  void changePaymentKind(PaymentKind kind) {
    if (paymentOperationInProgress) return;
    final ticket = state.activeTicket;
    if (!ticket.hasPendingCheckout) {
      setPaymentKind(kind);
      return;
    }
    final newId = state.tickets.map((t) => t.id).reduce(
              (a, b) => a > b ? a : b,
            ) +
        1;
    _emitAndPersist(state.copyWith(
      tickets: [
        ...state.tickets,
        PosTicket(
          id: newId,
          items: List<CartItem>.from(ticket.items),
          customer: ticket.customer,
          fiscalizationMode: ticket.fiscalizationMode,
        ),
      ],
      activeTicketId: newId,
      paymentKind: kind,
      received: 0,
      clearSelection: true,
    ));
  }

  void setReceived(double value) {
    if (state.activeTicket.hasPendingCheckout) return;
    _emitAndPersist(state.copyWith(received: value));
  }

  double get change => state.received - total;

  void showHistory() {
    _emitAndPersist(state.copyWith(isHistoryMode: true));
  }

  void showSales() {
    _emitAndPersist(state.copyWith(isHistoryMode: false));
  }

  void closeTicket(int id) {
    final tickets = [...state.tickets];

    if (tickets.length <= 1) {
      // последний чек не трогаем
      return;
    }

    final idx = tickets.indexWhere((t) => t.id == id);
    if (idx == -1 || tickets[idx].hasPendingCheckout) return;

    tickets.removeAt(idx);

    var newActiveId = state.activeTicketId;

    // если удалили активный чек — выбрать соседний
    if (state.activeTicketId == id) {
      if (idx - 1 >= 0) {
        newActiveId = tickets[idx - 1].id;
      } else {
        newActiveId = tickets.first.id;
      }
    }

    _emitAndPersist(
      state.copyWith(
        tickets: tickets,
        activeTicketId: newActiveId,
        clearSelection: true,
      ),
    );
  }

  void createHoldTicket() {
    final ids = state.tickets.map((t) => t.id);
    final lastId = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
    final newId = lastId + 1;

    final newTicket = PosTicket(id: newId, items: const []);

    _emitAndPersist(
      state.copyWith(
        tickets: [...state.tickets, newTicket],
        activeTicketId: newId,
        isHistoryMode: false,
        clearSelection: true,
      ),
    );
  }

  void switchTicket(int id) {
    if (!state.tickets.any((t) => t.id == id)) return;
    _emitAndPersist(
      state.copyWith(
        activeTicketId: id,
        isHistoryMode: false,
        clearSelection: true,
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leemon_app/core/models/product_response.dart'; // ProductModel
import 'package:leemon_app/features/domain/entities/cart_item.dart';
import 'package:leemon_app/features/domain/entities/payment.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';

part 'pos_state.dart';

class PosCubit extends Cubit<PosState> {
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
    emit(nextState);
    _schedulePersistState(nextState);
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
    List<CartItem> Function(List<CartItem>) updater,
  ) {
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

  void clearAfterPayment() {
    final tickets = [...state.tickets];
    final idx = tickets.indexWhere((t) => t.id == state.activeTicketId);
    if (idx == -1) return;

    tickets[idx] = tickets[idx].copyWith(
      items: const [],
      clearCustomer: true,
    );

    _emitAndPersist(state.copyWith(
      tickets: tickets,
      received: 0,
      paymentKind: PaymentKind.cash,
      selectedItemIndex: null,
      clearSelection: true,
    ));
  }

  void setCustomerForActiveTicket(PosCustomer customer) {
    final tid = state.activeTicketId;

    final updated = state.tickets.map((t) {
      if (t.id != tid) return t;
      return t.copyWith(customer: customer);
    }).toList();

    _emitAndPersist(state.copyWith(tickets: updated));
  }

  void clearCustomerForActiveTicket() {
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
    if (qty <= 0 || qty.isNaN || qty.isInfinite) return;

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
          markCodes: [...it.markCodes, ...markCodes],
        );
        updatedCartQty = list[idx].qty;
        updatedDiscountApplied = list[idx].discountApplied;
        selectedIndex = idx;
      } else {
        list.add(CartItem(
          product: p,
          qty: qty,
          discountApplied: _shouldApplyServerDiscount(p),
          markCodes: markCodes,
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

  void setMarkCodes(int index, List<String> codes) {
    if (index < 0 || index >= state.items.length) return;
    final normalized = codes
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      list[index] = list[index].copyWith(markCodes: normalized);
      return list;
    });
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
    if (index < 0 || index >= state.items.length) return;

    if (qty <= 0) {
      removeAt(index);
      return;
    }

    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        final current = list[index];
        var normalizedQty = current.product.isUniversal
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
        if (current.product.requiresMarking &&
            normalizedQty > current.markCodes.length) {
          normalizedQty = current.markCodes.length.toDouble();
        }
        final retainedCodes = current.product.requiresMarking
            ? current.markCodes.take(normalizedQty.round()).toList()
            : current.markCodes;
        list[index] = current.copyWith(
          qty: normalizedQty,
          markCodes: retainedCodes,
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

  void setPaymentKind(PaymentKind kind) {
    _emitAndPersist(state.copyWith(paymentKind: kind));
  }

  void setReceived(double value) {
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
    if (idx == -1) return;

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

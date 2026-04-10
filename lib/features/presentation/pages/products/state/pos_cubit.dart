import 'dart:async';
import 'dart:convert';

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

  PosCubit(this.repo) : super(PosState.initial()) {
    unawaited(_restorePersistedState());
  }

  void _emitAndPersist(PosState nextState) {
    emit(nextState);
    unawaited(_persistState(nextState));
  }

  Future<void> _persistState(PosState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPersistedStateKey, jsonEncode(state.toJson()));
  }

  Future<void> _restorePersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPersistedStateKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final restored = PosState.fromJson(decoded);
      super.emit(restored);
    } catch (_) {
      await prefs.remove(_kPersistedStateKey);
    }
  }

  Future<void> resetAllLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPersistedStateKey);
    emit(PosState.initial());
  }

  double _normalizedMaxQty(Product product) {
    final qty = product.quantity;
    if (qty.isNaN || qty.isInfinite) return 0;
    return qty < 0 ? 0 : qty;
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
    final id = (m.id?.toString().isNotEmpty ?? false)
        ? m.id!.toString()
        : (m.id?.toString().isNotEmpty ?? false)
            ? m.id!.toString()
            : m.name;

    return Product(
      id: id,
      name: m.name,
      price: m.sellingPrice,
      vat: 0,
      quantity: m.quantity,
      measurementUnit: m.measurementUnit,
      conversionValue: m.conversionValue,
    );
  }

  void clearAfterPayment() {
    final tickets = [...state.tickets];
    final idx = tickets.indexWhere((t) => t.id == state.activeTicketId);
    if (idx == -1) return;

    tickets[idx] = tickets[idx].copyWith(items: const []);

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

  void addWithQty(Product p, double qty) {
    final maxQty = _normalizedMaxQty(p);
    if (maxQty <= 0 || qty <= 0 || qty.isNaN || qty.isInfinite) return;

    int? selectedIndex; // какой индекс выбрать после добавления/увеличения

    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      final idx = list.indexWhere((e) => e.product.id == p.id);

      if (idx >= 0) {
        final it = list[idx];
        final nextQty = (it.qty + qty) > maxQty ? maxQty : (it.qty + qty);
        list[idx] = it.copyWith(qty: nextQty);
        selectedIndex = idx;
      } else {
        final initialQty = qty > maxQty ? maxQty : qty;
        list.add(CartItem(product: p, qty: initialQty));
        selectedIndex = list.length - 1;
      }

      return list;
    });

    _emitAndPersist(state.copyWith(
      tickets: tickets,
      selectedItemIndex: selectedIndex,
    ));
  }

  void addFromProductModel(ProductModel m, {double qty = 1}) {
    final product = _mapProductModelToProduct(m);
    addWithQty(product, qty);
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
        final maxQty = _normalizedMaxQty(current.product);
        final normalizedQty = ProductModel.isPiecesMeasurementUnit(
                current.product.measurementUnit)
            ? qty.roundToDouble()
            : qty;
        final nextQty = normalizedQty > maxQty ? maxQty : normalizedQty;
        list[index] = current.copyWith(qty: nextQty);
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
    setQty(idx, current.qty + 1);
  }

  // Уменьшить количество у выбранной позиции
  void decrementSelectedQty() {
    final idx = state.selectedItemIndex;
    if (idx == null) return;
    final items = state.items;
    if (idx < 0 || idx >= items.length) return;

    final current = items[idx];
    final newQty = current.qty - 1;
    setQty(idx, newQty);
  }

  double get total => state.items.fold<double>(0, (p, e) => p + e.sum);

  double get discountSum => state.items.fold<double>(
        0,
        (p, e) => p + (e.product.price * e.qty) * (e.discount / 100),
      );

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

    final newTicket = PosTicket(id: newId, items: []);

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

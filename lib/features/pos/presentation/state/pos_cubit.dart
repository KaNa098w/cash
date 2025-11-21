import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/pos_repository.dart';

part 'pos_state.dart';

class PosCubit extends Cubit<PosState> {
  final PosRepository repo;

  PosCubit(this.repo) : super(PosState.initial());

  // ====== ВСПОМОГАТЕЛЬНЫЙ МЕТОД ДЛЯ РЕДАКТИРОВАНИЯ АКТИВНОГО ЧЕКА ======

  List<PosTicket> _updateActiveTicketItems(
    List<CartItem> Function(List<CartItem>) updater,
  ) {
    final tickets = [...state.tickets];
    final idx = tickets.indexWhere((t) => t.id == state.activeTicketId);

    if (idx == -1) {
      // на всякий случай, если тикета нет — создаём
      final newItems = updater(const []);
      tickets.add(PosTicket(id: state.activeTicketId, items: newItems));
    } else {
      final ticket = tickets[idx];
      final newItems = updater(ticket.items);
      tickets[idx] = ticket.copyWith(items: newItems);
    }

    return tickets;
  }

  // ====== ДЕМО-ДАННЫЕ В АКТИВНЫЙ ЧЕК ======

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

    emit(
      state.copyWith(
        tickets: tickets,
        activeTicketId: newActiveId,
      ),
    );
  }

  void seedDemo() {
    final demo = List.generate(
      6,
      (i) => CartItem(
        product: Product(
          id: '$i',
          name: 'Типа товаргой',
          price: 2000,
          vat: 20,
        ),
        qty: 4,
        discount: 20,
      ),
    );

    final tickets = _updateActiveTicketItems((_) => demo);
    emit(state.copyWith(tickets: tickets));
  }

  // ====== ПОИСК ТОВАРОВ ======

  Future<void> search(String q) async {
    emit(state.copyWith(searching: true));
    final results = await repo.searchProducts(q);
    emit(state.copyWith(searching: false, searchResults: results));
  }

  // ====== РАБОТА С ТОВАРАМИ В АКТИВНОМ ЧЕКЕ ======

  void add(Product p) {
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      final idx = list.indexWhere((e) => e.product.id == p.id);

      if (idx >= 0) {
        final it = list[idx];
        list[idx] = it.copyWith(qty: it.qty + 1);
      } else {
        list.add(CartItem(product: p, qty: 1));
      }

      return list;
    });

    emit(state.copyWith(tickets: tickets));
  }

  void removeAt(int index) {
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        list.removeAt(index);
      }
      return list;
    });

    emit(state.copyWith(tickets: tickets));
  }

  void setQty(int index, double qty) {
    final tickets = _updateActiveTicketItems((items) {
      final list = List<CartItem>.from(items);
      if (index >= 0 && index < list.length) {
        list[index] = list[index].copyWith(qty: qty);
      }
      return list;
    });

    emit(state.copyWith(tickets: tickets));
  }

  double get total => state.items.fold<double>(0, (p, e) => p + e.sum);

  double get discountSum => state.items.fold<double>(
        0,
        (p, e) => p + (e.product.price * e.qty) * (e.discount / 100),
      );

  void setPaymentKind(PaymentKind kind) {
    emit(state.copyWith(paymentKind: kind));
  }

  void setReceived(double value) {
    emit(state.copyWith(received: value));
  }

  double get change => state.received - total;

  // ====== ИСТОРИЯ / ПРОДАЖИ (ПЕРЕКЛЮЧЕНИЕ ЭКРАНОВ) ======

  void showHistory() {
    emit(state.copyWith(isHistoryMode: true));
  }

  void showSales() {
    emit(state.copyWith(isHistoryMode: false));
  }

  // ====== МУЛЬТИЧЕКИ: ОТЛОЖКА И ПЕРЕКЛЮЧЕНИЕ ВКЛАДОК ======

  /// "+ Отложка" — создаём новый чек с 0 товарами и переключаемся на него
  void createHoldTicket() {
    final ids = state.tickets.map((t) => t.id);
    final lastId = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
    final newId = lastId + 1;

    final newTicket = PosTicket(id: newId, items: const []);

    emit(
      state.copyWith(
        tickets: [...state.tickets, newTicket],
        activeTicketId: newId,
        isHistoryMode: false,
      ),
    );
  }

  /// Переключение между существующими чеками
  void switchTicket(int id) {
    if (!state.tickets.any((t) => t.id == id)) return;
    emit(
      state.copyWith(
        activeTicketId: id,
        isHistoryMode: false,
      ),
    );
  }
}

part of 'pos_cubit.dart';

/// Один чек (вкладка)
class PosTicket extends Equatable {
  final int id;
  final List<CartItem> items;

  const PosTicket({
    required this.id,
    this.items = const [],
  });

  PosTicket copyWith({
    List<CartItem>? items,
  }) {
    return PosTicket(
      id: id,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [id, items];
}

class PosState extends Equatable {
  /// Все чеки (вкладки)
  final List<PosTicket> tickets;

  /// ID активного чека
  final int activeTicketId;

  /// true → экран "История продаж", false → обычный POS
  final bool isHistoryMode;

  /// поиск
  final bool searching;
  final List<Product> searchResults;

  /// оплата
  final PaymentKind paymentKind;
  final double received;

  const PosState({
    this.tickets = const [],
    this.activeTicketId = 1,
    this.isHistoryMode = false,
    this.searching = false,
    this.searchResults = const [],
    this.paymentKind = PaymentKind.cash,
    this.received = 0,
  });

  /// Стартовое состояние: один пустой чек №1
  factory PosState.initial() {
    return PosState(
      tickets: [const PosTicket(id: 1)],
      activeTicketId: 1,
    );
  }

  /// Активный чек
  PosTicket get activeTicket {
    if (tickets.isEmpty) {
      return PosTicket(id: activeTicketId, items: const []);
    }
    return tickets.firstWhere(
      (t) => t.id == activeTicketId,
      orElse: () => tickets.first,
    );
  }

  /// Позиции активного чека — CartList уже использует state.items
  List<CartItem> get items => activeTicket.items;

  PosState copyWith({
    List<PosTicket>? tickets,
    int? activeTicketId,
    bool? isHistoryMode,
    bool? searching,
    List<Product>? searchResults,
    PaymentKind? paymentKind,
    double? received,
  }) {
    return PosState(
      tickets: tickets ?? this.tickets,
      activeTicketId: activeTicketId ?? this.activeTicketId,
      isHistoryMode: isHistoryMode ?? this.isHistoryMode,
      searching: searching ?? this.searching,
      searchResults: searchResults ?? this.searchResults,
      paymentKind: paymentKind ?? this.paymentKind,
      received: received ?? this.received,
    );
  }

  @override
  List<Object?> get props => [
        tickets,
        activeTicketId,
        isHistoryMode,
        searching,
        searchResults,
        paymentKind,
        received,
      ];
}

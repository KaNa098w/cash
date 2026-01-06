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

  /// оплата
  final PaymentKind paymentKind;
  final double received;

  /// выбранная позиция в активном чеке (index в items) или null
  final int? selectedItemIndex;

  const PosState({
    this.tickets = const [],
    this.activeTicketId = 1,
    this.isHistoryMode = false,
    this.paymentKind = PaymentKind.cash,
    this.received = 0,
    this.selectedItemIndex,
  });

  /// Стартовое состояние: один пустой чек №1
  factory PosState.initial() {
    return const PosState(
      tickets: [PosTicket(id: 1)],
      activeTicketId: 1,
      selectedItemIndex: null,
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

  /// Позиции активного чека — CartList использует state.items
  List<CartItem> get items => activeTicket.items;

  PosState copyWith({
    List<PosTicket>? tickets,
    int? activeTicketId,
    bool? isHistoryMode,
    PaymentKind? paymentKind,
    double? received,
    int? selectedItemIndex,
    bool clearSelection = false, // для явного сброса
  }) {
    return PosState(
      tickets: tickets ?? this.tickets,
      activeTicketId: activeTicketId ?? this.activeTicketId,
      isHistoryMode: isHistoryMode ?? this.isHistoryMode,
      paymentKind: paymentKind ?? this.paymentKind,
      received: received ?? this.received,
      selectedItemIndex:
          clearSelection ? null : (selectedItemIndex ?? this.selectedItemIndex),
    );
  }

  @override
  List<Object?> get props => [
        tickets,
        activeTicketId,
        isHistoryMode,
        paymentKind,
        received,
        selectedItemIndex,
      ];
}

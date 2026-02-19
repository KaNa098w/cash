part of 'pos_cubit.dart';

class PosTicket extends Equatable {
  final int id;
  final List<CartItem> items;

  // ✅ выбранный покупатель для этого чека
  final PosCustomer? customer;

  const PosTicket({
    required this.id,
    this.items = const [],
    this.customer,
  });

  PosTicket copyWith({
    List<CartItem>? items,
    PosCustomer? customer,
    bool clearCustomer = false,
  }) {
    return PosTicket(
      id: id,
      items: items ?? this.items,
      customer: clearCustomer ? null : (customer ?? this.customer),
    );
  }

  @override
  List<Object?> get props => [id, items, customer];
}

class PosState extends Equatable {
  final List<PosTicket> tickets;
  final int activeTicketId;

  final bool isHistoryMode;

  final PaymentKind paymentKind;
  final double received;

  final int? selectedItemIndex;

  const PosState({
    this.tickets = const [],
    this.activeTicketId = 1,
    this.isHistoryMode = false,
    this.paymentKind = PaymentKind.cash,
    this.received = 0,
    this.selectedItemIndex,
  });

  factory PosState.initial() {
    return const PosState(
      tickets: [PosTicket(id: 1)],
      activeTicketId: 1,
      selectedItemIndex: null,
    );
  }

  PosTicket get activeTicket {
    if (tickets.isEmpty) {
      return PosTicket(id: activeTicketId, items: const []);
    }
    return tickets.firstWhere(
      (t) => t.id == activeTicketId,
      orElse: () => tickets.first,
    );
  }

  List<CartItem> get items => activeTicket.items;

  // ✅ активный покупатель
  PosCustomer? get activeCustomer => activeTicket.customer;

  PosState copyWith({
    List<PosTicket>? tickets,
    int? activeTicketId,
    bool? isHistoryMode,
    PaymentKind? paymentKind,
    double? received,
    int? selectedItemIndex,
    bool clearSelection = false,
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

class PosCustomer {
  final String id;
  final String name;
  final String? phone;

  const PosCustomer({
    required this.id,
    required this.name,
    this.phone,
  });
}

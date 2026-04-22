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

  factory PosTicket.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final items = itemsRaw is List
        ? itemsRaw
            .whereType<Map>()
            .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <CartItem>[];
    final customerRaw = json['customer'];
    return PosTicket(
      id: (json['id'] as num?)?.toInt() ?? 1,
      items: items,
      customer: customerRaw is Map
          ? PosCustomer.fromJson(Map<String, dynamic>.from(customerRaw))
          : null,
    );
  }

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items.map((e) => e.toJson()).toList(growable: false),
        'customer': customer?.toJson(),
      };

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

  factory PosState.fromJson(Map<String, dynamic> json) {
    final ticketsRaw = json['tickets'];
    final tickets = ticketsRaw is List
        ? ticketsRaw
            .whereType<Map>()
            .map((e) => PosTicket.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <PosTicket>[];
    final paymentKindRaw =
        (json['paymentKind'] ?? PaymentKind.cash.name).toString();

    return PosState(
      tickets: tickets.isEmpty ? const [PosTicket(id: 1)] : tickets,
      activeTicketId: (json['activeTicketId'] as num?)?.toInt() ?? 1,
      isHistoryMode: json['isHistoryMode'] == true,
      paymentKind: PaymentKind.values.firstWhere(
        (kind) => kind.name == paymentKindRaw,
        orElse: () => PaymentKind.cash,
      ),
      received: (json['received'] as num?)?.toDouble() ?? 0,
      selectedItemIndex: (json['selectedItemIndex'] as num?)?.toInt(),
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

  Map<String, dynamic> toJson() => {
        'tickets': tickets.map((e) => e.toJson()).toList(growable: false),
        'activeTicketId': activeTicketId,
        'isHistoryMode': isHistoryMode,
        'paymentKind': paymentKind.name,
        'received': received,
        'selectedItemIndex': selectedItemIndex,
      };

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
  final num balance;
  final num debtLimit;
  final bool debtAllowed;

  const PosCustomer({
    required this.id,
    required this.name,
    this.phone,
    this.balance = 0,
    this.debtLimit = 0,
    this.debtAllowed = true,
  });

  factory PosCustomer.fromJson(Map<String, dynamic> json) => PosCustomer(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        phone: json['phone']?.toString(),
        balance: (json['balance'] as num?) ?? 0,
        debtLimit: (json['debtLimit'] as num?) ?? 0,
        debtAllowed: json['debtAllowed'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'balance': balance,
        'debtLimit': debtLimit,
        'debtAllowed': debtAllowed,
      };
}

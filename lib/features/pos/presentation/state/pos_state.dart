part of 'pos_cubit.dart';

class PosState extends Equatable {
  final List<CartItem> items;
  final bool searching;
  final List<Product> searchResults;
  final PaymentKind paymentKind;
  final double received;

  const PosState({
    this.items = const [],
    this.searching = false,
    this.searchResults = const [],
    this.paymentKind = PaymentKind.cash,
    this.received = 0,
  });

  PosState copyWith({
    List<CartItem>? items,
    bool? searching,
    List<Product>? searchResults,
    PaymentKind? paymentKind,
    double? received,
  }) =>
      PosState(
        items: items ?? this.items,
        searching: searching ?? this.searching,
        searchResults: searchResults ?? this.searchResults,
        paymentKind: paymentKind ?? this.paymentKind,
        received: received ?? this.received,
      );

  @override
  List<Object?> get props => [items, searching, searchResults, paymentKind, received];
}

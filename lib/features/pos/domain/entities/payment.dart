enum PaymentKind { cash, card, credit }

class Payment {
  final PaymentKind kind;
  final double amount;

  const Payment(this.kind, this.amount);
}

class OrganizationBankAccount {
  OrganizationBankAccount(this.json);
  final Map<String, dynamic> json;
  String get id => (json['id'] ?? '').toString();
  bool get isDefault => json['is_default'] == true || json['is_default'] == 1;
  String get label => [json['name'], json['bank_name'], json['iban']]
      .where((v) => v != null && v.toString().isNotEmpty)
      .join(' · ');

  static OrganizationBankAccount? preferred(
      List<OrganizationBankAccount> values) {
    if (values.isEmpty) return null;
    return values.firstWhere((v) => v.isDefault, orElse: () => values.first);
  }
}

class PaymentInvoice {
  PaymentInvoice(this.json);
  final Map<String, dynamic> json;
  String get id => (json['id'] ?? '').toString();
  String get number => (json['number'] ?? id).toString();
  String get status => (json['status'] ?? '').toString();
  String get dueAt => (json['due_at'] ?? '').toString().split('T').first;
  String get saleId => (json['sale_id'] ?? '').toString();
  String get customerName =>
      (details('customer_details')['name'] ?? '').toString();
  String get currency => (json['currency'] ?? 'KZT').toString();
  num get total => num.tryParse('${json['total_amount']}') ?? 0;
  Map<String, dynamic> details(String key) =>
      json[key] is Map ? Map<String, dynamic>.from(json[key]) : {};
  List<Map<String, dynamic>> get items => (json['items'] as List? ?? [])
      .whereType<Map>()
      .map((v) => Map<String, dynamic>.from(v))
      .toList();

  String statusAt(DateTime now) {
    final due = DateTime.tryParse(dueAt);
    if (status == 'issued' &&
        due != null &&
        DateTime(due.year, due.month, due.day)
            .isBefore(DateTime(now.year, now.month, now.day))) {
      return 'expired';
    }
    return status;
  }

  String get displayStatus => statusAt(DateTime.now());
  bool get canConfirm => displayStatus == 'issued';
  bool get canCancel => status == 'issued' || status == 'expired';
  String get statusLabel => switch (displayStatus) {
        'issued' => 'Ожидает оплаты',
        'paid' => 'Оплачен',
        'cancelled' => 'Отменён',
        'expired' => 'Просрочен',
        _ => status,
      };
}

class PaymentInvoicePage {
  const PaymentInvoicePage(this.items, this.page, this.lastPage);
  final List<PaymentInvoice> items;
  final int page;
  final int lastPage;
}

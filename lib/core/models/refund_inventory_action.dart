enum RefundInventoryAction {
  returnToStock('return_to_stock', 'Вернуть на склад'),
  writeOff('write_off', 'Списать без возврата на склад'),
  reverseSale('reverse_sale', 'Вернуть ошибочно проданное количество'),
  amountCorrection('amount_correction', 'Исправить только деньги');

  const RefundInventoryAction(this.code, this.label);
  final String code;
  final String label;

  static RefundInventoryAction forReason(String? reason) => switch (reason) {
        'defective' || 'damaged' || 'expired' => writeOff,
        'incorrect_quantity' || 'duplicate_sale' => reverseSale,
        'incorrect_price' => amountCorrection,
        _ => returnToStock,
      };
}

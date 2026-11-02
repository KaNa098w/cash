import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'supplies_controller.dart';
import 'supply_widgets.dart';

class SupplyPaymentsPanel extends StatelessWidget {
  const SupplyPaymentsPanel(
      {super.key,
      required this.controller,
      required this.document,
      required this.enabled,
      required this.onUpdated});
  final SuppliesController controller;
  final SupplyDocument document;
  final bool enabled;
  final VoidCallback onUpdated;

  Future<void> _edit(BuildContext context, [SupplyPayment? payment]) async {
    if (!await ensureSupplyAccess(context, controller) || !context.mounted) {
      return;
    }
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SupplyPaymentDialog(
            controller: controller,
            document: document,
            payment: payment,
            onUpdated: onUpdated));
  }

  Future<void> _delete(BuildContext context, SupplyPayment payment) async {
    if (!await supplyConfirm(context, 'Удалить оплату?',
        '${supplyMoney(payment.amount)} · ${payment.accountName}. Остаток задолженности будет пересчитан сервером.',
        button: 'Удалить оплату')) {
      return;
    }
    if (!context.mounted ||
        !await ensureSupplyAccess(context, controller) ||
        !context.mounted) {
      return;
    }
    if (await controller.mutate('Удаление оплаты', (manager) async {
      await controller.api.deletePayment(controller.posKey, controller.deviceId,
          manager, document.id, payment.id);
      return document.id;
    }, documentId: document.id)) {
      onUpdated();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Оплаты поставщику',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: supplyInk)),
              Text('Оплачено: ${supplyMoney(document.paid)}',
                  style: const TextStyle(
                      color: supplyGreen, fontWeight: FontWeight.w700)),
              Text('Осталось: ${supplyMoney(document.unpaid)}',
                  style: const TextStyle(color: supplyMuted)),
              OutlinedButton.icon(
                  onPressed: enabled ? () => _edit(context) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить оплату')),
            ]),
        const SizedBox(height: 12),
        if (document.payments.isEmpty)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Оплат пока нет. Оплаты сохраняются отдельно от приёмки.',
                  style: TextStyle(color: supplyMuted))),
        ...document.payments.map((p) => Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5EBF1)))),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: supplyGreen),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${supplyMoney(p.amount)} · ${p.accountName}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        '${supplyDisplayDay(p.date)}${p.comment.isEmpty ? '' : ' · ${p.comment}'}',
                        style: const TextStyle(color: supplyMuted)),
                  ])),
              IconButton(
                  tooltip: 'Изменить оплату',
                  onPressed: enabled ? () => _edit(context, p) : null,
                  icon: const Icon(Icons.edit_outlined)),
              IconButton(
                  tooltip: 'Удалить оплату',
                  onPressed: enabled ? () => _delete(context, p) : null,
                  icon: const Icon(Icons.delete_outline)),
            ]))),
      ]));
}

class _SupplyPaymentDialog extends StatefulWidget {
  const _SupplyPaymentDialog(
      {required this.controller,
      required this.document,
      required this.onUpdated,
      this.payment});
  final SuppliesController controller;
  final SupplyDocument document;
  final SupplyPayment? payment;
  final VoidCallback onUpdated;
  @override
  State<_SupplyPaymentDialog> createState() => _SupplyPaymentDialogState();
}

class _SupplyPaymentDialogState extends State<_SupplyPaymentDialog> {
  late String? _account = widget.payment?.accountId;
  late double _amount = widget.payment?.amount ?? widget.document.unpaid;
  late DateTime _date =
      DateTime.tryParse(widget.payment?.date ?? '') ?? DateTime.now();
  late final _comment =
      TextEditingController(text: widget.payment?.comment ?? '');
  String? _error;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (_, __) {
        final c = widget.controller;
        final enabled = !c.busy && c.pending == null;
        return PopScope(
            canPop: !c.busy,
            child: SupplyDialog(
              canClose: !c.busy,
              icon: Icons.account_balance_wallet_outlined,
              subtitle: 'Расчёты с поставщиком · отдельная оплата',
              title: Text(widget.payment == null
                  ? 'Оплата поставщику'
                  : 'Изменить оплату'),
              content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SupplySelect(
                        label: 'Счёт списания',
                        items: c.references.accounts,
                        value: _account,
                        onChanged: enabled
                            ? (v) => setState(() => _account = v)
                            : null),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                            onPressed: enabled
                                ? () async {
                                    final value = await supplyNumberDialog(
                                        context,
                                        title: 'Сумма оплаты',
                                        value: _amount);
                                    if (value != null && mounted) {
                                      setState(() => _amount = value);
                                    }
                                  }
                                : null,
                            child: Text(supplyMoney(_amount),
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800)))),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                            onPressed: enabled
                                ? () async {
                                    final date = await showDatePicker(
                                        context: context,
                                        initialDate: _date,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                        builder: (ctx, child) => Theme(
                                            data: supplyTheme(ctx),
                                            child: child!),
                                        initialEntryMode:
                                            DatePickerEntryMode.calendarOnly);
                                    if (date != null && mounted) {
                                      setState(() => _date = date);
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(supplyDisplayDay(supplyDay(_date))))),
                    const SizedBox(height: 16),
                    SupplyNoteField(
                        controller: _comment,
                        label: 'Комментарий к оплате',
                        enabled: enabled),
                    if (c.busy)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator()),
                    if (_error != null || c.error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child:
                              SupplyMessage(_error ?? c.error!, error: true)),
                    if (c.pending != null)
                      const Text(
                          'Повтор оплаты заблокирован. Закройте окно и проверьте документ и список оплат.',
                          style: TextStyle(color: Colors.deepOrange)),
                  ]))),
              actions: [
                TextButton(
                    onPressed: c.busy ? null : () => Navigator.pop(context),
                    child: const Text('Закрыть')),
                FilledButton(
                    onPressed: enabled &&
                            _account != null &&
                            _amount.isFinite &&
                            _amount > 0
                        ? () async {
                            if (!await ensureSupplyAccess(context, c) ||
                                !mounted) {
                              return;
                            }
                            final ok = await c.mutate(
                                widget.payment == null
                                    ? 'Добавление оплаты'
                                    : 'Изменение оплаты', (manager) async {
                              await c.api.payment(
                                  c.posKey,
                                  c.deviceId,
                                  manager,
                                  widget.document.id,
                                  {
                                    'account_id': _account,
                                    'amount': _amount,
                                    'date': supplyDay(_date),
                                    if (_comment.text.trim().isNotEmpty)
                                      'comment': _comment.text.trim(),
                                  },
                                  paymentId: widget.payment?.id);
                              return widget.document.id;
                            }, documentId: widget.document.id);
                            if (ok && context.mounted) {
                              widget.onUpdated();
                              Navigator.pop(context);
                            }
                          }
                        : null,
                    child: const Text('Сохранить оплату'))
              ],
            ));
      });
}

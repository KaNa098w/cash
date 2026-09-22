import 'invoice_text_field.dart';
import 'invoice_customer_picker.dart';
import 'invoice_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/payment_invoice.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/invoices_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'invoice_history_dialog.dart';

Future<bool> showInvoiceIssueDialog(BuildContext context) async {
  final cubit = context.read<PosCubit>();
  final auth = context.read<AuthTokenProvider>();
  final ticket = cubit.state.activeTicket;
  if (ticket.checkout != null || ticket.items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Для выставления счёта нужна корзина без отправленной оплаты.')));
    return false;
  }
  final invoice = await showDialog<PaymentInvoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InvoiceIssueDialog(cubit: cubit, auth: auth, ticket: ticket));
  if (invoice == null) return false;
  if (context.mounted) {
    await showInvoiceDetails(context, invoice: invoice, auth: auth);
  }
  return true;
}

class _InvoiceIssueDialog extends StatefulWidget {
  const _InvoiceIssueDialog(
      {required this.cubit, required this.auth, required this.ticket});
  final PosCubit cubit;
  final AuthTokenProvider auth;
  final PosTicket ticket;
  @override
  State<_InvoiceIssueDialog> createState() => _InvoiceIssueDialogState();
}

class _InvoiceIssueDialogState extends State<_InvoiceIssueDialog> {
  final _comment = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _bin = TextEditingController();
  final _legalName = TextEditingController();
  final _address = TextEditingController();
  bool _withDetails = false;
  final _form = GlobalKey<FormState>();
  final _api = sl<InvoicesRemoteDataSource>();
  List<OrganizationBankAccount> _banks = [];
  List<CustomerDto> _customers = [];
  String? _bankId;
  String? _customerId;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _newCustomer = false;
  late final String _key = widget.auth.posKey?.trim() ?? '';
  late final String _deviceId = widget.auth.deviceId?.trim() ?? '';
  late final String _storeId = widget.auth.storeId?.trim() ?? '';
  late Map<String, dynamic>? _frozen = widget.ticket.invoiceCheckout;
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  Map<String, dynamic>? get _payload => _frozen?['payload'] is Map
      ? Map<String, dynamic>.from(_frozen!['payload'])
      : null;

  @override
  void initState() {
    super.initState();
    final payload = _payload;
    if (payload != null) {
      _comment.text = (payload['comment'] ?? '').toString();
      _customerId = payload['customer_id']?.toString();
      _bankId = payload['organization_bank_account_id']?.toString();
      _due = DateTime.tryParse('${payload['due_at']}') ?? _due;
      _loading = false;
    } else {
      _customerId = widget.ticket.customer?.id;
      _load();
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    _name.dispose();
    _phone.dispose();
    _bin.dispose();
    _legalName.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final banks = await _api.bankAccounts(_key);
      final customers = await sl<CustomersRemoteDataSource>()
          .listCustomers(key: _key, size: 1000);
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _bankId = OrganizationBankAccount.preferred(banks)?.id;
        _customers = customers;
        if (!_customers.any((c) => c.id == _customerId)) _customerId = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = invoiceError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _issue() async {
    if (_busy || _loading) return;
    if (_frozen == null && !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_key.isEmpty ||
          _deviceId.isEmpty ||
          widget.auth.posKey != _key ||
          widget.auth.deviceId != _deviceId ||
          widget.auth.storeId != _storeId ||
          (_frozen != null &&
              (_frozen!['pos_key'] != _key ||
                  _frozen!['device_id'] != _deviceId ||
                  _frozen!['store_id'] != _storeId))) {
        throw StateError(
            'Вернитесь в исходный магазин и терминал для завершения счёта');
      }
      Map<String, dynamic> payload;
      if (_frozen != null) {
        payload = _payload!;
      } else {
        final userId = widget.auth.activeUserId?.trim() ?? '';
        final sessionId = widget.auth.shiftId?.trim() ?? '';
        if (userId.isEmpty || sessionId.isEmpty) {
          throw StateError('Откройте смену для выставления счёта');
        }
        if (_bankId == null) {
          throw StateError('Не настроены банковские реквизиты организации');
        }
        final today = DateTime.now();
        if (DateTime(_due.year, _due.month, _due.day)
            .isBefore(DateTime(today.year, today.month, today.day))) {
          throw StateError('Срок оплаты не может быть раньше сегодняшнего дня');
        }
        if (_newCustomer) {
          final created = await _api.createCustomer(_key,
              name: _name.text,
              userId: userId,
              phone: _phone.text,
              bin: _withDetails ? _bin.text : '',
              legalName: _withDetails ? _legalName.text : '',
              legalAddress: _withDetails ? _address.text : '');
          _customers = [..._customers, created];
          _customerId = created.id;
          _newCustomer = false;
        }
        if (_customerId == null) throw StateError('Выберите покупателя');
        payload = {
          'client_invoice_id': const Uuid().v4(),
          'customer_id': _customerId,
          'organization_bank_account_id': _bankId,
          'pos_session_id': sessionId,
          'due_at': DateFormat('yyyy-MM-dd').format(_due),
          'user_id': userId,
          'comment': _comment.text.trim(),
          'items': [
            for (final item in widget.ticket.items)
              {
                'product_id': item.product.id,
                'quantity': item.billableQuantity,
                'price': item.billableQuantity == 0
                    ? 0
                    : item.sum / item.billableQuantity,
                'total_price': item.sum,
                'mark_codes': item.markCodes,
              }
          ],
        };
        _frozen = {
          'pos_key': _key,
          'device_id': _deviceId,
          'store_id': _storeId,
          'customer_name':
              _customers.firstWhere((c) => c.id == _customerId).name,
          'bank_label': _banks.firstWhere((b) => b.id == _bankId).label,
          'payload': payload
        };
      }
      // Also retry persistence after a disk failure; never send an unsaved UUID.
      await widget.cubit.saveInvoiceCheckout(widget.ticket.id, _frozen!);
      final invoice = await _api.create(_key, payload);
      if (!widget.cubit.isClosed &&
          widget.cubit.state.tickets.any((t) =>
              t.id == widget.ticket.id &&
              t.invoiceCheckout?['payload']?['client_invoice_id'] ==
                  payload['client_invoice_id'])) {
        widget.cubit.completeCheckout(widget.ticket.id);
        await widget.cubit.flushPendingState();
      }
      if (mounted) Navigator.pop(context, invoice);
    } catch (e) {
      // A validation rejection did not create an invoice; allow correcting it.
      if (invoiceValidationCanBeCorrected(e)) {
        widget.cubit.releaseInvoiceCheckout(widget.ticket.id);
        await widget.cubit.flushPendingState();
        _frozen = null;
        if (mounted) await _load();
      }
      if (mounted) setState(() => _error = invoiceError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCustomer() async {
    final customer = await showDialog<CustomerDto>(
        context: context,
        builder: (_) => InvoiceCustomerPicker(customers: _customers));
    if (customer != null && mounted) setState(() => _customerId = customer.id);
  }

  Widget _section(String title, IconData icon, List<Widget> children) =>
      InvoiceInfoCard(
          color: Colors.white,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: invoiceBlue),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700)))
            ]),
            const SizedBox(height: 18),
            ...children,
          ]));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
        context: context,
        initialDate: _due.isBefore(today) ? today : _due,
        firstDate: today,
        lastDate: DateTime(now.year + 10, 12, 31),
        initialEntryMode: DatePickerEntryMode.calendarOnly);
    if (date != null && mounted) setState(() => _due = date);
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _frozen != null;
    final editable = !frozen && !_busy && !_loading;
    CustomerDto? customer;
    for (final item in _customers) {
      if (item.id == _customerId) customer = item;
    }
    final buyer = _section('Покупатель', Icons.person_outline, [
      if (frozen) ...[
        Text('${_frozen!['customer_name'] ?? _customerId}',
            style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        const Text(
            'Счёт сохранён. Повторная отправка использует исходные данные.',
            style: TextStyle(color: invoiceMuted)),
      ] else ...[
        Row(children: [
          Expanded(
              child: _newCustomer
                  ? OutlinedButton(
                      onPressed: editable
                          ? () => setState(() => _newCustomer = false)
                          : null,
                      child: const Text('Выбрать покупателя'))
                  : FilledButton(
                      onPressed: editable ? _pickCustomer : null,
                      child: const Text('Выбрать покупателя'))),
          const SizedBox(width: 12),
          Expanded(
              child: _newCustomer
                  ? FilledButton(
                      onPressed: editable ? () {} : null,
                      child: const Text('Новый покупатель'))
                  : OutlinedButton.icon(
                      onPressed: editable
                          ? () => setState(() => _newCustomer = true)
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Новый покупатель'))),
        ]),
        const SizedBox(height: 18),
        if (_newCustomer) ...[
          InvoiceTextField(
              controller: _name,
              label: 'Имя или название покупателя',
              enabled: editable,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Укажите имя' : null),
          const SizedBox(height: 14),
          InvoiceTextField(
              controller: _phone,
              label: 'Телефон (необязательно)',
              inputKind: InvoiceInputKind.phone,
              validator: (v) =>
                  (v ?? '').isEmpty || invoicePhoneDigits(v!).length == 10
                      ? null
                      : 'Введите номер полностью',
              enabled: editable),
          const SizedBox(height: 8),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Реквизиты организации'),
              subtitle: const Text('ИИН/БИН, юридическое название и адрес'),
              value: _withDetails,
              onChanged:
                  editable ? (v) => setState(() => _withDetails = v) : null),
          if (_withDetails) ...[
            const SizedBox(height: 10),
            InvoiceTextField(
                controller: _bin,
                label: 'ИИН/БИН',
                inputKind: InvoiceInputKind.digits,
                enabled: editable,
                validator: (v) => RegExp(r'^\d{12}$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Введите 12 цифр'),
            const SizedBox(height: 14),
            InvoiceTextField(
                controller: _legalName,
                label: 'Юридическое название',
                enabled: editable,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Укажите юридическое название'
                    : null),
            const SizedBox(height: 14),
            InvoiceTextField(
                controller: _address,
                label: 'Юридический адрес',
                enabled: editable,
                maxLines: 2,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Укажите юридический адрес'
                    : null),
          ],
          const SizedBox(height: 12),
          const Text('Покупатель будет создан при выставлении счёта.',
              style: TextStyle(color: invoiceMuted)),
        ] else
          FormField<String>(
              key: ValueKey(_customerId),
              initialValue: _customerId,
              validator: (_) =>
                  _customerId == null ? 'Выберите покупателя' : null,
              builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InvoiceInfoCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(customer?.name ?? 'Покупатель не выбран',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              if (customer != null) ...[
                                if (customer.phone.isNotEmpty)
                                  Text(customer.phone),
                                if (customer.bin.isNotEmpty)
                                  Text('ИИН/БИН: ${customer.bin}'),
                                if (customer.legalName.isNotEmpty)
                                  Text(customer.legalName),
                                if (customer.legalAddress.isNotEmpty)
                                  Text(customer.legalAddress),
                              ],
                            ])),
                        if (field.hasError)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(field.errorText!,
                                  style: const TextStyle(color: Colors.red))),
                      ])),
      ],
    ]);
    final terms = _section('Условия оплаты', Icons.account_balance_outlined, [
      if (frozen)
        Text('Банк: ${_frozen!['bank_label'] ?? _bankId}')
      else if (!_loading && _banks.isEmpty)
        const Text('Не настроены банковские реквизиты организации',
            style: TextStyle(color: Colors.red))
      else
        DropdownButtonFormField<String>(
            key: ValueKey(_bankId),
            initialValue: _bankId,
            isExpanded: true,
            itemHeight: 64,
            menuMaxHeight: 360,
            decoration:
                const InputDecoration(labelText: 'Банковский счёт продавца'),
            items: _banks
                .map((b) => DropdownMenuItem(
                    value: b.id,
                    child: Text(b.label, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: editable ? (v) => setState(() => _bankId = v) : null),
      const SizedBox(height: 18),
      ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: invoiceBorder)),
          title: const Text('Оплатить до'),
          subtitle: Text(DateFormat('dd.MM.yyyy').format(_due),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.calendar_month, color: invoiceBlue),
          onTap: editable ? _pickDate : null),
      if (editable) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final days in [3, 7, 14])
            OutlinedButton(
                onPressed: () => setState(
                    () => _due = DateTime.now().add(Duration(days: days))),
                child: Text('+$days дней'))
        ]),
      ],
      const SizedBox(height: 18),
      InvoiceTextField(
          controller: _comment,
          label: 'Комментарий (необязательно)',
          enabled: editable,
          maxLines: 2),
    ]);
    return PopScope(
        canPop: !_busy,
        child: InvoiceSheet(
          title: const Text('Счёт на оплату'),
          subtitle:
              'Выберите покупателя и укажите условия банковского перевода',
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InvoiceInfoCard(
                            color: const Color(0xFFEAF2FF),
                            child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 24,
                                runSpacing: 8,
                                children: [
                                  const Text('К оплате по счёту',
                                      style: TextStyle(
                                          fontSize: 18, color: invoiceInk)),
                                  Text(
                                      invoiceAmount(
                                          widget.ticket.items.fold<num>(
                                              0, (sum, item) => sum + item.sum),
                                          'KZT'),
                                      style: const TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700,
                                          color: invoiceBlue)),
                                  Text('Товаров: ${widget.ticket.items.length}',
                                      style:
                                          const TextStyle(color: invoiceMuted)),
                                ])),
                        const SizedBox(height: 14),
                        const Text(
                            'Продажа будет оформлена после поступления денег. Товары по счёту не резервируются.',
                            style: TextStyle(color: invoiceMuted, height: 1.5)),
                        const SizedBox(height: 20),
                        if (_loading) const LinearProgressIndicator(),
                        LayoutBuilder(
                            builder: (context, constraints) =>
                                constraints.maxWidth >= 760
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                            Expanded(child: buyer),
                                            const SizedBox(width: 20),
                                            Expanded(child: terms)
                                          ])
                                    : Column(children: [
                                        buyer,
                                        const SizedBox(height: 18),
                                        terms
                                      ])),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: InvoiceInfoCard(
                                  color: const Color(0xFFFFF0EE),
                                  child: Text(_error!,
                                      style:
                                          const TextStyle(color: Colors.red)))),
                        if (_error != null && !frozen)
                          TextButton(
                              onPressed: _busy ? null : _load,
                              child:
                                  const Text('Обновить покупателей и счета')),
                      ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Закрыть')),
            FilledButton(
                onPressed: _busy || _loading || (!frozen && _banks.isEmpty)
                    ? null
                    : _issue,
                child: Text(_busy ? 'Выставление…' : 'Выставить счёт')),
          ],
        ));
  }
}

import 'invoice_text_field.dart';
import 'invoice_design.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/payment_invoice.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/invoices_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/repositories/invoice_payment_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

Future<void> showInvoiceHistory(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) =>
        InvoiceHistoryDialog(auth: context.read<AuthTokenProvider>()));

Future<void> showInvoiceDetails(BuildContext context,
        {required PaymentInvoice invoice, required AuthTokenProvider auth}) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => InvoiceDetailsDialog(invoice: invoice, auth: auth));

class InvoiceHistoryDialog extends StatefulWidget {
  const InvoiceHistoryDialog({super.key, required this.auth});
  final AuthTokenProvider auth;
  @override
  State<InvoiceHistoryDialog> createState() => _InvoiceHistoryDialogState();
}

class _InvoiceHistoryDialogState extends State<InvoiceHistoryDialog> {
  final _api = sl<InvoicesRemoteDataSource>();
  late final String _key = widget.auth.posKey ?? '';
  PaymentInvoicePage? _page;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.list(_key, page: page);
      if (mounted) setState(() => _page = result);
    } catch (e) {
      if (mounted) setState(() => _error = invoiceError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InvoiceSheet(
        title: const Text('Счета на оплату'),
        subtitle: 'Банковские переводы · документы и статусы оплаты',
        content:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(
                    _page == null
                        ? 'Загрузка счетов…'
                        : 'На странице: ${_page!.items.length}',
                    style: const TextStyle(color: invoiceMuted))),
            IconButton(
                tooltip: 'Обновить',
                onPressed: _busy ? null : () => _load(_page?.page ?? 1),
                icon: const Icon(Icons.refresh, color: invoiceBlue)),
          ]),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
          Expanded(
              child: _page == null
                  ? const SizedBox.shrink()
                  : _page!.items.isEmpty
                      ? const Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.request_quote_outlined,
                              size: 64, color: invoiceBlue),
                          SizedBox(height: 20),
                          Text('Счетов пока нет',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w600)),
                          SizedBox(height: 10),
                          Text(
                              'Создайте первый счёт кнопкой «Счёт на оплату»\nв окне продажи.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: invoiceMuted, height: 1.6)),
                        ]))
                      : ListView.separated(
                          itemCount: _page!.items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final invoice = _page!.items[index];
                            return _InvoiceListCard(
                                invoice: invoice,
                                onTap: _busy
                                    ? null
                                    : () async {
                                        await showInvoiceDetails(context,
                                            invoice: invoice,
                                            auth: widget.auth);
                                        if (mounted) await _load(_page!.page);
                                      });
                          })),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: 'Предыдущая страница',
                onPressed: !_busy && (_page?.page ?? 1) > 1
                    ? () => _load(_page!.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left)),
            Text('${_page?.page ?? 1} / ${_page?.lastPage ?? 1}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            IconButton(
                tooltip: 'Следующая страница',
                onPressed: !_busy && (_page?.page ?? 1) < (_page?.lastPage ?? 1)
                    ? () => _load(_page!.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'))
        ],
      );
}

class _InvoiceListCard extends StatelessWidget {
  const _InvoiceListCard({required this.invoice, this.onTap});
  final PaymentInvoice invoice;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: invoiceBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(builder: (context, constraints) {
                  final identity = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Счёт № ${invoice.number}',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: invoiceInk)),
                        const SizedBox(height: 6),
                        Text(
                            invoice.customerName.isEmpty
                                ? 'Покупатель не указан'
                                : invoice.customerName,
                            style: const TextStyle(fontSize: 15),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Text('Оплатить до ${invoiceDate(invoice.dueAt)}',
                            style: const TextStyle(
                                color: invoiceMuted, fontSize: 12)),
                      ]);
                  final amount = Text(
                      invoiceAmount(invoice.total, invoice.currency),
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: invoiceInk));
                  if (constraints.maxWidth < 540) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: 14),
                          amount,
                          const SizedBox(height: 10),
                          InvoiceStatusBadge(invoice: invoice),
                        ]);
                  }
                  return Row(children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFEFF4FD),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.description_outlined,
                            color: invoiceBlue)),
                    const SizedBox(width: 16),
                    Expanded(child: identity),
                    const SizedBox(width: 16),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          amount,
                          const SizedBox(height: 10),
                          InvoiceStatusBadge(invoice: invoice)
                        ]),
                    const SizedBox(width: 12),
                    const Icon(Icons.chevron_right, color: invoiceMuted),
                  ]);
                }))),
      );
}

class InvoiceDetailsDialog extends StatefulWidget {
  const InvoiceDetailsDialog(
      {super.key, required this.invoice, required this.auth});
  final PaymentInvoice invoice;
  final AuthTokenProvider auth;
  @override
  State<InvoiceDetailsDialog> createState() => _InvoiceDetailsDialogState();
}

class _InvoiceDetailsDialogState extends State<InvoiceDetailsDialog> {
  final _api = sl<InvoicesRemoteDataSource>();
  final _paymentStore = InvoicePaymentStore();
  late PaymentInvoice _invoice = widget.invoice;
  late final String _key = widget.auth.posKey ?? '';
  late final String _deviceId = widget.auth.deviceId ?? '';
  late final String _scope = '$_key:$_deviceId';
  bool _busy = false;
  String? _error;
  String? _message;
  @override
  void initState() {
    super.initState();
    _run(_reload);
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (widget.auth.posKey != _key || widget.auth.deviceId != _deviceId) {
        throw StateError('Вернитесь в исходный терминал для работы со счётом');
      }
      await work();
    } catch (e) {
      if (mounted) setState(() => _error = invoiceError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final invoice = await _api.get(_key, _invoice.id);
    if (mounted) setState(() => _invoice = invoice);
  }

  Future<void> _confirm() async {
    await _reload();
    if (!_invoice.canConfirm || !mounted) return;
    final sessionId = widget.auth.shiftId?.trim() ?? '';
    final userId = widget.auth.activeUserId?.trim() ?? '';
    if (sessionId.isEmpty || userId.isEmpty) {
      throw StateError('Откройте смену для подтверждения оплаты');
    }
    final saved = await _paymentStore.read(_scope, _invoice.id);
    if (!mounted) return;
    final confirmation = await showDialog<_TransferConfirmation>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TransferDialog(
            amount: '${_invoice.total} ${_invoice.currency}', saved: saved));
    if (confirmation == null) return;
    final payload = await _paymentStore.prepare(
        scope: _scope,
        invoiceId: _invoice.id,
        sessionId: sessionId,
        userId: userId,
        comment: confirmation.comment,
        date: confirmation.date);
    try {
      final result = await _api.confirm(_key, _invoice.id, payload);
      if (mounted) setState(() => _invoice = result);
      await _paymentStore.clear(_scope, _invoice.id);
    } on DioException catch (e) {
      // Definitive validation rejection can be corrected (e.g. a new shift).
      if (invoiceValidationCanBeCorrected(e)) {
        await _paymentStore.clear(_scope, _invoice.id);
      }
      rethrow;
    }
    try {
      await sl<PosSyncService>().pullOnce(key: _key, deviceId: _deviceId);
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Оплата подтверждена. История продаж обновится при синхронизации.');
      }
    }
  }

  Future<void> _cancel() async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Отменить счёт?'),
                content: Text('Счёт № ${_invoice.number} будет отменён.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Назад')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Отменить счёт'))
                ]));
    if (accepted != true) return;
    await _api.cancel(_key, _invoice.id);
    await _reload();
  }

  String _filename(String format) =>
      'invoice_${_invoice.number.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$format';

  Future<void> _pdf() async {
    final bytes = await _api.document(_key, _invoice.id);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
            child: SizedBox(
                width: 900,
                height: MediaQuery.sizeOf(ctx).height * .9,
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Счёт № ${_invoice.number}'))),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close))
                  ]),
                  Expanded(
                      child: PdfPreview(
                          build: (_) async => bytes,
                          pdfFileName: _filename('pdf'),
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          canDebug: false)),
                ]))));
  }

  Future<void> _download(String format) async {
    final bytes = await _api.document(_key, _invoice.id, format: format);
    final directory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    // Keep existing downloads; each download gets its own filename.
    final file = File(path.join(directory.path,
        '${path.basenameWithoutExtension(_filename(format))}_${DateTime.now().microsecondsSinceEpoch}.$format'));
    await file.writeAsBytes(bytes, flush: true);
    if (mounted) setState(() => _message = 'Файл сохранён: ${file.path}');
  }

  Future<void> _share() async {
    final bytes = await _api.document(_key, _invoice.id);
    final shared =
        await Printing.sharePdf(bytes: bytes, filename: _filename('pdf'));
    if (!shared && mounted) {
      setState(
          () => _message = 'Передача документа отменена. Можно скачать файл.');
    }
  }

  Future<void> _sale() async {
    final sale = await sl<SaleRemoteDataSource>()
        .fetchSaleById(key: _key, saleId: _invoice.saleId);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('Продажа № ${sale.number}'),
                content: SizedBox(
                    width: 550,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              'Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(sale.date)}'),
                          Text(
                              'Сумма: ${sale.totalAmount} ${_invoice.currency}'),
                          const SizedBox(height: 12),
                          for (final item in sale.items)
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item.displayProductName),
                                subtitle:
                                    Text('${item.quantity} × ${item.price}'),
                                trailing: Text('${item.totalPrice}')),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Закрыть'))
                ]));
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: InvoiceSheet(
        title: Text('Счёт № ${_invoice.number}'),
        subtitle: 'Реквизиты, документы и банковский перевод',
        content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  InvoiceInfoCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        InvoiceStatusBadge(invoice: _invoice),
                        const SizedBox(height: 18),
                        const Text('Сумма счёта',
                            style: TextStyle(color: invoiceMuted)),
                        const SizedBox(height: 4),
                        Text(invoiceAmount(_invoice.total, _invoice.currency),
                            style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: invoiceInk)),
                        const SizedBox(height: 18),
                        Wrap(spacing: 40, runSpacing: 16, children: [
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Покупатель',
                                    style: TextStyle(
                                        color: invoiceMuted, fontSize: 12)),
                                const SizedBox(height: 5),
                                Text(_invoice.customerName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ]),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Оплатить до',
                                    style: TextStyle(
                                        color: invoiceMuted, fontSize: 12)),
                                const SizedBox(height: 5),
                                Text(invoiceDate(_invoice.dueAt),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ]),
                        ]),
                        if (_invoice.json['paid_at'] != null) ...[
                          const SizedBox(height: 12),
                          Text(
                              'Оплачен: ${invoiceDate('${_invoice.json['paid_at']}')}'),
                        ],
                      ])),
                  if ((_invoice.json['comment'] ?? '')
                      .toString()
                      .isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('${_invoice.json['comment']}',
                        style: const TextStyle(color: invoiceMuted)),
                  ],
                  const SizedBox(height: 24),
                  Text('Товары · ${_invoice.items.length}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final item in _invoice.items)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${item['name'] ?? item['product_name'] ?? (item['product'] is Map ? item['product']['name'] : null) ?? item['product_id'] ?? 'Товар'}'),
                        subtitle:
                            Text('${item['quantity']} × ${item['price']}'),
                        trailing: Text('${item['total_price']}')),
                  const SizedBox(height: 12),
                  const Text('Документы',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(
                        onPressed: _busy ? null : () => _run(_pdf),
                        child: const Text('Открыть PDF')),
                    OutlinedButton(
                        onPressed:
                            _busy ? null : () => _run(() => _download('pdf')),
                        child: const Text('Скачать')),
                    OutlinedButton(
                        onPressed: _busy ? null : () => _run(_share),
                        child: const Text('Поделиться')),
                    OutlinedButton(
                        onPressed:
                            _busy ? null : () => _run(() => _download('xlsx')),
                        child: const Text('Скачать Excel')),
                    if (_invoice.status == 'paid' && _invoice.saleId.isNotEmpty)
                      OutlinedButton(
                          onPressed: _busy ? null : () => _run(_sale),
                          child: const Text('Связанная продажа')),
                  ]),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red))),
                  if (_message != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SelectableText(_message!)),
                ]))),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Закрыть')),
          TextButton(
              onPressed: _busy ? null : () => _run(_reload),
              child: const Text('Обновить')),
          if (_invoice.canCancel)
            OutlinedButton(
                onPressed: _busy ? null : () => _run(_cancel),
                child: const Text('Отменить счёт')),
          if (_invoice.status == 'issued' ||
              _invoice.displayStatus == 'expired')
            FilledButton(
                onPressed:
                    _busy || !_invoice.canConfirm ? null : () => _run(_confirm),
                child: const Text('Подтвердить оплату')),
        ],
      ));
}

class _TransferConfirmation {
  const _TransferConfirmation(this.date, this.comment);
  final DateTime date;
  final String comment;
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.amount, this.saved});
  final String amount;
  final Map<String, dynamic>? saved;
  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late DateTime _date =
      DateTime.tryParse('${widget.saved?['date']}'.replaceFirst(' ', 'T')) ??
          DateTime.now();
  late final _comment = TextEditingController(
      text: widget.saved?['comment']?.toString() ?? 'Оплата поступила');
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Подтвердить банковский перевод'),
          content: SizedBox(
              width: 500,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    'Подтвердите, что полная сумма ${widget.amount} поступила на банковский счёт.'),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дата поступления'),
                    subtitle:
                        Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(_date)),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: widget.saved != null
                        ? null
                        : () async {
                            final date = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now());
                            if (date == null || !context.mounted) return;
                            final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(_date));
                            if (time != null && mounted) {
                              setState(() => _date = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute));
                            }
                          }),
                if (widget.saved != null)
                  const Text(
                      'Повторное подтверждение использует сохранённые дату и комментарий.'),
                InvoiceTextField(
                    enabled: widget.saved == null,
                    controller: _comment,
                    label: 'Комментарий'),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Назад')),
            FilledButton(
                onPressed: () => Navigator.pop(context,
                    _TransferConfirmation(_date, _comment.text.trim())),
                child: const Text('Деньги поступили')),
          ]);
}

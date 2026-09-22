import 'package:flutter/material.dart';
import '../../../data/datasources/customers_remote_datasource.dart';
import 'invoice_design.dart';
import 'invoice_text_field.dart';

class InvoiceCustomerPicker extends StatefulWidget {
  const InvoiceCustomerPicker({super.key, required this.customers});
  final List<CustomerDto> customers;
  @override
  State<InvoiceCustomerPicker> createState() => _InvoiceCustomerPickerState();
}

class _InvoiceCustomerPickerState extends State<InvoiceCustomerPicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final customers = widget.customers
        .where((c) => '${c.name} ${c.phone} ${c.bin} ${c.legalName}'
            .toLowerCase()
            .contains(query))
        .toList();
    return InvoiceSheet(
        title: const Text('Выберите покупателя'),
        subtitle: 'Найдите по имени, телефону или ИИН/БИН',
        content: Column(children: [
          InvoiceTextField(
              controller: _search,
              label: 'Поиск покупателя',
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          Expanded(
              child: customers.isEmpty
                  ? const Center(child: Text('Покупатели не найдены'))
                  : ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return Material(
                            color: const Color(0xFFF5F7FB),
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                                minVerticalPadding: 18,
                                leading: const Icon(Icons.person_outline,
                                    color: invoiceBlue),
                                title: Text(customer.name,
                                    style: const TextStyle(fontSize: 18)),
                                subtitle: [customer.phone, customer.bin]
                                        .where((s) => s.isNotEmpty)
                                        .isEmpty
                                    ? null
                                    : Text([customer.phone, customer.bin]
                                        .where((s) => s.isNotEmpty)
                                        .join(' · ')),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.pop(context, customer)));
                      })),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Назад'))
        ]);
  }
}

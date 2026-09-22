import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:leemon_app/core/models/payment_invoice.dart';

const invoiceBlue = Color(0xFF1155BB);
const invoiceInk = Color(0xFF202C40);
const invoiceMuted = Color(0xFF6C7A90);
const invoiceBorder = Color(0xFFE3E9F1);

String invoiceAmount(num amount, String currency) =>
    '${NumberFormat('#,##0.##', 'ru').format(amount)} ${currency == 'KZT' ? '₸' : currency}';
String invoiceDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? 'Не указан' : DateFormat('dd.MM.yyyy').format(date);
}

class InvoiceSheet extends StatelessWidget {
  const InvoiceSheet(
      {super.key,
      required this.title,
      required this.content,
      required this.actions,
      this.subtitle,
      this.icon = Icons.request_quote_outlined});
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final theme = Theme.of(context);
    return Theme(
        data: theme.copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: invoiceBlue, brightness: Brightness.light),
          textTheme: theme.textTheme
              .apply(bodyColor: invoiceInk, displayColor: invoiceInk),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF5F7FB),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: invoiceBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: invoiceBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: invoiceBlue, width: 1.5)),
          ),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: invoiceBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                  foregroundColor: invoiceBlue,
                  minimumSize: const Size(0, 46),
                  side: const BorderSide(color: invoiceBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)))),
        ),
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: EdgeInsets.all(compact ? 12 : 28),
          clipBehavior: Clip.antiAlias,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
              width: 980,
              height: MediaQuery.sizeOf(context).height * .88,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                        padding: EdgeInsets.all(compact ? 18 : 26),
                        decoration: const BoxDecoration(
                            color: Color(0xFFF7F9FC),
                            border: Border(
                                bottom: BorderSide(color: invoiceBorder))),
                        child: Row(children: [
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE8F0FF),
                                  borderRadius: BorderRadius.circular(16)),
                              child: Icon(icon, color: invoiceBlue, size: 28)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                DefaultTextStyle.merge(
                                    style: TextStyle(
                                        fontSize: compact ? 20 : 26,
                                        fontWeight: FontWeight.w700,
                                        color: invoiceInk),
                                    child: title),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 5),
                                  Text(subtitle!,
                                      style: const TextStyle(
                                          color: invoiceMuted, fontSize: 13))
                                ],
                              ])),
                        ])),
                    Expanded(
                        child: Padding(
                            padding: EdgeInsets.all(compact ? 16 : 26),
                            child: content)),
                    Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 16 : 26, vertical: 16),
                        decoration: const BoxDecoration(
                            border:
                                Border(top: BorderSide(color: invoiceBorder))),
                        child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 8,
                            children: actions)),
                  ])),
        ));
  }
}

class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({super.key, required this.invoice});
  final PaymentInvoice invoice;
  @override
  Widget build(BuildContext context) {
    final (color, background, icon) = switch (invoice.displayStatus) {
      'paid' => (
          const Color(0xFF16754D),
          const Color(0xFFE6F6EE),
          Icons.check_circle_outline
        ),
      'expired' => (
          const Color(0xFFB64732),
          const Color(0xFFFFEDE8),
          Icons.schedule
        ),
      'cancelled' => (invoiceMuted, const Color(0xFFEEF1F5), Icons.block),
      _ => (
          const Color(0xFF946400),
          const Color(0xFFFFF4D8),
          Icons.access_time
        ),
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(invoice.statusLabel,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600))
        ]));
  }
}

class InvoiceInfoCard extends StatelessWidget {
  const InvoiceInfoCard(
      {super.key, required this.child, this.color = const Color(0xFFF7F9FC)});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: invoiceBorder)),
      child: Material(color: Colors.transparent, child: child));
}

import 'package:flutter/material.dart';
import 'package:leemon_app/core/service/kaspi_payment_service.dart';
import 'package:leemon_app/core/service/kaspi_terminal.dart';
import 'kaspi_dialog_style.dart';

class KaspiPaymentDialog extends StatefulWidget {
  const KaspiPaymentDialog(
      {super.key, required this.saleId, required this.amount, this.terminal});
  final String saleId;
  final double amount;
  final KaspiTerminal? terminal;
  @override
  State<KaspiPaymentDialog> createState() => _KaspiPaymentDialogState();
}

class _KaspiPaymentDialogState extends State<KaspiPaymentDialog> {
  bool _busy = true;
  bool _readyForPayment = false;
  bool _closing = false;
  bool _confirmedFailure = false;
  String _message = 'Подключение к Kaspi…';
  @override
  void initState() {
    super.initState();
    _pay();
  }

  Future<void> _pay() async {
    try {
      final result = await (widget.terminal ?? KaspiTerminal.instance).pay(
        saleId: widget.saleId,
        amount: widget.amount,
        onProgress: (message) {
          if (mounted && !_closing) {
            setState(() {
              _message = message;
              if (message == 'Ожидаем оплату на Kaspi. QR или карта.') {
                _readyForPayment = true;
              }
            });
          }
        },
      );
      if (mounted && !_closing) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted && !_closing) {
        setState(() {
          _busy = false;
          _confirmedFailure = e is KaspiPaymentException && e.confirmedFailure;
          _message = e is KaspiPaymentException
              ? e.message
              : 'Связь с Kaspi прервана. Закройте окно и повторите оплату.';
        });
      }
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await (widget.terminal ?? KaspiTerminal.instance)
          .abandonPayment(widget.saleId);
      if (mounted) Navigator.of(context).pop({'status': 'fail'});
    } catch (_) {
      if (mounted) {
        setState(() {
          _closing = false;
          _message = 'Не удалось закрыть оплату. Повторите закрытие.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              KaspiDialogHeader(
                  title: 'Оплата через Kaspi',
                  subtitle: _busy
                      ? (_readyForPayment
                          ? 'Ожидаем оплату покупателя'
                          : 'Отправляем сумму на терминал')
                      : 'Повторите оплату'),
              Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                          width: 112,
                          height: 112,
                          child: Stack(alignment: Alignment.center, children: [
                            Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                    color: _busy
                                        ? const Color(0xFFE8F6F0)
                                        : const Color(0xFFFFF0E9),
                                    borderRadius: BorderRadius.circular(28)),
                                child: Icon(
                                    _busy
                                        ? Icons.point_of_sale_rounded
                                        : Icons.info_outline_rounded,
                                    size: 48,
                                    color: _busy
                                        ? kaspiGreen
                                        : const Color(0xFFBD452F))),
                            if (_busy)
                              const Positioned.fill(
                                  child: CircularProgressIndicator(
                                      color: kaspiGreen,
                                      strokeWidth: 3,
                                      backgroundColor: kaspiSurface)),
                          ])),
                      const SizedBox(height: 22),
                      const Text('СУММА К ОПЛАТЕ',
                          style: TextStyle(
                              color: kaspiMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6)),
                      const SizedBox(height: 6),
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('${_formattedAmount()} ₸',
                              style: const TextStyle(
                                  color: kaspiInk,
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800))),
                      const SizedBox(height: 22),
                      if (_busy && _readyForPayment) ...[
                        const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _PaymentMethod(
                                  icon: Icons.qr_code_rounded,
                                  label: 'Kaspi QR'),
                              Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14),
                                  child: Text('или',
                                      style: TextStyle(color: kaspiMuted))),
                              _PaymentMethod(
                                  icon: Icons.contactless_outlined,
                                  label: 'Карта / NFC'),
                            ]),
                        const SizedBox(height: 22),
                      ],
                      KaspiStatusCard(
                          title: _busy
                              ? (_readyForPayment
                                  ? 'Оплатите на терминале'
                                  : 'Подключение к терминалу')
                              : _confirmedFailure
                                  ? 'Оплата не выполнена'
                                  : 'Не удалось выполнить оплату',
                          message: _message,
                          tone: _busy
                              ? KaspiStatusTone.busy
                              : KaspiStatusTone.error),
                      const SizedBox(height: 18),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: _closing ? null : _close,
                              style: kaspiPrimaryButton(),
                              child: Text(_busy
                                  ? 'Закрыть оплату'
                                  : 'Вернуться к продаже'))),
                    ],
                  )),
            ])),
          ),
        ),
      );

  String _formattedAmount() => widget.amount
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
}

class _PaymentMethod extends StatelessWidget {
  const _PaymentMethod({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: kaspiInk, size: 28),
        const SizedBox(height: 7),
        Text(label,
            style: const TextStyle(
                color: kaspiInk, fontSize: 13, fontWeight: FontWeight.w600)),
      ]);
}

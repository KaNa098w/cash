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
          if (mounted) setState(() => _message = message);
        },
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmedFailure = e is KaspiPaymentException && e.confirmedFailure;
          _message = e is KaspiPaymentException
              ? e.message
              : 'Связь с Kaspi прервана. Операция сохранена. Нажмите «Оплатить» ещё раз для проверки результата.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
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
                      ? 'Ожидаем ответ терминала'
                      : 'Проверьте результат оплаты'),
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
                      if (_busy) ...[
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
                              ? 'Оплатите на терминале'
                              : _confirmedFailure
                                  ? 'Оплата не выполнена'
                                  : 'Нужна проверка оплаты',
                          message: _message,
                          tone: _busy
                              ? KaspiStatusTone.busy
                              : KaspiStatusTone.error),
                      const SizedBox(height: 18),
                      if (_busy)
                        const Text(
                            'Для отмены используйте терминал.\nКасса дождётся подтверждения оплаты.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: kaspiMuted, fontSize: 13, height: 1.5))
                      else
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: () => Navigator.of(context).pop(
                                    _confirmedFailure
                                        ? {'status': 'fail'}
                                        : null),
                                style: kaspiPrimaryButton(),
                                child: const Text('Вернуться к продаже'))),
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

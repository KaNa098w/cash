import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/provider/auth_provider.dart'
    show AuthTokenProvider;
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_dialog.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_page.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../../data/utils/money.dart';
import '../../domain/entities/payment.dart';

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key});

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  final _cashCtrl = TextEditingController();
  bool _paying = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  void _applyTextToState(BuildContext context, String text) {
    final cubit = context.read<PosCubit>();
    final normalized = text.replaceAll(',', '.');
    final value = double.tryParse(normalized) ?? 0;
    cubit.setReceived(value);
  }

  void _setText(BuildContext context, String text) {
    _cashCtrl.text = text;
    _cashCtrl.selection = TextSelection.collapsed(offset: text.length);
    _applyTextToState(context, text);
  }

  Future<void> _pickCustomer() async {
    final posCubit = context.read<PosCubit>();
    final auth = context.read<AuthTokenProvider>();
    final posKey = auth.posKey?.trim() ?? '';

    if (posKey.isEmpty) {
      return;
    }

    try {
      final ds = sl<CustomersRemoteDataSource>();

      final dtos = await ds.listCustomers(key: posKey);

      final customers = dtos
          .map(
            (e) => CustomerLite(
              id: e.id,
              name: e.name,
              phone: e.phone,
              balance: 0,
            ),
          )
          .toList();

      final selected = await showCustomerPickerDialog(
        context,
        customers: customers,
      );

      if (selected == null) return;
      posCubit.setCustomerForActiveTicket(
        PosCustomer(
          id: selected.id,
          name: selected.name,
          phone: selected.phone,
        ),
      );
    } catch (_) {
      // intentionally no snackbar in payment panel
    }
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  final _printService = PrintService();

  Future<void> _showPaymentSuccessDialog(
    BuildContext context, {
    required CreateSaleResult result,
    required String amountText,
    required PaymentKind paymentKind,
  }) async {
    final methodLabel = switch (paymentKind) {
      PaymentKind.cash => 'РќР°Р»РёС‡РЅС‹Рµ',
      PaymentKind.card => 'Р‘РµР·РЅР°Р»РёС‡РЅС‹Р№',
      PaymentKind.credit => 'Р’ РґРѕР»Рі',
    };
    final subtitle = switch (result) {
      CreateSaleResult.sent => 'РћРїР»Р°С‚Р° РїСЂРѕРІРµРґРµРЅР° Рё РѕС‚РїСЂР°РІР»РµРЅР° РЅР° СЃРµСЂРІРµСЂ',
      CreateSaleResult.queued => 'РћРїР»Р°С‚Р° РїСЂРёРЅСЏС‚Р°. РџСЂРѕРґР°Р¶Р° СЃРѕС…СЂР°РЅРµРЅР° РІ РѕС‡РµСЂРµРґРё',
      CreateSaleResult.rejected => 'РћРїР»Р°С‚Р° РѕС‚РєР»РѕРЅРµРЅР°',
    };

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'payment-success',
      barrierColor: Colors.black.withOpacity(0.48),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, __) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 420,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFECFDF3), Color(0xFFFFFFFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF15803D).withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFDCFCE7),
                        border: Border.all(
                          color: const Color(0xFF86EFAC),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 42,
                        color: Color(0xFF15803D),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'РћРїР»Р°С‚Р° РїСЂРѕС€Р»Р° СѓСЃРїРµС€РЅРѕ',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF14532D),
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            amountText,
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF111827),
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$methodLabel вЂў $subtitle',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Р“РѕС‚РѕРІРѕ',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  Future<pw.Document> _buildReceipt(
    PosCubit cubit, {
    required PdfPageFormat pageFormat,
    required String storeName,
  }) async {
    final items = cubit.state.items;
    final total = cubit.total;
    final discountSum = cubit.discountSum;
    final received = cubit.state.received;
    final change = cubit.change.clamp(0, double.infinity);

    final base = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();
    final mono = await PdfGoogleFonts.robotoMonoRegular();

    final doc = pw.Document();

    pw.Widget rowKV(String k, String v, {bool strong = false, double fs = 8}) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
              child: pw.Text(k,
                  style:
                      pw.TextStyle(font: strong ? bold : base, fontSize: fs))),
          pw.Text(v,
              style: pw.TextStyle(font: strong ? bold : base, fontSize: fs)),
        ],
      );
    }

    pw.Widget divider() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Divider(height: 1, thickness: 1),
        );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        orientation: pw.PageOrientation.portrait,
        margin: const pw.EdgeInsets.only(right: 18, top: 12, bottom: 12),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(storeName,
                  style: pw.TextStyle(font: bold, fontSize: 10),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 2),
              pw.Text('Р”Р°С‚Р°: ${DateTime.now().toLocal()}',
                  style: pw.TextStyle(font: base, fontSize: 7)),
              divider(),
              for (final it in items) ...[
                pw.Text(it.product.name,
                    style: pw.TextStyle(font: base, fontSize: 8)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${it.qty} x ${money(it.product.price)}'
                      '${it.discount > 0 ? '  (-${it.discount.toStringAsFixed(0)}%)' : ''}',
                      style: pw.TextStyle(font: mono, fontSize: 8),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(money(it.sum),
                        style: pw.TextStyle(font: mono, fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],
              divider(),
              rowKV('Р‘РµР· СЃРєРёРґРѕРє', money(total + discountSum)),
              rowKV('РЎРєРёРґРєР°', money(discountSum)),
              rowKV('РРўРћР“Рћ', money(total), strong: true),
              pw.SizedBox(height: 3),
              rowKV('РџРѕР»СѓС‡РµРЅРѕ', money(received)),
              rowKV('РЎРґР°С‡Р°', money(change), strong: true),
              pw.SizedBox(height: 4),
              rowKV(
                  'РњРµС‚РѕРґ',
                  switch (cubit.state.paymentKind) {
                    PaymentKind.cash => 'РќР°Р»РёС‡РЅС‹Рµ',
                    PaymentKind.card => 'Р‘РµР·РЅР°Р»',
                    PaymentKind.credit => 'Р’ РґРѕР»Рі',
                  }),
              pw.SizedBox(height: 6),
              pw.Text('РЎРїР°СЃРёР±Рѕ Р·Р° РїРѕРєСѓРїРєСѓ!',
                  style: pw.TextStyle(font: base, fontSize: 8),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 35 * PdfPageFormat.mm),
            ],
          );
        },
      ),
    );

    return doc;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520,
      width: 550,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: BlocConsumer<PosCubit, PosState>(
          listenWhen: (prev, curr) => prev.received != curr.received,
          listener: (context, state) {
            final text = _fmt(state.received);
            if (_cashCtrl.text != text) {
              _setText(context, text);
            }
          },
          builder: (context, state) {
            final cubit = context.read<PosCubit>();
            final total = cubit.total;
            final change = cubit.change.clamp(0, double.infinity);

            void setReceivedText(String text) {
              _cashCtrl.text = text;
              _cashCtrl.selection =
                  TextSelection.collapsed(offset: text.length);
              _applyTextToState(context, text);
            }

            void appendToken(String token) {
              var t = _cashCtrl.text;

              if (token == 'вЊ«') {
                if (t.isNotEmpty) t = t.substring(0, t.length - 1);
                setReceivedText(t);
                return;
              }

              if (token == '.') {
                if (!t.contains('.')) {
                  t = t.isEmpty ? '0.' : '$t.';
                }
                setReceivedText(t);
                return;
              }

              t = t == '0' ? token : '$t$token';

              t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
              setReceivedText(t);
            }

            void addQuick(int inc) {
              final curr =
                  double.tryParse(_cashCtrl.text.replaceAll(',', '.')) ?? 0;
              final next = curr + inc;
              setReceivedText(_fmt(next));
            }

            final customerName = state.activeCustomer?.name.trim();
            final customerButtonText =
                (customerName != null && customerName.isNotEmpty)
                    ? customerName
                    : 'РџРћРљРЈРџРђРўР•Р›Р¬';

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F343C),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 210,
                            child: _TopAmountBox(
                              label: 'Рљ РѕРїР»Р°С‚Рµ',
                              value: money(total),
                              selected: false,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 175,
                            child: _TopAmountBox(
                              label: 'РЎРґР°С‡Р°',
                              value: money(change),
                              selected: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 215,
                          child: _BlueInput(
                            label: '',
                            controller: _cashCtrl,
                            onChanged: (v) => _applyTextToState(context, v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 174,
                          height: 41,
                          child: _WhiteButton(
                            text: customerButtonText,
                            onTap: _pickCustomer,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0, right: 12.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 210,
                            child: _Keypad3x4(onTap: appendToken),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                _QuickGrid(
                                  onTap: (v) => addQuick(v),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _GreyButton(
                                        text: 'РЎС‡РµС‚Р° РЅР°\nРѕРїР»Р°С‚Сѓ',
                                        height: 46,
                                        selected: false,
                                        onTap: () {},
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _GreyButton(
                                        text: 'Р’ РґРѕР»Рі',
                                        height: 46,
                                        selected: state.paymentKind ==
                                            PaymentKind.credit,
                                        onTap: () => cubit
                                            .setPaymentKind(PaymentKind.credit),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _OrangePayTag(
                                  text: 'Р‘РµР·РЅР°Р»РёС‡РЅС‹Р№',
                                  selected:
                                      state.paymentKind == PaymentKind.card,
                                  onTap: () =>
                                      cubit.setPaymentKind(PaymentKind.card),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: _BottomButton(
                            text: 'РћРўРњР•РќРђ',
                            bg: const Color(0xFFD9534F),
                            fg: Colors.white,
                            onTap: () {
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 100,
                          child: _BottomButton(
                            text: 'Р‘Р•Р— РЎР”РђР§Р',
                            bg: const Color(0xFF9CA3AF),
                            fg: Colors.white,
                            onTap: () {
                              cubit.setPaymentKind(PaymentKind.cash);
                              setReceivedText(_fmt(total));
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 175,
                          child: _BottomButton(
                            text: 'РћРџР›РђРўРђ',
                            bg: const Color(0xFF35C28A),
                            fg: Colors.white,
                            loading: _paying,
                            onTap: _paying
                                ? null
                                : () async {
                                    final posCubit = context.read<PosCubit>();
                                    final auth =
                                        context.read<AuthTokenProvider>();

                                    final key = auth.posKey?.trim() ?? '';
                                    final deviceId =
                                        auth.deviceId?.trim() ?? '';
                                    final storeId = auth.storeId?.trim() ?? '';
                                    final posId = auth.posId?.trim() ?? '';
                                    final userId = auth.users.first.id ?? '';

                                    if (key.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('РќРµС‚ РєР»СЋС‡Р° POS (posKey)')),
                                      );
                                      return;
                                    }
                                    if (deviceId.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('РќРµС‚ deviceId')),
                                      );
                                      return;
                                    }
                                    if (storeId.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('РќРµС‚ storeId')),
                                      );
                                      return;
                                    }
                                    if (posId.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('РќРµС‚ posId (accountId)')),
                                      );
                                      return;
                                    }
                                    if (posCubit.state.items.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('РљРѕСЂР·РёРЅР° РїСѓСЃС‚Р°СЏ')),
                                      );
                                      return;
                                    }

                                    if (posCubit.state.paymentKind ==
                                            PaymentKind.cash &&
                                        posCubit.state.received <
                                            posCubit.total) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'РќРµРґРѕСЃС‚Р°С‚РѕС‡РЅРѕ РІРЅРµСЃРµРЅРѕ РЅР°Р»РёС‡РЅС‹С…')),
                                      );
                                      return;
                                    }

                                    final saleItems = <SaleItemModel>[];
                                    for (final it in posCubit.state.items) {
                                      if (it.qty % 1 != 0) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Р”СЂРѕР±РЅРѕРµ РєРѕР»РёС‡РµСЃС‚РІРѕ РЅРµ РїРѕРґРґРµСЂР¶РёРІР°РµС‚СЃСЏ: ${it.product.name}')),
                                        );
                                        return;
                                      }
                                      final qty = it.qty.toInt();
                                      final price = it.product.price.round();
                                      final totalPrice =
                                          (it.product.price * it.qty).round();

                                      saleItems.add(
                                        SaleItemModel(
                                          productId: it.product.id,
                                          quantity: qty,
                                          price: price,
                                          totalPrice: totalPrice,
                                          id: '',
                                          saleId: '',
                                        ),
                                      );
                                    }

                                    final paymentMethod =
                                        switch (posCubit.state.paymentKind) {
                                      PaymentKind.cash => 'cash',
                                      PaymentKind.card => 'card',
                                      PaymentKind.credit => 'credit',
                                    };

                                    final customerId = context
                                        .read<PosCubit>()
                                        .state
                                        .activeCustomer
                                        ?.id;

                                    final sale = SaleModel(
                                      localId: const Uuid().v4(),
                                      number: '',
                                      date: DateTime.now(),
                                      totalAmount: posCubit.total.round(),
                                      paymentMethod: paymentMethod,
                                      posId: posId,
                                      storeId: storeId,
                                      userId: userId,
                                      accountId: userId,
                                      customerId: customerId,
                                      items: saleItems,
                                    );

                                    final repo = GetIt.I<SaleRepository>();

                                    setState(() => _paying = true);
                                    try {
                                      final pageFormat =
                                          auth.receiptPaperMm == 57
                                              ? PdfPageFormat.roll57
                                              : PdfPageFormat.roll80;
                                      final totalPaid = posCubit.total;
                                      final paymentKind =
                                          posCubit.state.paymentKind;
                                      final result = await repo.createSale(
                                        key: key,
                                        deviceId: deviceId,
                                        sale: sale,
                                      );

                                      await _printService.print80mmSilently(
                                        () => _buildReceipt(
                                          posCubit,
                                          pageFormat: pageFormat,
                                          storeName: (() { final name = (auth.storeName ?? '').trim(); return name.isEmpty ? 'РќР°РёРјРµРЅРѕРІР°РЅРёРµ РјР°РіР°Р·РёРЅР°' : name; })(),

                                        ),
                                      );

                                      if (!mounted) return;
                                      if (result == CreateSaleResult.rejected) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'РџСЂРѕРґР°Р¶Р° РѕС‚РєР»РѕРЅРµРЅР° СЃРµСЂРІРµСЂРѕРј'),
                                          ),
                                        );
                                        return;
                                      }

                                      final rootContext = Navigator.of(context,
                                              rootNavigator: true)
                                          .context;
                                      Navigator.of(context).pop();
                                      posCubit.clearAfterPayment();
                                      await _showPaymentSuccessDialog(
                                        rootContext,
                                        result: result,
                                        amountText: money(totalPaid),
                                        paymentKind: paymentKind,
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text('РћС€РёР±РєР° РѕРїР»Р°С‚С‹: $e')),
                                      );
                                    } finally {
                                      if (mounted)
                                        setState(() => _paying = false);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class FlatGrey extends StatelessWidget {
  const FlatGrey(
      {required this.text,
      required this.onTap,
      this.width = 100,
      this.height = 44});
  final String text;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(Size(width, height)),
          fixedSize: MaterialStateProperty.all(Size(width, height)),
          padding: MaterialStateProperty.all(EdgeInsets.zero),
          backgroundColor: MaterialStateProperty.all(const Color(0xFFD1D5DB)),
          foregroundColor: MaterialStateProperty.all(const Color(0xFF111827)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TopAmountBox extends StatelessWidget {
  const _TopAmountBox({
    required this.label,
    required this.value,
    required this.selected,
  });

  final String label;
  final String value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final border = selected ? const Color(0xFF3B82F6) : const Color(0xFFE5E7EB);
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueInput extends StatelessWidget {
  const _BlueInput({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 43,
      width: 220,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          isDense: true,
          filled: true,
          fillColor: ThemeColors.greyB,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF00A1FF), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF00A1FF), width: 1),
          ),
          labelStyle: const TextStyle(
            color: Color(0xFF00A1FF),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Keypad3x4 extends StatelessWidget {
  const _Keypad3x4({required this.onTap});
  final void Function(String) onTap;

  static const _rows = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['.', '0', 'вЊ«'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in _rows) ...[
          Row(
            children: [
              for (int i = 0; i < r.length; i++) ...[
                Expanded(
                  child: SizedBox(
                    height: 60,
                    width: 273,
                    child: r[i].isEmpty
                        ? const SizedBox.shrink()
                        : TextButton(
                            onPressed: () => onTap(r[i]),
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF8F8F8F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              r[i],
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ),
                if (i != r.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.onTap});
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    Widget btn(String text, int value) {
      return SizedBox(
        height: 46,
        child: TextButton(
          onPressed: () => onTap(value),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF111827),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [
          Expanded(child: btn('+200', 200)),
          const SizedBox(width: 10),
          Expanded(child: btn('+500', 500))
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: btn('+1 000', 1000)),
          const SizedBox(width: 10),
          Expanded(child: btn('+2 000', 2000))
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: btn('+5 000', 5000)),
          const SizedBox(width: 10),
          Expanded(child: btn('+10 000', 10000))
        ]),
      ],
    );
  }
}

class _GreyButton extends StatelessWidget {
  const _GreyButton({
    required this.text,
    required this.onTap,
    required this.height,
    this.selected = false,
  });

  final String text;
  final VoidCallback onTap;
  final double height;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFF59E0B) : Colors.white;
    final fg = selected ? Colors.white : const Color(0xFF111827);
    final border = selected ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB);

    return SizedBox(
      height: height,
      child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: border, width: 1),
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1,
              color: fg,
            ),
          )),
    );
  }
}

class _OrangePayTag extends StatelessWidget {
  const _OrangePayTag({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFF59E0B) : Colors.white;
    final fg = selected ? Colors.white : const Color(0xFF111827);
    final border = selected ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB);

    return SizedBox(
      height: 44,
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: border, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              alignment: Alignment.center,
              child: Icon(Icons.credit_card, size: 18, color: fg),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.interTextTheme().bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.text,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.loading = false,
  });

  final String text;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minimumSize: const Size(0, 52),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

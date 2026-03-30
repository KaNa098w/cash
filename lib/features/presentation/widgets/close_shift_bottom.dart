import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';

import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';

class CloseShiftPage extends StatefulWidget {
  const CloseShiftPage({super.key});

  @override
  State<CloseShiftPage> createState() => _CloseShiftPageState();
}

class _CloseShiftPageState extends State<CloseShiftPage> {
  final _ctrl = TextEditingController(text: '');
  final _amountFocusNode = FocusNode();
  bool _submitting = false;
  bool _showSuccessState = false;
  bool _summaryExpanded = false;
  late final Future<ShiftClosureSummaryData?> _summaryFuture;

  @override
  void initState() {
    super.initState();
    final sessionId = context.read<AuthTokenProvider>().shiftId?.trim() ?? '';
    _summaryFuture = sessionId.isEmpty
        ? Future<ShiftClosureSummaryData?>.value(null)
        : GetIt.I<PosSyncService>().loadShiftClosureSummary(sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _focusAmountInput();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _focusAmountInput() {
    if (!mounted) return;
    _amountFocusNode.requestFocus();
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  num? _parseAmount(String s) {
    final v = s.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final amount = _parseAmount(_ctrl.text);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректную сумму')),
      );
      return;
    }

    setState(() => _submitting = true);
    await context.read<AuthCubit>().closeSessionWithCash(
          closingCashAmount: amount,
        );
    if (mounted) setState(() => _submitting = false);
  }

  void _closePage() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go('/pos');
  }

  @override
  Widget build(BuildContext context) {
    final tokenProvider = context.read<AuthTokenProvider>();
    final hasShift = tokenProvider.hasShiftId;

    return BlocConsumer<AuthCubit, AuthState>(
      listenWhen: (prev, curr) =>
          curr is AuthFailure ||
          curr is AuthShiftClosed ||
          curr is AuthProvisioned ||
          curr is AuthInitial,
      listener: (context, state) {
        if (state is AuthFailure) {
          if (mounted) {
            setState(() {
              _showSuccessState = false;
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          return;
        }

        if (state is AuthShiftClosed) {
          if (mounted) {
            setState(() => _showSuccessState = true);
          }
          return;
        }

        if (_showSuccessState) return;
      },
      builder: (context, state) {
        final isLoading =
            state is AuthClosingSession || _submitting || _showSuccessState;
        final loadingState = state is AuthClosingSession ? state : null;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F1E7),
          body: SafeArea(
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF7F1E5),
                        Color(0xFFEAF2F8),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: isLoading ? null : _closePage,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF111827),
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Сдать смену',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Закрой смену на отдельной странице без конфликта с поиском и фокусом.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        blurRadius: 24,
                                        offset: const Offset(0, 16),
                                      ),
                                    ],
                                  ),
                                  child: hasShift
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: SingleChildScrollView(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 14,
                                                        vertical: 10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                            0xFFFFF4E5),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          999,
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'Финальная проверка кассы',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              Color(0xFFB45309),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 18),
                                                    const Text(
                                                      'Сколько наличных осталось в кассе?',
                                                      style: TextStyle(
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color:
                                                            Color(0xFF111827),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    const Text(
                                                      'Кнопка сдачи смены закреплена ниже, а здесь показывается только краткая сводка по смене.',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        height: 1.45,
                                                        color:
                                                            Color(0xFF6B7280),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 18),
                                                    FutureBuilder<
                                                        ShiftClosureSummaryData?>(
                                                      future: _summaryFuture,
                                                      builder:
                                                          (context, snapshot) {
                                                        final summary =
                                                            snapshot.data;
                                                        if (summary == null) {
                                                          return Container(
                                                            width:
                                                                double.infinity,
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(
                                                              16,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                0xFFF9FAFB,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                20,
                                                              ),
                                                            ),
                                                            child: const Text(
                                                              'Сводка по смене загружается...',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                  0xFF6B7280,
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                        return _ShiftSummaryCard(
                                                          summary: summary,
                                                          expanded:
                                                              _summaryExpanded,
                                                          onToggle: () {
                                                            setState(() {
                                                              _summaryExpanded =
                                                                  !_summaryExpanded;
                                                            });
                                                          },
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(height: 22),
                                                    TextField(
                                                      controller: _ctrl,
                                                      focusNode:
                                                          _amountFocusNode,
                                                      autofocus: true,
                                                      keyboardType:
                                                          const TextInputType
                                                              .numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                      textInputAction:
                                                          TextInputAction.done,
                                                      inputFormatters: [
                                                        FilteringTextInputFormatter
                                                            .allow(
                                                          RegExp(r'[0-9\.,]'),
                                                        ),
                                                      ],
                                                      onSubmitted: (_) =>
                                                          _submit(),
                                                      onTap: _focusAmountInput,
                                                      style: const TextStyle(
                                                        fontSize: 34,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color:
                                                            Color(0xFF111827),
                                                      ),
                                                      decoration:
                                                          InputDecoration(
                                                        filled: true,
                                                        fillColor: const Color(
                                                          0xFFF9FAFB,
                                                        ),
                                                        labelText:
                                                            'Фактическая сумма',
                                                        hintText: '0',
                                                        border:
                                                            OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            24,
                                                          ),
                                                          borderSide:
                                                              BorderSide.none,
                                                        ),
                                                        contentPadding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 22,
                                                          vertical: 24,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 20),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: isLoading
                                                        ? null
                                                        : _closePage,
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        vertical: 18,
                                                      ),
                                                      side: const BorderSide(
                                                        color:
                                                            Color(0xFFD1D5DB),
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          18,
                                                        ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Отмена',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color:
                                                            Color(0xFF374151),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: isLoading
                                                        ? null
                                                        : _submit,
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      elevation: 0,
                                                      backgroundColor:
                                                          const Color(
                                                              0xFFBE3A14),
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        vertical: 18,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          18,
                                                        ),
                                                      ),
                                                    ),
                                                    child: isLoading
                                                        ? const SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          )
                                                        : const Text(
                                                            'Сдать смену',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Смена не открыта',
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF111827),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              'Закрывать нечего. Вернись назад и открой смену заново при необходимости.',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                            const Spacer(),
                                            SizedBox(
                                              width: 220,
                                              child: ElevatedButton(
                                                onPressed: _closePage,
                                                style: ElevatedButton.styleFrom(
                                                  elevation: 0,
                                                  backgroundColor:
                                                      const Color(0xFF111827),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    vertical: 18,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      18,
                                                    ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Назад',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 4,
                                child: IgnorePointer(
                                  ignoring: isLoading,
                                  child: Opacity(
                                    opacity: isLoading ? 0.55 : 1,
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2C3444),
                                        borderRadius: BorderRadius.circular(28),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.10),
                                            blurRadius: 24,
                                            offset: const Offset(0, 16),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Клавиатура',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Можно вводить сумму цифрами на клавиатуре или кнопками ниже.',
                                            style: TextStyle(
                                              color: Color(0xFFCBD5E1),
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          Expanded(
                                            child: AmountKeypad(
                                              text: _ctrl.text,
                                              onChanged: (t) {
                                                setState(() {
                                                  _ctrl.text = t;
                                                  _ctrl.selection =
                                                      TextSelection.collapsed(
                                                    offset: t.length,
                                                  );
                                                });
                                                _focusAmountInput();
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xAA111827),
                      alignment: Alignment.center,
                      child: Container(
                        width: 460,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 34,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 54,
                              height: 54,
                              child: _LoadingOrSuccessIcon(
                                showSuccess: _showSuccessState,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _showSuccessState
                                  ? 'Смена успешно закрыта'
                                  : (loadingState?.title ?? 'Закрываем смену'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _showSuccessState
                                  ? 'Смена завершена успешно. Нажми "ОК", чтобы перейти к странице кассиров.'
                                  : (loadingState?.message ??
                                      'Подожди немного, касса завершает операцию.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_showSuccessState)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    final hasProvision = context
                                            .read<AuthTokenProvider>()
                                            .cachedProvision !=
                                        null;
                                    context.go(
                                        hasProvision ? '/cashiers' : '/login');
                                  },
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: const Color(0xFF0F766E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text(
                                    'ОК',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Text(
                                  'Не закрывай приложение и не выключай принтер во время завершения смены.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.bg,
  });

  final String label;
  final String value;
  final Color accent;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftSummaryCard extends StatelessWidget {
  const _ShiftSummaryCard({
    required this.summary,
    required this.expanded,
    required this.onToggle,
  });

  final ShiftClosureSummaryData summary;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Должно быть в кассе',
            value: money(summary.expectedCashAmount),
            strong: true,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Итого продаж',
            value: money(summary.totalSalesAmount),
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Возвраты',
            value: '-${money(summary.refundsTotal)}',
            valueColor: const Color(0xFFBE3A14),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onToggle,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                expanded ? 'Скрыть полный отчет' : 'Показать полный отчет',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF374151),
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            _SummaryRow(
              label: 'Наличные при открытии',
              value: money(summary.openingCashAmount),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Продажи наличными',
              value: '+${money(summary.cashSalesTotal)}',
              valueColor: const Color(0xFF0F766E),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Продажи картой',
              value: money(summary.cardSalesTotal),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Продажи переводом',
              value: money(summary.transferSalesTotal),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Итого продаж',
              value: money(summary.totalSalesAmount),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Возвраты наличными',
              value: '-${money(summary.refundsTotal)}',
              valueColor: const Color(0xFFBE3A14),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Приход в кассу',
              value: '+${money(summary.incomeTotal)}',
              valueColor: const Color(0xFF0F766E),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Расход из кассы',
              value: '-${money(summary.expenseTotal)}',
              valueColor: const Color(0xFFBE3A14),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: strong ? 16 : 13,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
            color: valueColor ?? const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

class _LoadingOrSuccessIcon extends StatelessWidget {
  const _LoadingOrSuccessIcon({
    required this.showSuccess,
  });

  final bool showSuccess;

  @override
  Widget build(BuildContext context) {
    if (!showSuccess) {
      return const CircularProgressIndicator(
        strokeWidth: 4,
        color: Color(0xFFBE3A14),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE7F8F2),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_rounded,
        color: Color(0xFF0F766E),
        size: 34,
      ),
    );
  }
}

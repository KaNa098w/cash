import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/entities/payment.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';
import 'package:leemon_app/features/presentation/widgets/app_scroll_behovir.dart';

class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key});

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  final _customersDs = sl<CustomersRemoteDataSource>();
  final _salesDs = sl<SaleRemoteDataSource>();
  final _sync = sl<PosSyncService>();

  List<CustomerDto> _items = const [];
  List<SaleModel> _customerSales = const [];
  List<CustomerSettlementHistoryDto> _customerSettlements = const [];
  int? _selectedIndex;
  bool _loading = true;
  bool _salesLoading = false;
  bool _settlementsLoading = false;
  bool _settling = false;
  bool _refreshingOnline = false;
  int _customerDataRevision = 0;
  String? _error;
  String? _salesError;
  String? _settlementsError;
  StreamSubscription<void>? _debtsChangedSub;
  final _customersScrollController = ScrollController();
  final _salesScrollController = ScrollController();

  CustomerDto? get _selectedItem {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _items.length) return null;
    return _items[index];
  }

  @override
  void initState() {
    super.initState();
    _debtsChangedSub = _sync.onDebtsChanged.listen((_) {
      if (!mounted) return;
      _customerDataRevision += 1;
      unawaited(_loadDebts(refreshOnline: false));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDebts());
  }

  @override
  void dispose() {
    _debtsChangedSub?.cancel();
    _customersScrollController.dispose();
    _salesScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDebts({bool refreshOnline = true}) async {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'POS key пустой';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadLocalDebts();
    if (refreshOnline) {
      unawaited(_refreshDebtsOnline());
    }
  }

  Future<void> _loadLocalDebts() async {
    try {
      final localCustomers = await _sync.loadCustomers();
      final debtCustomers = localCustomers
          .map((customer) {
            try {
              return CustomerDto.fromJson(customer.rawJson);
            } catch (_) {
              return null;
            }
          })
          .whereType<CustomerDto>()
          .where((customer) => customer.debtBalance > 0)
          .toList(growable: false);
      debtCustomers
          .sort((a, b) => b.debtBalance.abs().compareTo(a.debtBalance.abs()));
      if (!mounted) return;
      final currentSelectedId = _selectedItem?.id;
      final nextIndex = currentSelectedId == null
          ? (debtCustomers.isEmpty ? null : 0)
          : debtCustomers.indexWhere((item) => item.id == currentSelectedId);
      setState(() {
        _items = debtCustomers;
        _selectedIndex = debtCustomers.isEmpty
            ? null
            : nextIndex == null || nextIndex < 0
                ? 0
                : nextIndex;
        _loading = false;
        _error = null;
      });
      final selected = _selectedItem;
      if (selected != null) {
        await _loadCustomerSales(selected, refreshOnline: false);
        unawaited(_loadCustomerSettlements(selected));
      } else {
        setState(() {
          _customerSales = const [];
          _customerSettlements = const [];
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить локальные долги: $e';
      });
    }
  }

  Future<void> _refreshDebtsOnline() async {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty || _refreshingOnline) return;

    setState(() {
      _refreshingOnline = true;
      _error = null;
    });
    final revisionAtStart = _customerDataRevision;

    try {
      final customers = await _customersDs.listCustomers(
        key: key,
        size: 500,
        hasDebt: true,
      );
      if (revisionAtStart != _customerDataRevision) {
        if (mounted) setState(() => _refreshingOnline = false);
        return;
      }
      await _sync.upsertCustomersRaw(
        customers.map((customer) => customer.toJson()).toList(growable: false),
      );
      final debtCustomers = customers
          .where((customer) => customer.debtBalance > 0)
          .toList(growable: false);
      debtCustomers
          .sort((a, b) => b.debtBalance.abs().compareTo(a.debtBalance.abs()));
      if (!mounted) return;
      final currentSelectedId = _selectedItem?.id;
      final nextIndex = currentSelectedId == null
          ? (debtCustomers.isEmpty ? null : 0)
          : debtCustomers.indexWhere((item) => item.id == currentSelectedId);
      setState(() {
        _items = debtCustomers;
        _selectedIndex = debtCustomers.isEmpty
            ? null
            : nextIndex == null || nextIndex < 0
                ? 0
                : nextIndex;
        _loading = false;
        _refreshingOnline = false;
      });
      final selected = _selectedItem;
      if (selected != null) {
        unawaited(_loadCustomerSales(selected));
        unawaited(_loadCustomerSettlements(selected));
      }
    } catch (e) {
      if (!mounted) return;
      if (revisionAtStart != _customerDataRevision) {
        setState(() => _refreshingOnline = false);
        return;
      }
      setState(() {
        _loading = false;
        _refreshingOnline = false;
        _error = 'Не удалось загрузить долги: $e';
      });
    }
  }

  Future<void> _loadCustomerSales(
    CustomerDto customer, {
    bool refreshOnline = true,
  }) async {
    await _loadCustomerSalesLocal(customer);
    if (refreshOnline) {
      unawaited(_refreshCustomerSalesOnline(customer));
    }
  }

  Future<void> _loadCustomerSalesLocal(CustomerDto customer) async {
    setState(() {
      _salesLoading = true;
      _salesError = null;
      _customerSales = const [];
    });

    try {
      final sales = await _sync.loadAllSalesHistory();
      final unpaidSales = sales
          .where((sale) =>
              sale.customerId == customer.id && sale.documentUnpaidAmount > 0)
          .toList(growable: false);
      if (!mounted || _selectedItem?.id != customer.id) return;
      setState(() {
        _customerSales = unpaidSales;
        _salesLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedItem?.id != customer.id) return;
      setState(() {
        _salesError = 'Не удалось загрузить локальные продажи: $e';
        _salesLoading = false;
      });
    }
  }

  Future<void> _refreshCustomerSalesOnline(CustomerDto customer) async {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) return;

    setState(() {
      _salesLoading = true;
      _salesError = null;
      _customerSales = const [];
    });

    try {
      final sales = await _salesDs.getAllSales(
        key: key,
        perPage: 100,
        customerId: customer.id,
      );
      await _sync.upsertSalesHistory(sales);
      final unpaidSales = sales
          .where((sale) => sale.documentUnpaidAmount > 0)
          .toList(growable: false);
      if (!mounted || _selectedItem?.id != customer.id) return;
      setState(() {
        _customerSales = unpaidSales;
        _salesLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedItem?.id != customer.id) return;
      setState(() {
        _salesError = 'Не удалось загрузить продажи: $e';
        _salesLoading = false;
      });
    }
  }

  Future<void> _loadCustomerSettlements(CustomerDto customer) async {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) return;
    setState(() {
      _settlementsLoading = true;
      _settlementsError = null;
      _customerSettlements = const [];
    });

    try {
      final settlements = await _customersDs.listDebtSettlements(
        key: key,
        customerId: customer.id,
      );
      if (!mounted || _selectedItem?.id != customer.id) return;
      setState(() {
        _customerSettlements = settlements;
        _settlementsLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedItem?.id != customer.id) return;
      setState(() {
        _settlementsLoading = false;
        _settlementsError = 'Не удалось загрузить погашения: $e';
      });
    }
  }

  Future<void> _settleSelectedDebt() async {
    final selected = _selectedItem;
    final index = _selectedIndex;
    if (selected == null || index == null || _settling) return;

    if (selected.debtBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У покупателя нет долга к погашению')),
      );
      return;
    }

    final amount = await _showDebtAmountDialog(
      context,
      title: 'Погасить долг',
      actionLabel: 'Погасить',
      accentColor: const Color(0xFF16A34A),
      maxAmount: selected.debtBalance,
    );
    if (amount == null || amount <= 0 || !mounted) return;

    final auth = context.read<AuthTokenProvider>();
    final key = auth.posKey?.trim() ?? '';
    final userId = auth.activeUserId?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? 'pos';
    final accountId = auth.accountId?.trim() ?? '';
    if (key.isEmpty || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не найдены данные кассы или кассира')),
      );
      return;
    }
    if (accountId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не найден наличный счёт POS')),
      );
      return;
    }

    setState(() {
      _settling = true;
      // Any customer-list request started before this settlement contains an
      // older debt balance and must not overwrite the settlement response.
      _customerDataRevision += 1;
    });
    try {
      final localSessionId = auth.shiftId?.trim() ?? '';
      final resolvedSessionId = localSessionId.isEmpty
          ? ''
          : await _sync.resolveServerSessionId(localSessionId);
      final posSessionId =
          resolvedSessionId.startsWith('session_') ? null : resolvedSessionId;

      final settlement = await _customersDs.settleDebt(
        key: key,
        customerId: selected.id,
        accountId: accountId,
        amount: amount,
        date: DateTime.now(),
        userId: userId,
        posSessionId: posSessionId,
        clientSettlementId: '$deviceId-settlement-${const Uuid().v4()}',
        note: 'Погашение долга через POS',
      );
      await _sync.upsertCustomersRaw([settlement.agent.toJson()]);

      if (!mounted) return;
      setState(() {
        final nextItems = List<CustomerDto>.from(_items);
        final removed = settlement.agent.debtBalance == 0;
        if (removed) {
          nextItems.removeAt(index);
        } else {
          nextItems[index] = settlement.agent;
        }
        nextItems
            .sort((a, b) => b.debtBalance.abs().compareTo(a.debtBalance.abs()));
        _items = nextItems;
        _selectedIndex = nextItems.isEmpty
            ? null
            : removed
                ? index.clamp(0, nextItems.length - 1).toInt()
                : nextItems.indexWhere(
                    (item) => item.id == settlement.agent.id,
                  );
        _settling = false;
      });
      final nextSelected = _selectedItem;
      if (nextSelected != null) {
        await _loadCustomerSales(nextSelected);
        unawaited(_loadCustomerSettlements(nextSelected));
      }
      await _loadDebts(refreshOnline: true);
      if (!mounted) return;
      await _showSettlementSuccessDialog(
        context,
        customerName: settlement.agent.name,
        paidAmount: amount,
        remainingDebt: settlement.agent.debtBalance,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _settling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось погасить долг: $e')),
      );
    }
  }

  void _openDebtSale() {
    final selected = _selectedItem;
    if (selected == null) return;

    final posCubit = context.read<PosCubit>();
    posCubit.setCustomerForActiveTicket(
      PosCustomer(
        id: selected.id,
        name: selected.name,
        phone: selected.phone,
        balance: selected.debtBalance,
        debtLimit: selected.debtLimit,
        debtAllowed: selected.debtAllowed,
      ),
    );
    posCubit.setPaymentKind(PaymentKind.credit);
    context.go('/pos');
  }

  void _selectCustomer(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() => _selectedIndex = index);
    if (_salesScrollController.hasClients) {
      _salesScrollController.jumpTo(0);
    }
    _loadCustomerSales(_items[index]);
    _loadCustomerSettlements(_items[index]);
  }

  Future<void> _refreshSelectedSales() async {
    final selected = _selectedItem;
    if (selected == null) return;
    await _refreshCustomerSalesOnline(selected);
  }

  @override
  Widget build(BuildContext context) {
    final receivable = _items
        .where((e) => e.debtBalance > 0)
        .fold<num>(0, (s, e) => s + e.debtBalance);
    final payable = _items
        .where((e) => e.debtBalance < 0)
        .fold<num>(0, (s, e) => s + e.debtBalance);
    final net = receivable + payable;
    final selectedItem = _selectedItem;

    Widget debtList({
      required bool twoColumns,
      required double height,
    }) {
      if (_loading) return const _LoadingPanel();
      if (_error != null) {
        return _StatePanel(
          icon: Icons.error_outline_rounded,
          title: 'Ошибка загрузки',
          message: _error!,
          actionLabel: 'Повторить',
          onAction: _loadDebts,
        );
      }
      if (_items.isEmpty) {
        return _StatePanel(
          icon: Icons.check_circle_outline_rounded,
          title: 'Долгов нет',
          message: 'Покупатели с долгом или авансом не найдены.',
          actionLabel: 'Обновить',
          onAction: _loadDebts,
        );
      }
      return SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Контрагенты',
              subtitle: '${_items.length} записей',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ScrollConfiguration(
                behavior: AppScrollBehavior(),
                child: Scrollbar(
                  controller: _customersScrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: GridView.builder(
                    controller: _customersScrollController,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.only(right: 12, bottom: 4),
                    itemCount: _items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: twoColumns ? 2 : 1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 88,
                    ),
                    itemBuilder: (context, index) {
                      return _DebtCard(
                        item: _items[index],
                        selected: _selectedIndex == index,
                        onTap: () => _selectCustomer(index),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              receivable: receivable,
              payable: payable,
              net: net,
              onBack: () => context.go('/pos'),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final panelHeight =
                      (constraints.maxHeight - 192).clamp(420.0, 620.0);
                  return RefreshIndicator(
                    onRefresh: _loadDebts,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 16,
                        18,
                        wide ? 28 : 16,
                        28,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Toolbar(onRefresh: _loadDebts),
                              const SizedBox(height: 12),
                              _SummaryBand(
                                receivable: receivable,
                                payable: payable,
                                net: net,
                              ),
                              const SizedBox(height: 12),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: debtList(
                                        twoColumns: false,
                                        height: panelHeight,
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    SizedBox(
                                      width: 400,
                                      child: selectedItem == null
                                          ? const _NoDebtSelectionPanel()
                                          : _DebtActionPanel(
                                              item: selectedItem,
                                              sales: _customerSales,
                                              settlements: _customerSettlements,
                                              salesLoading: _salesLoading,
                                              settlementsLoading:
                                                  _settlementsLoading,
                                              salesError: _salesError,
                                              settlementsError:
                                                  _settlementsError,
                                              settling: _settling,
                                              onSettle: _settleSelectedDebt,
                                              onAddDebt: _openDebtSale,
                                              onRefreshSales:
                                                  _refreshSelectedSales,
                                              onRefreshSettlements: () =>
                                                  _loadCustomerSettlements(
                                                selectedItem,
                                              ),
                                              scrollController:
                                                  _salesScrollController,
                                              height: panelHeight,
                                            ),
                                    ),
                                  ],
                                )
                              else ...[
                                if (selectedItem != null) ...[
                                  _DebtActionPanel(
                                    item: selectedItem,
                                    sales: _customerSales,
                                    settlements: _customerSettlements,
                                    salesLoading: _salesLoading,
                                    settlementsLoading: _settlementsLoading,
                                    salesError: _salesError,
                                    settlementsError: _settlementsError,
                                    settling: _settling,
                                    onSettle: _settleSelectedDebt,
                                    onAddDebt: _openDebtSale,
                                    onRefreshSales: _refreshSelectedSales,
                                    onRefreshSettlements: () =>
                                        _loadCustomerSettlements(selectedItem),
                                    scrollController: _salesScrollController,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                debtList(
                                  twoColumns: constraints.maxWidth >= 720,
                                  height: 420,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: const Color(0xFF6B7280)),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1D4ED8),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoDebtSelectionPanel extends StatelessWidget {
  const _NoDebtSelectionPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.4),
      ),
      child: Text(
        'Выберите контрагента',
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF111827),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.receivable,
    required this.payable,
    required this.net,
    required this.onBack,
  });

  final num receivable;
  final num payable;
  final num net;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF2F343B),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 42,
                child: IconButton(
                  tooltip: 'Назад',
                  onPressed: onBack,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Долги',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatMoney(receivable)} к получению  /  ${_formatMoney(payable)} аванс',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              _NetBadge(amount: net),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF6B7280)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Покупатели с долгом',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              'Обновить',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({
    required this.receivable,
    required this.payable,
    required this.net,
  });

  final num receivable;
  final num payable;
  final num net;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Нам должны',
            value: _formatMoney(receivable),
            color: const Color(0xFF16A34A),
            icon: Icons.payments_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Аванс',
            value: _formatMoney(payable),
            color: const Color(0xFFDC2626),
            icon: Icons.request_quote_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Баланс',
            value: _formatMoney(net),
            color: net >= 0 ? const Color(0xFF0F766E) : const Color(0xFFB91C1C),
            icon: Icons.account_balance_wallet_rounded,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtActionPanel extends StatelessWidget {
  const _DebtActionPanel({
    required this.item,
    required this.sales,
    required this.settlements,
    required this.salesLoading,
    required this.settlementsLoading,
    required this.salesError,
    required this.settlementsError,
    required this.settling,
    required this.onSettle,
    required this.onAddDebt,
    required this.onRefreshSales,
    required this.onRefreshSettlements,
    required this.scrollController,
    this.height,
  });

  final CustomerDto item;
  final List<SaleModel> sales;
  final List<CustomerSettlementHistoryDto> settlements;
  final bool salesLoading;
  final bool settlementsLoading;
  final String? salesError;
  final String? settlementsError;
  final bool settling;
  final VoidCallback onSettle;
  final VoidCallback onAddDebt;
  final VoidCallback onRefreshSales;
  final VoidCallback onRefreshSettlements;
  final ScrollController scrollController;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final positive = item.debtBalance > 0;
    final color = positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusText = switch (item.debtState) {
      'advance' => 'Аванс покупателя',
      'settled' => 'Расчет закрыт',
      _ => 'Покупатель должен',
    };

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.person_rounded, color: color, size: 30),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                    height: 1.08,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _formatMoney(item.debtBalance),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          _DetailLine(icon: Icons.phone_rounded, text: item.phone),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: positive && !settling ? onSettle : null,
                    icon: settling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payments_rounded, size: 20),
                    label: Text(
                      positive ? 'Погасить' : 'Недоступно',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                      disabledForegroundColor: const Color(0xFF6B7280),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: onAddDebt,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      'Добавить',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB7791F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Продажи с остатком',
            subtitle: '${sales.length}',
          ),
          const SizedBox(height: 8),
          if (height != null)
            Expanded(child: _buildActivityList())
          else
            SizedBox(height: 360, child: _buildActivityList()),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    return ScrollConfiguration(
      behavior: AppScrollBehavior(),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        interactive: true,
        child: ListView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(right: 12, bottom: 2),
          children: [
            if (salesLoading)
              const SizedBox(
                height: 82,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (salesError != null)
              _MiniState(
                icon: Icons.error_outline_rounded,
                text: salesError!,
                actionLabel: 'Повторить',
                onAction: onRefreshSales,
              )
            else if (sales.isEmpty)
              const _MiniState(
                icon: Icons.receipt_long_rounded,
                text: 'Неоплаченных продаж не найдено',
              )
            else
              for (var index = 0; index < sales.length; index++) ...[
                _DebtSaleRow(sale: sales[index]),
                if (index != sales.length - 1) const SizedBox(height: 8),
              ],
            const SizedBox(height: 18),
            _SectionHeader(
              title: 'История погашений',
              subtitle: '${settlements.length}',
            ),
            const SizedBox(height: 8),
            if (settlementsLoading)
              const SizedBox(
                height: 82,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (settlementsError != null)
              _MiniState(
                icon: Icons.error_outline_rounded,
                text: settlementsError!,
                actionLabel: 'Повторить',
                onAction: onRefreshSettlements,
              )
            else if (settlements.isEmpty)
              const _MiniState(
                icon: Icons.payments_outlined,
                text: 'Погашений пока не было',
              )
            else
              for (var index = 0; index < settlements.length; index++) ...[
                _DebtSettlementRow(settlement: settlements[index]),
                if (index != settlements.length - 1) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _MiniState extends StatelessWidget {
  const _MiniState({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DebtSaleRow extends StatelessWidget {
  const _DebtSaleRow({required this.sale});

  final SaleModel sale;

  @override
  Widget build(BuildContext context) {
    final number = sale.number.trim().isEmpty ? sale.localId : sale.number;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFFB7791F),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number.isEmpty ? 'Чек без номера' : 'Чек $number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(sale.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(sale.documentUnpaidAmount),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatMoney(sale.totalAmount),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtSettlementRow extends StatelessWidget {
  const _DebtSettlementRow({required this.settlement});

  final CustomerSettlementHistoryDto settlement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: Color(0xFF15803D),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Погашение долга',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF14532D),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(settlement.date),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '−${_formatMoney(settlement.amount.abs())}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF15803D),
                ),
              ),
              if (settlement.remainingDebt != null) ...[
                const SizedBox(height: 3),
                Text(
                  'Остаток: ${_formatMoney(settlement.remainingDebt!)}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text.isEmpty ? '-' : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF374151),
            ),
          ),
        ),
      ],
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CustomerDto item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final positive = item.debtBalance > 0;
    final color = positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final softColor =
        positive ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final stateLabel = switch (item.debtState) {
      'advance' => 'Аванс',
      'settled' => 'Закрыт',
      _ => 'Долг',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            color: selected ? softColor : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 36,
                decoration: BoxDecoration(
                  color: softColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    positive ? '+' : '-',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _formatMoney(item.debtBalance),
                          maxLines: 1,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: color,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _SmallPill(text: stateLabel),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF4B5563),
        ),
      ),
    );
  }
}

class _NetBadge extends StatelessWidget {
  const _NetBadge({required this.amount});

  final num amount;

  @override
  Widget build(BuildContext context) {
    final positive = amount >= 0;
    final color = positive ? const Color(0xFF33CC99) : const Color(0xFFFF6B6B);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        _formatMoney(amount),
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

Future<num?> _showDebtAmountDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required Color accentColor,
  num? maxAmount,
}) {
  final controller = TextEditingController();

  void setControllerText(String value) {
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
  }

  num parseAmount() {
    final raw = controller.text.replaceAll(' ', '').replaceAll(',', '.');
    return num.tryParse(raw) ?? 0;
  }

  return showDialog<num>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final amount = parseAmount();
          final exceedsLimit = maxAmount != null && amount > maxAmount;
          final valid = amount > 0 && !exceedsLimit;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 26,
                      offset: Offset(0, 18),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      if (maxAmount != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Текущий долг: ${_formatMoney(maxAmount)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Введите сумму',
                          errorText: exceedsLimit
                              ? 'Сумма больше текущего долга'
                              : null,
                          hintStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF9CA3AF),
                          ),
                          suffixText: 'тг',
                          suffixStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF6B7280),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: accentColor, width: 1.6),
                          ),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AmountKeypad(
                        text: controller.text,
                        showQuickRows: false,
                        onChanged: (value) {
                          setControllerText(value);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(
                                  'Закрыть',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: valid
                                    ? () => Navigator.of(context).pop(amount)
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFFE5E7EB),
                                ),
                                child: Text(
                                  actionLabel,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

Future<void> _showSettlementSuccessDialog(
  BuildContext context, {
  required String customerName,
  required num paidAmount,
  required num remainingDebt,
}) {
  final settled = remainingDebt <= 0;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 28,
                  offset: Offset(0, 18),
                  color: Color(0x33000000),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF16A34A),
                          size: 34,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Долг погашен',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF111827),
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettlementResultRow(
                    label: 'Оплачено',
                    value: _formatMoney(paidAmount),
                    color: const Color(0xFF16A34A),
                  ),
                  const SizedBox(height: 10),
                  _SettlementResultRow(
                    label: settled ? 'Остаток закрыт' : 'Осталось',
                    value: settled ? '0тг' : _formatMoney(remainingDebt),
                    color: settled
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFB7791F),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF111827),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Готово',
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
  );
}

class _SettlementResultRow extends StatelessWidget {
  const _SettlementResultRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMoney(num value) {
  final sign = value > 0
      ? '+'
      : value < 0
          ? '-'
          : '';
  final rounded = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    final fromEnd = rounded.length - i;
    buffer.write(rounded[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(' ');
  }
  return '$sign${buffer.toString()}тг';
}

String _formatDate(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

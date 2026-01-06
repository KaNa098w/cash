// lib/features/pos/presentation/widgets/sales_history_page.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/sale_remote_datesource.dart';
import 'package:provider/provider.dart';

import 'package:pos_desktop_clean/core/models/sale_model.dart';
import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/sales_history/state/sales_cubit.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/sales_history/state/sales_state.dart';

import '../../widgets/search_bar.dart' as sb;

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  int? _expandedIndex;
  final ScrollController _scrollController = ScrollController();

  late final SalesHistoryCubit _cubit;

  @override
  void initState() {
    super.initState();

    final remote = GetIt.I<SaleRemoteDataSource>();
    _cubit = SalesHistoryCubit(remote);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthTokenProvider>();
      final key = auth.posKey?.trim() ?? '';

      if (key.isEmpty) {
        _cubit.showError('POS key пустой. Пройдите provisioning.');
        return;
      }

      _cubit.loadFirst(key: key);
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 240) {
        final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
        if (key.isNotEmpty) _cubit.loadMore(key: key);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<SalesHistoryCubit, SalesHistoryState>(
        builder: (context, state) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 340.0),
                        child: sb.SearchBar(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () {
                          final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
                          if (key.isNotEmpty) _cubit.loadFirst(key: key);
                        },
                        child: const Text('Обновить'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: const [
                    SizedBox(width: 100, child: Text('№ чека', style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 170, child: Text('Время', style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 110, child: Text('Статус', style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 120, child: Text('Кассир', style: TextStyle(fontWeight: FontWeight.w600))),
                    Spacer(),
                    SizedBox(
                      width: 140,
                      child: Text('Сумма', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: state.loading
                    ? const Center(child: CircularProgressIndicator())
                    : state.error != null
                        ? _ErrorBlock(
                            message: state.error!,
                            onRetry: () {
                              final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
                              if (key.isNotEmpty) _cubit.loadFirst(key: key);
                            },
                          )
                        : ScrollConfiguration(
                            behavior: AppScrollBehavior(),
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              trackVisibility: true,
                              interactive: true,
                              thickness: 10,
                              radius: const Radius.circular(12),
                              child: ListView.separated(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: state.sales.length + (state.loadingMore ? 1 : 0),
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, index) {
                                  if (index >= state.sales.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }

                                  final sale = state.sales[index];
                                  final expanded = _expandedIndex == index;

                                  return Column(
                                    children: [
                                      GestureDetector(
                                        onTap: () => setState(() {
                                          _expandedIndex = expanded ? null : index;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(24),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 80,
                                                child: Text(
                                                  _saleNumber(sale),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 180,
                                                child: Text('${_fmtDate(sale.date)}   ${_fmtTime(sale.date)}'),
                                              ),
                                              const SizedBox(
                                                width: 120,
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: _StatusChip(label: 'Закрыт'),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 120,
                                                child: Text(
                                                  _cashierLabel(sale),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const Spacer(),
                                              SizedBox(
                                                width: 140,
                                                child: Text(
                                                  _moneyInt(sale.totalAmount),
                                                  textAlign: TextAlign.right,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              const Icon(Icons.more_horiz, size: 20, color: Colors.black54),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (expanded) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(24),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade100,
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                                                  child: Column(
                                                    children: sale.items
                                                        .map(
                                                          (item) => Padding(
                                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                                            child: Row(
                                                              children: [
                                                                Expanded(
                                                                  flex: 3,
                                                                  child: Text(
                                                                    item.productId, // позже заменим на имя из Hive
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                                SizedBox(width: 80, child: Text(_moneyInt(item.price))),
                                                                SizedBox(
                                                                  width: 60,
                                                                  child: Text('${item.quantity} шт', textAlign: TextAlign.right),
                                                                ),
                                                                SizedBox(
                                                                  width: 110,
                                                                  child: Text(_moneyInt(item.totalPrice), textAlign: TextAlign.right),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 24),
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 200,
                                                    height: 40,
                                                    child: OutlinedButton(
                                                      onPressed: () {},
                                                      child: const Text('Возврат'),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  SizedBox(
                                                    width: 200,
                                                    height: 60,
                                                    child: ElevatedButton(
                                                      onPressed: () {},
                                                      child: const Text('Распечатать чек'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ===== helpers =====

String _saleNumber(SaleModel s) {
  if (s.localId.isEmpty) return '—';
  return s.localId.length > 8 ? s.localId.substring(s.localId.length - 8) : s.localId;
}

String _cashierLabel(SaleModel s) {
  if (s.userId.isEmpty) return '—';
  return s.userId.length > 10 ? '${s.userId.substring(0, 10)}…' : s.userId;
}

String _fmtDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String _fmtTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

String _moneyInt(int value) => '$value ₸';

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF16A34A),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

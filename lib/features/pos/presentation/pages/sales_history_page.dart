// lib/features/pos/presentation/widgets/sales_history_page.dart
import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import '../widgets/search_bar.dart' as sb;

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  int? _expandedIndex;

  // Фейковые данные для примера
  final List<_Sale> _sales = List.generate(
    5,
    (i) => _Sale(
      number: '4564${i + 2}',
      date: '18 ноябрь 2025',
      time: '14:2${i}',
      cashier: 'Жарас',
      status: 'Закрыт',
      total: 10000.0,
      items: List.generate(
        6,
        (j) => _SaleItem(
          name: 'Наименование товара',
          price: 500.0,
          qty: 20,
          sum: 10000.0,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Поиск + "Покупатель"
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              // Поисковая строка, максимально как на дизайне
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: sb.SearchBar(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Заголовки таблицы
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: const [
              SizedBox(
                width: 100,
                child: Text(
                  '№ чека',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 170,
                child: Text(
                  'Время',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  'Статус',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  'Кассир',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Spacer(),
              SizedBox(
                width: 140,
                child: Text(
                  'Сумма',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: 40),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Список чеков
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _sales.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final sale = _sales[index];
              final expanded = _expandedIndex == index;

              return Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expandedIndex = expanded
                            ? null
                            : index; // сворачиваем/разворачиваем
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              sale.number,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: Text(
                              '${sale.date}   ${sale.time}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _StatusChip(label: sale.status),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              sale.cashier,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 140,
                            child: Text(
                              _money(sale.total),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 6),
                    // Детальный блок под чеком
                    Container(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Список позиций
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding:
                                  const EdgeInsets.fromLTRB(24, 16, 24, 16),
                              child: Column(
                                children: [
                                  // заголовок внутри серого блока можно не делать — на макете его нет
                                  Column(
                                    children: sale.items
                                        .map(
                                          (item) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            child: Row(
                                              children: [
                                                // Наименование
                                                const Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    'Наименование товара',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                // Цена
                                                SizedBox(
                                                  width: 80,
                                                  child: Text(
                                                    _money(item.price),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                // Кол-во
                                                SizedBox(
                                                  width: 60,
                                                  child: Text(
                                                    '${item.qty} шт',
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                // Сумма
                                                SizedBox(
                                                  width: 110,
                                                  child: Text(
                                                    _money(item.sum),
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 24),

                          // Кнопки справа
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 200,
                                height: 40,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: ThemeColors.grey, // серый
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    // TODO: логика возврата
                                  },
                                  child: const Text(
                                    'Возврат',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 200,
                                height: 60,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        ThemeColors.green1, // зелёная
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    // TODO: логика печати чека
                                  },
                                  child: const Text(
                                    'Распечатать чек',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
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
      ],
    );
  }
}

// ===== ВСПОМОГАТЕЛЬНЫЕ ТИПЫ И ВИДЖЕТЫ =====

class _Sale {
  final String number;
  final String date;
  final String time;
  final String cashier;
  final String status;
  final double total;
  final List<_SaleItem> items;

  _Sale({
    required this.number,
    required this.date,
    required this.time,
    required this.cashier,
    required this.status,
    required this.total,
    required this.items,
  });
}

class _SaleItem {
  final String name;
  final double price;
  final int qty;
  final double sum;

  _SaleItem({
    required this.name,
    required this.price,
    required this.qty,
    required this.sum,
  });
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

String _money(double value) {
  // очень простой форматтер
  return '${value.toStringAsFixed(0)} ₸';
}

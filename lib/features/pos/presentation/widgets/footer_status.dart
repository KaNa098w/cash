import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';

class FooterStatus extends StatelessWidget {
  const FooterStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8, right: 6),
      child: SizedBox(
        height: 160,
        child: Row(
          children: [
            // левая карточка (время/касса)
            Container(
              height: 160,
              width: 176,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.access_time_filled, color: Colors.white),
                      Text(
                        '19:45',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text('7 Октябрь | Вторник',
                      style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 2),
                  Text(
                    'Касса-1  \nНаименование Магазина',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // правая плашка с карточками
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD9D9D9)),
                  color: AppTheme.grey,
                  borderRadius: BorderRadius.circular(17),
                ),
                padding: const EdgeInsets.only(left: 8, top: 12, right: 8),
                child: _ProductsStrip(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductsStrip extends StatelessWidget {
  _ProductsStrip({super.key});

  // мок-данные для примера
  final _items = List.generate(
    8,
    (i) => (
      name: 'Наименование товара ... 2 строк',
      price: 315.00,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      reverse: true,
      separatorBuilder: (_, __) => const SizedBox(width: 16),
      itemBuilder: (ctx, i) {
        final it = _items[i];
        return _ProductCard(
          title: it.name,
          price: it.price,
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.price,
  });

  final String title;
  final double price;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 71, // визуально как на макете
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // квадратное превью с + в углу
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 71,
                  height: 71,
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.add, size: 20, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // название: 2 строки, троеточие
          SizedBox(
            width: 120,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B7280), // серый как на скрине
                height: 1.2,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // белая "капсула" с ценой
          Container(
            width: 71,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${price.toStringAsFixed(2)} ₸',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

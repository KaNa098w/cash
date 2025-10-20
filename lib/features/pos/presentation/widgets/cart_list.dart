import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import '../../../pos/presentation/state/pos_cubit.dart';
import '../../../../core/utils/money.dart';

class CartList extends StatelessWidget {
  const CartList({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const _Header(), // просто подписи сверху
          const SizedBox(height: 8),
          Expanded(
            child: BlocBuilder<PosCubit, PosState>(
              builder: (context, state) {
                return ListView.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, i) {
                    final it = state.items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 2),
                      color: Colors.white,
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            14), // «чуть овальные концовки»
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // превью
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppTheme.grey,
                                border:
                                    Border.all(color: const Color(0xFFE5E7EB)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(width: 20),

                            // Наименование + метки
                            Expanded(
                              child: Text(
                                it.product.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Цена
                            SizedBox(
                              width: 90,
                              child: Text(
                                money(it.product.price),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Количество
                            SizedBox(
                              width: 80,
                              child: Text(
                                it.qty.toStringAsFixed(2),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 40),

                            // Скидка
                            SizedBox(
                              width: 70,
                              child: _DiscountChip(it.discount.toStringAsFixed(0))
                            ),
                            const SizedBox(width: 16),

                            // Сумма
                            SizedBox(
                              width: 105,
                              child: Text(
                                money(it.sum),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  context.read<PosCubit>().removeAt(i),
                              tooltip: 'Удалить',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    Widget cell(String t,
            {double w = 100, TextAlign align = TextAlign.right}) =>
        SizedBox(
            width: w,
            child: Text(t,
                textAlign: align,
                style: const TextStyle(fontWeight: FontWeight.w600)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 40), // место под превью
          const Expanded(
              child: Text('Наименование',
                  style: TextStyle(fontWeight: FontWeight.w600))),
          cell('Цена', w: 90),
          const SizedBox(width: 16),
          cell('Количество', w: 120),
          const SizedBox(width: 16),
          cell('Скидка', w: 70),
          const SizedBox(width: 16),
          cell('Сумма', w: 100),
          const SizedBox(width: 60),
        ],
      ),
    );
  }
}

class _DiscountChip extends StatelessWidget {
  final String text;
  const _DiscountChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD1F2D7)),
      ),
      child: Text(
        '${text}%',
        style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF16A34A),
            fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
      ),
    );
  }
}

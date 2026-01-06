import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/sales_history/sales_history_page.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/cart_list/cart_list.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/footer_status.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/payment_panel.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/search_bar.dart' as sb;
import 'package:pos_desktop_clean/features/pos/presentation/widgets/top_bar.dart';
import '../state/pos_cubit.dart'; // ⬅️ важно не забыть импорт

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          const TopBar(),

          Expanded(
            child: BlocBuilder<PosCubit, PosState>(
              builder: (context, state) {
                // если нужен переключатель режимов — можно раскомментить
                if (state.isHistoryMode) {
                  return const SalesHistoryPage();
                }

                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: const [
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: sb.SearchBar(),
                          ),
                          SizedBox(height: 8),
                          Expanded(child: CartList()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: FooterStatus(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width: 340,
                      child: PaymentPanel(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

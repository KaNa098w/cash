// pos_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/sales_history_page.dart';

import '../widgets/top_bar.dart';
import '../widgets/search_bar.dart' as sb;
import '../widgets/cart_list.dart';
import '../widgets/payment_panel.dart';
import '../widgets/footer_status.dart';
import '../state/pos_cubit.dart';

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          const TopBar(), // всё берёт из PosCubit

          Expanded(
            child: BlocBuilder<PosCubit, PosState>(
              buildWhen: (p, n) => p.isHistoryMode != n.isHistoryMode,
              builder: (context, state) {
                if (state.isHistoryMode) {
                  return const SalesHistoryPage();
                }

                // обычный POS
                return  const Row(
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

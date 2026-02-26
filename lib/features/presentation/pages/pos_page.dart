import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/sales_history_page.dart';
import 'package:leemon_app/features/presentation/pages/products/cart_list/cart_list.dart';
import 'package:leemon_app/features/presentation/widgets/footer_status.dart';
import 'package:leemon_app/features/presentation/pages/search/search_bar.dart'
    as sb;
import 'package:leemon_app/features/presentation/widgets/top_bar.dart';

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
                if (state.isHistoryMode) {
                  return const SafeArea(
                    top: false,
                    child: SalesHistoryPage(),
                  );
                }

                return const Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: sb.SearchBar(),
                          ),
                          SizedBox(height: 8),
                          Expanded(child: CartList()),
                          FooterStatus(),
                        ],
                      ),
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

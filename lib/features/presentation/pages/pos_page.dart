import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/features/presentation/pages/products/cart_list/cart_list.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/sales_history_page.dart';
import 'package:leemon_app/features/presentation/widgets/app_update_background_check.dart';
import 'package:leemon_app/features/presentation/widgets/footer_status.dart';
import 'package:leemon_app/features/presentation/widgets/order_notification_demo.dart';
import 'package:leemon_app/features/presentation/widgets/top_bar.dart';
import 'package:leemon_app/features/presentation/pages/search/search_bar.dart'
    as sb;

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  bool _updateCheckStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(checkForAppUpdateAfterCashierLogin(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Theme(
        data: baseTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
          primaryTextTheme: GoogleFonts.interTextTheme(
            baseTheme.primaryTextTheme,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const TopBar(),
                Expanded(
                  child: BlocBuilder<PosCubit, PosState>(
                    builder: (context, state) {
                      return IndexedStack(
                        index: state.isHistoryMode ? 1 : 0,
                        children: const [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Padding(
                                      padding:
                                          EdgeInsets.fromLTRB(16, 12, 16, 0),
                                      child: sb.SearchBar(),
                                    ),
                                    SizedBox(height: 8),
                                    Expanded(child: CartList()),
                                    FooterStatus(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SafeArea(top: false, child: SalesHistoryPage()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            const Positioned.fill(child: OrderNotificationDemo()),
          ],
        ),
      ),
    );
  }
}

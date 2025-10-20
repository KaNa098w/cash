import 'package:flutter/material.dart';
import '../widgets/top_bar.dart';
import '../widgets/search_bar.dart' as sb;
import '../widgets/cart_list.dart';
import '../widgets/payment_panel.dart';
import '../widgets/footer_status.dart';

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar:  PreferredSize(
        
        
        preferredSize: Size.fromHeight(70),
        child: TopBar(),
      ),
      body: Row(
        children: [
          // Left: items + search + list
          Expanded(
            child: const Column(
              children: [
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
          // Right: payment
          SizedBox(
            width: 340,
            child: const PaymentPanel(),
          ),
        ],
      ),
      // bottomNavigationBar: const SafeArea(child: FooterStatus()),
    );
  }
}

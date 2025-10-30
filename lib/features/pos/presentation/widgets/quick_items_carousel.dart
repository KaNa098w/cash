import 'package:flutter/material.dart';

class QuickItemsCarousel extends StatelessWidget {
  const QuickItemsCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFBBF24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: List.generate(
              7,
              (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i == 6 ? 0 : 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Center(child: Icon(Icons.add)),
                    ),
                  )),
        ),
      ),
    );
  }
}

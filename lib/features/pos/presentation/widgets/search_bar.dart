import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import '../state/pos_cubit.dart';

class SearchBar extends StatefulWidget {
  const SearchBar({super.key});

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PosCubit>();
    return Row(
      children: [
        // Search bar with white background, no border, oval shape
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[200], // Серый фон снаружи
              borderRadius: BorderRadius.circular(28),
            ),
            padding:
                const EdgeInsets.all(2), // Отступ для внутреннего контейнера
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
     
                border: Border.all(
                  color: AppTheme.grey, // Обводка
                  width: 15,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: TextField(
                controller: controller,
                onSubmitted: cubit.search,
                decoration: const InputDecoration(
                  hintText: 'Введите наименование товара или код товара',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),

            border: Border.all(
              color: AppTheme.grey, // Обводка
              width: 15,
            ),
          ),
          child: ElevatedButton(onPressed: (){ }, child: Text('Покупатель') , style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            elevation: 0,
          ),),
        ),
      ],
    );
  }
}

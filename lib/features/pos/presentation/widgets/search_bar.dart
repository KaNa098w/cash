import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';

import 'package:pos_desktop_clean/core/utils/app_theme.dart';
import '../state/pos_cubit.dart';

class SearchBar extends StatefulWidget {
  const SearchBar({super.key});

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // всегда активное поле под сканер
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
      _ensureValidSelection();
    });
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _ensureValidSelection();
      } else {
        // если кто-то попытался «украсть» фокус — вернём
        // (даёт эффект "всегда активное" для POS)
        Future.microtask(() => _focusNode.requestFocus());
      }
    });
  }

  void _doSearch() {
    context.read<PosCubit>().search(_controller.text.trim());
    // по желанию: закрыть экранную клавиатуру после поиска
    // OnscreenKeyboard.of(context).close();
  }

  void _openKeyboard() {
    // поле уже в фокусе — просто открыть экранную
    // OnscreenKeyboard.of(context).open(); // ручной вызов
  }

  void _ensureValidSelection() {
    final sel = _controller.selection;
    if (sel.start < 0 || sel.end < 0) {
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(28),
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ThemeColors.grey, width: 15),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                // ВАЖНО: клавиатура не открывается на фокусе
                // enableOnscreenKeyboard: false, // <- ключевая строка
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true, // поле активно сразу (для сканера)
                onSubmitted: (_) => _doSearch(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Введите наименование товара или код товара',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  suffixIcon: SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Экранная клавиатура',
                          icon: const Icon(Icons.keyboard),
                          onPressed: _openKeyboard, // теперь открывает вручную
                        ),
                        IconButton(
                          tooltip: 'Найти',
                          icon: const Icon(Icons.search),
                          onPressed: _doSearch,
                        ),
                      ],
                    ),
                  ),
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
            border: Border.all(color: ThemeColors.grey, width: 15),
          ),
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              elevation: 0,
            ),
            child: const Text('Покупатель'),
          ),
        ),
      ],
    );
  }
}

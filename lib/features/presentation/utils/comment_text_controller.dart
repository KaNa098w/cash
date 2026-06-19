import 'package:flutter/widgets.dart';

void capitalizeFirstLetterInController(TextEditingController controller) {
  final text = controller.text;
  if (text.isEmpty) return;

  var offset = 0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final upper = char.toUpperCase();
    final lower = char.toLowerCase();
    final isLetter = upper != lower;

    if (isLetter) {
      if (char == upper) return;

      final nextText = text.replaceRange(offset, offset + char.length, upper);
      final selection = controller.selection;
      controller.value = controller.value.copyWith(
        text: nextText,
        selection: selection.isValid
            ? selection.copyWith(
                baseOffset: selection.baseOffset.clamp(0, nextText.length),
                extentOffset: selection.extentOffset.clamp(0, nextText.length),
              )
            : TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      );
      return;
    }

    offset += char.length;
  }
}

import 'package:flutter/foundation.dart';

final ValueNotifier<int> searchKeyboardCloseSignal = ValueNotifier<int>(0);
final ValueNotifier<int> searchResetAndFocusSignal = ValueNotifier<int>(0);

void requestSearchKeyboardClose() {
  searchKeyboardCloseSignal.value++;
}

void requestSearchResetAndFocus() {
  searchResetAndFocusSignal.value++;
}

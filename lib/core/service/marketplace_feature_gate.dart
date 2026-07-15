import 'package:flutter/foundation.dart';

class MarketplaceFeatureGate extends ChangeNotifier {
  MarketplaceFeatureGate._();

  static final MarketplaceFeatureGate instance = MarketplaceFeatureGate._();

  static const int requiredTaps = 10;

  bool _enabled = false;
  int _tapCount = 0;

  bool get enabled => _enabled;

  bool registerTap() {
    _tapCount++;
    if (_tapCount < requiredTaps) return false;

    _enabled = !_enabled;
    _tapCount = 0;
    notifyListeners();
    return true;
  }
}

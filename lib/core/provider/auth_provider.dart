import 'dart:convert' as dc show jsonDecode, jsonEncode;
import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:leemon_app/core/models/pos_pricing_plan_status.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';

class AuthTokenProvider extends ChangeNotifier {
  static const _kPosKey = 'posKey';
  static const _kDeviceId = 'deviceId';

  static const _kPosName = 'posName';
  static const _kPosNumber = 'posNumber';
  static const _kPosId = 'posId';
  static const _kPosIsTest = 'posIsTest';
  static const _kStoreId = 'storeId';
  static const _kStoreName = 'storeName';
  static const _kAllowCustomSalePrices = 'allowCustomSalePrices';
  static const _kAllowBelowCostSalePrices = 'allowBelowCostSalePrices';
  static const _kAllowRefundsWithoutSale = 'allowRefundsWithoutSale';
  static const _kFiscalizationEnabled = 'fiscalizationEnabled';
  static const _kFiscalizationPollSeconds = 'fiscalizationPollSeconds';
  static const _kPrintLocalReceiptImmediately = 'printLocalReceiptImmediately';
  static const _kOrganizationId = 'organizationId';
  static const _kAccountId = 'accountId';

  static const _kUsers = 'posUsers';

  static const _kPinSalt = 'pinSalt';

  static const _kShiftId = 'shiftId';
  static const _kShiftUserId = 'shiftUserId';
  static const _kReceiptPaperMm = 'receiptPaperMm';
  static const _kReceiptPrinterName = 'receiptPrinterName';
  static const _kInvoicePrinterName = 'invoicePrinterName';
  static const _kPricingPlanStatus = 'pricingPlanStatus';

  // ✅ активный кассир
  static const _kActiveUserId = 'activeUserId';
  static const _kActiveUserName = 'activeUserName';

  String? _posKey;
  String? get posKey => _posKey;
  bool get hasPosKey => _posKey != null && _posKey!.trim().isNotEmpty;

  String? _deviceId;
  String? get deviceId => _deviceId;

  String? _posName;
  String? get posName => _posName;

  String? _posNumber;
  String? get posNumber => _posNumber;

  String? _posId;
  String? get posId => _posId;

  bool _posIsTest = false;
  bool get posIsTest => _posIsTest;

  String? _storeId;
  String? get storeId => _storeId;

  String? _storeName;
  String? get storeName => _storeName;

  bool _allowCustomSalePrices = false;
  bool get allowCustomSalePrices => _allowCustomSalePrices;

  bool _allowBelowCostSalePrices = false;
  bool get allowBelowCostSalePrices => _allowBelowCostSalePrices;

  bool _allowRefundsWithoutSale = false;
  bool get allowRefundsWithoutSale => _allowRefundsWithoutSale;
  bool _fiscalizationEnabled = false;
  bool get fiscalizationEnabled => _fiscalizationEnabled;
  int _fiscalizationPollSeconds = 2;
  int get fiscalizationPollSeconds => _fiscalizationPollSeconds;
  bool _printLocalReceiptImmediately = true;
  bool get printLocalReceiptImmediately => _printLocalReceiptImmediately;

  String? _organizationId;
  String? get organizationId => _organizationId;

  String? _accountId;
  String? get accountId => _accountId;

  String? _pinSalt;
  String get pinSalt => _pinSalt ?? '';

  String? _shiftId;
  String? get shiftId => _shiftId;
  bool get hasShiftId => _shiftId != null && _shiftId!.trim().isNotEmpty;

  String? _shiftUserId;
  String? get shiftUserId => _shiftUserId;
  bool get hasShiftUserId =>
      _shiftUserId != null && _shiftUserId!.trim().isNotEmpty;

  int _receiptPaperMm = 57;
  int get receiptPaperMm => _receiptPaperMm == 80 ? 80 : 57;
  bool get isReceipt57mm => receiptPaperMm == 57;

  String? _receiptPrinterName;
  String? get receiptPrinterName => _receiptPrinterName;

  String? _invoicePrinterName;
  String? get invoicePrinterName => _invoicePrinterName;

  String? _activeUserId;
  String? get activeUserId => _activeUserId;
  bool get hasActiveUserId =>
      _activeUserId != null && _activeUserId!.trim().isNotEmpty;

  List<PosUser> _users = [];
  List<PosUser> get users => List.unmodifiable(_users);
  String? _activeUserName;
  String? get activeUserName => _activeUserName;
  PosPricingPlanStatus? _pricingPlanStatus;
  PosPricingPlanStatus? get pricingPlanStatus => _pricingPlanStatus;
  bool get shouldShowTariffExpiryNotice =>
      _pricingPlanStatus?.shouldShowExpiryNotice() ?? false;
  int? get tariffDaysUntilExpiry => _pricingPlanStatus?.daysUntilExpiry();

  bool get isProvisioned =>
      hasPosKey &&
      (_storeId != null && _storeId!.isNotEmpty) &&
      (_organizationId != null && _organizationId!.isNotEmpty) &&
      (_posId != null && _posId!.isNotEmpty) &&
      (_posName != null && _posName!.isNotEmpty) &&
      (_accountId != null && _accountId!.isNotEmpty) &&
      _users.isNotEmpty;

  PosProvisionResponse? get cachedProvision {
    if (!isProvisioned) return null;

    return PosProvisionResponse(
      id: _posId!,
      name: _posName!,
      number: _posNumber ?? '',
      key: _posKey ?? '',
      accountId: _accountId!,
      storeId: _storeId!,
      storeName: _storeName ?? '',
      isTest: _posIsTest,
      allowCustomSalePrices: _allowCustomSalePrices,
      allowBelowCostSalePrices: _allowBelowCostSalePrices,
      allowRefundsWithoutSale: _allowRefundsWithoutSale,
      fiscalization: PosFiscalizationConfig(
        enabled: _fiscalizationEnabled,
        pollIntervalSeconds: _fiscalizationPollSeconds,
        printLocalReceiptImmediately: _printLocalReceiptImmediately,
      ),
      organizationId: _organizationId!,
      users: _users,
      createdAt: null,
      updatedAt: null,
    );
  }

  PosProvisionResponse provisionForOpenShift(PosProvisionResponse provision) {
    if (!hasShiftId) return provision;

    final userId = (_shiftUserId?.trim().isNotEmpty == true)
        ? _shiftUserId!.trim()
        : (_activeUserId ?? '').trim();
    if (userId.isEmpty) return provision;

    final users = provision.users.where((user) => user.id == userId).toList();
    if (users.isEmpty) return provision;

    return PosProvisionResponse(
      id: provision.id,
      name: provision.name,
      number: provision.number,
      key: provision.key,
      accountId: provision.accountId,
      storeId: provision.storeId,
      storeName: provision.storeName,
      isTest: provision.isTest,
      allowCustomSalePrices: provision.allowCustomSalePrices,
      allowBelowCostSalePrices: provision.allowBelowCostSalePrices,
      allowRefundsWithoutSale: provision.allowRefundsWithoutSale,
      fiscalization: provision.fiscalization,
      organizationId: provision.organizationId,
      users: users,
      createdAt: provision.createdAt,
      updatedAt: provision.updatedAt,
    );
  }

  /// sha256(pin|salt)
  String hashPin(String pin) {
    final bytes = utf8.encode('${pin.trim()}|$pinSalt');
    return sha256.convert(bytes).toString();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    _posKey = prefs.getString(_kPosKey);
    _deviceId = prefs.getString(_kDeviceId);

    _posName = prefs.getString(_kPosName);
    _posNumber = prefs.getString(_kPosNumber);
    _posId = prefs.getString(_kPosId);
    _posIsTest = prefs.getBool(_kPosIsTest) ?? false;
    _storeId = prefs.getString(_kStoreId);
    _storeName = prefs.getString(_kStoreName);
    _allowCustomSalePrices = prefs.getBool(_kAllowCustomSalePrices) ?? false;
    _allowBelowCostSalePrices =
        prefs.getBool(_kAllowBelowCostSalePrices) ?? false;
    _allowRefundsWithoutSale =
        prefs.getBool(_kAllowRefundsWithoutSale) ?? false;
    _fiscalizationEnabled = prefs.getBool(_kFiscalizationEnabled) ?? false;
    _fiscalizationPollSeconds =
        (prefs.getInt(_kFiscalizationPollSeconds) ?? 2).clamp(1, 30);
    _printLocalReceiptImmediately =
        prefs.getBool(_kPrintLocalReceiptImmediately) ?? true;
    _organizationId = prefs.getString(_kOrganizationId);
    _accountId = prefs.getString(_kAccountId);

    _shiftId = prefs.getString(_kShiftId);
    _shiftUserId = prefs.getString(_kShiftUserId);
    _activeUserId = prefs.getString(_kActiveUserId);
    _activeUserName = prefs.getString(_kActiveUserName);
    if ((_shiftUserId ?? '').trim().isEmpty &&
        (_shiftId ?? '').trim().isNotEmpty &&
        (_activeUserId ?? '').trim().isNotEmpty) {
      _shiftUserId = _activeUserId;
      await prefs.setString(_kShiftUserId, _shiftUserId!);
    }
    final savedReceiptPaperMm = prefs.getInt(_kReceiptPaperMm);
    _receiptPaperMm = savedReceiptPaperMm == 80 ? 80 : 57;
    _receiptPrinterName = prefs.getString(_kReceiptPrinterName);
    _invoicePrinterName = prefs.getString(_kInvoicePrinterName);
    final pricingPlanStatusStr = prefs.getString(_kPricingPlanStatus);
    if (pricingPlanStatusStr != null && pricingPlanStatusStr.isNotEmpty) {
      try {
        final decoded = dc.jsonDecode(pricingPlanStatusStr);
        if (decoded is Map<String, dynamic>) {
          _pricingPlanStatus = PosPricingPlanStatus.fromDataJson(decoded);
        }
      } catch (_) {
        _pricingPlanStatus = null;
      }
    }

    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceId, _deviceId!);
    }

    _pinSalt = prefs.getString(_kPinSalt);
    if (_pinSalt == null || _pinSalt!.isEmpty) {
      _pinSalt = const Uuid().v4();
      await prefs.setString(_kPinSalt, _pinSalt!);
    }

    final usersStr = prefs.getString(_kUsers);
    if (usersStr != null && usersStr.isNotEmpty) {
      try {
        final decoded = dc.jsonDecode(usersStr);
        if (decoded is List) {
          _users = decoded
              .whereType<Map<String, dynamic>>()
              .map(PosUser.fromJson)
              .toList();
        }
      } catch (_) {
        _users = [];
      }
    }

    notifyListeners();
  }

  Future<void> setPosKey(String key) async {
    _posKey = key.trim();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPosKey, _posKey!);
  }

  Future<void> clearPosKey() async {
    _posKey = null;
    await clearProvisioned(keepDeviceId: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPosKey);

    notifyListeners();
  }

  Future<void> setProvisioned(PosProvisionResponse resp) async {
    _posKey = resp.key;

    _posName = resp.name;
    _posNumber = resp.number;
    _posId = resp.id;
    _posIsTest = resp.isTest;
    _storeId = resp.storeId;
    _storeName = resp.storeName;
    _allowCustomSalePrices = resp.allowCustomSalePrices;
    _allowBelowCostSalePrices = resp.allowBelowCostSalePrices;
    _allowRefundsWithoutSale = resp.allowRefundsWithoutSale;
    _fiscalizationEnabled = resp.fiscalization.enabled;
    _fiscalizationPollSeconds = resp.fiscalization.pollIntervalSeconds;
    _printLocalReceiptImmediately =
        resp.fiscalization.printLocalReceiptImmediately;
    _organizationId = resp.organizationId;
    _accountId = resp.accountId;

    final uniqueUsers = <String, PosUser>{};
    for (final user in resp.users) {
      uniqueUsers[user.id] = user;
    }

    _users = uniqueUsers.values.map((u) {
      final apiPin = u.pinCode.trim();
      final h = apiPin.isEmpty ? null : hashPin(apiPin);
      return u.copyWith(pinHash: h, pinCode: '');
    }).toList();

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPosKey, _posKey ?? '');

    await prefs.setString(_kPosName, _posName ?? '');
    await prefs.setString(_kPosNumber, _posNumber ?? '');
    await prefs.setString(_kPosId, _posId ?? '');
    await prefs.setBool(_kPosIsTest, _posIsTest);
    await prefs.setString(_kStoreId, _storeId ?? '');
    await prefs.setString(_kStoreName, _storeName ?? '');
    await prefs.setBool(_kAllowCustomSalePrices, _allowCustomSalePrices);
    await prefs.setBool(
      _kAllowBelowCostSalePrices,
      _allowBelowCostSalePrices,
    );
    await prefs.setBool(_kAllowRefundsWithoutSale, _allowRefundsWithoutSale);
    await prefs.setBool(_kFiscalizationEnabled, _fiscalizationEnabled);
    await prefs.setInt(
      _kFiscalizationPollSeconds,
      _fiscalizationPollSeconds,
    );
    await prefs.setBool(
      _kPrintLocalReceiptImmediately,
      _printLocalReceiptImmediately,
    );
    await prefs.setString(_kOrganizationId, _organizationId ?? '');
    await prefs.setString(_kAccountId, _accountId ?? '');

    final jsonUsers = dc.jsonEncode(_users.map((u) => u.toJson()).toList());
    await prefs.setString(_kUsers, jsonUsers);
  }

  Future<void> clearProvisioned({bool keepDeviceId = true}) async {
    _posName = null;
    _posNumber = null;
    _posId = null;
    _posIsTest = false;
    _storeId = null;
    _storeName = null;
    _allowCustomSalePrices = false;
    _allowBelowCostSalePrices = false;
    _allowRefundsWithoutSale = false;
    _fiscalizationEnabled = false;
    _fiscalizationPollSeconds = 2;
    _printLocalReceiptImmediately = true;
    _organizationId = null;
    _accountId = null;
    _users = [];

    _shiftId = null;
    _shiftUserId = null;
    _activeUserId = null;
    _activeUserName = null;
    _pricingPlanStatus = null;

    if (!keepDeviceId) _deviceId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPosName);
    await prefs.remove(_kPosNumber);
    await prefs.remove(_kPosId);
    await prefs.remove(_kPosIsTest);
    await prefs.remove(_kStoreId);
    await prefs.remove(_kStoreName);
    await prefs.remove(_kAllowCustomSalePrices);
    await prefs.remove(_kAllowBelowCostSalePrices);
    await prefs.remove(_kAllowRefundsWithoutSale);
    await prefs.remove(_kFiscalizationEnabled);
    await prefs.remove(_kFiscalizationPollSeconds);
    await prefs.remove(_kPrintLocalReceiptImmediately);
    await prefs.remove(_kOrganizationId);
    await prefs.remove(_kAccountId);
    await prefs.remove(_kUsers);

    await prefs.remove(_kShiftId);
    await prefs.remove(_kShiftUserId);
    await prefs.remove(_kActiveUserId);
    await prefs.remove(_kActiveUserName);
    await prefs.remove(_kPricingPlanStatus);

    if (!keepDeviceId) {
      await prefs.remove(_kDeviceId);
    }

    notifyListeners();
  }

  Future<void> setReceiptPaperMm(int mm) async {
    final next = mm == 57 ? 57 : 80;
    _receiptPaperMm = next;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kReceiptPaperMm, next);
  }

  Future<void> setReceiptPrinterName(String? name) async {
    _receiptPrinterName = (name?.trim().isEmpty ?? true) ? null : name!.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_receiptPrinterName == null) {
      await prefs.remove(_kReceiptPrinterName);
    } else {
      await prefs.setString(_kReceiptPrinterName, _receiptPrinterName!);
    }
  }

  Future<void> setInvoicePrinterName(String? name) async {
    _invoicePrinterName = (name?.trim().isEmpty ?? true) ? null : name!.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_invoicePrinterName == null) {
      await prefs.remove(_kInvoicePrinterName);
    } else {
      await prefs.setString(_kInvoicePrinterName, _invoicePrinterName!);
    }
  }

  Future<void> setShiftId(String id) async {
    final v = id.trim();
    if (v.isEmpty) return;

    _shiftId = v;
    debugPrint('[AuthTokenProvider] saving shiftId=$v');
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShiftId, v);
    debugPrint(
        '[AuthTokenProvider] shiftId saved to SharedPreferences key=$_kShiftId');
  }

  Future<void> clearShiftId() async {
    _shiftId = null;
    _shiftUserId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kShiftId);
    await prefs.remove(_kShiftUserId);

    notifyListeners();
  }

  Future<void> setShiftUserId(String userId) async {
    final v = userId.trim();
    if (v.isEmpty) return;

    _shiftUserId = v;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShiftUserId, v);
  }

  Future<void> setActiveUserId(String userId) async {
    final v = userId.trim();
    if (v.isEmpty) return;

    _activeUserId = v;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveUserId, v);
  }

  Future<void> setActiveUserName(String userName) async {
    final v = userName.trim();
    if (v.isEmpty) return;

    _activeUserName = v;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveUserName, v);
  }

  /// Updates the active cashier with a single preferences flush and a single
  /// UI notification. Login previously performed both writes sequentially.
  Future<void> setActiveUser({
    required String id,
    required String name,
  }) async {
    final cleanId = id.trim();
    final cleanName = name.trim();
    if (cleanId.isEmpty) return;

    _activeUserId = cleanId;
    if (cleanName.isNotEmpty) _activeUserName = cleanName;

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_kActiveUserId, cleanId),
      if (cleanName.isNotEmpty) prefs.setString(_kActiveUserName, cleanName),
    ]);
    notifyListeners();
  }

  Future<void> setPricingPlanStatus(PosPricingPlanStatus status) async {
    _pricingPlanStatus = status;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPricingPlanStatus, dc.jsonEncode(status.toJson()));
  }

  Future<void> clearActiveUserId() async {
    _activeUserId = null;
    _activeUserName = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActiveUserId);
    await prefs.remove(_kActiveUserName);

    notifyListeners();
  }
}

import 'dart:convert' as dc show jsonDecode, jsonEncode;
import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:leemon_app/core/models/pos_provision_response.dart';

class AuthTokenProvider extends ChangeNotifier {
  static const _kPosKey = 'posKey';
  static const _kDeviceId = 'deviceId';

  static const _kPosName = 'posName';
  static const _kPosNumber = 'posNumber';
  static const _kPosId = 'posId';
  static const _kStoreId = 'storeId';
  static const _kStoreName = 'storeName';
  static const _kOrganizationId = 'organizationId';
  static const _kAccountId = 'accountId';

  static const _kUsers = 'posUsers';

  static const _kPinSalt = 'pinSalt';

  static const _kShiftId = 'shiftId';
  static const _kReceiptPaperMm = 'receiptPaperMm';
  static const _kReceiptPrinterName = 'receiptPrinterName';
  static const _kInvoicePrinterName = 'invoicePrinterName';

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

  String? _storeId;
  String? get storeId => _storeId;

  String? _storeName;
  String? get storeName => _storeName;

  String? _organizationId;
  String? get organizationId => _organizationId;

  String? _accountId;
  String? get accountId => _accountId;

  String? _pinSalt;
  String get pinSalt => _pinSalt ?? '';

  String? _shiftId;
  String? get shiftId => _shiftId;
  bool get hasShiftId => _shiftId != null && _shiftId!.trim().isNotEmpty;

  int _receiptPaperMm = 80;
  int get receiptPaperMm => _receiptPaperMm == 57 ? 57 : 80;
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
      organizationId: _organizationId!,
      users: _users,
      createdAt: null,
      updatedAt: null,
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
    _storeId = prefs.getString(_kStoreId);
    _storeName = prefs.getString(_kStoreName);
    _organizationId = prefs.getString(_kOrganizationId);
    _accountId = prefs.getString(_kAccountId);

    _shiftId = prefs.getString(_kShiftId);
    _activeUserId = prefs.getString(_kActiveUserId);
    _receiptPaperMm = (prefs.getInt(_kReceiptPaperMm) == 57) ? 57 : 80;
    _receiptPrinterName = prefs.getString(_kReceiptPrinterName);
    _invoicePrinterName = prefs.getString(_kInvoicePrinterName);

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
    _storeId = resp.storeId;
    _storeName = resp.storeName;
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
    await prefs.setString(_kStoreId, _storeId ?? '');
    await prefs.setString(_kStoreName, _storeName ?? '');
    await prefs.setString(_kOrganizationId, _organizationId ?? '');
    await prefs.setString(_kAccountId, _accountId ?? '');

    final jsonUsers = dc.jsonEncode(_users.map((u) => u.toJson()).toList());
    await prefs.setString(_kUsers, jsonUsers);
  }

  Future<void> clearProvisioned({bool keepDeviceId = true}) async {
    _posName = null;
    _posNumber = null;
    _posId = null;
    _storeId = null;
    _storeName = null;
    _organizationId = null;
    _accountId = null;
    _users = [];

    _shiftId = null;
    _activeUserId = null;
    _activeUserName = null;
    _receiptPaperMm = 80;

    if (!keepDeviceId) _deviceId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPosName);
    await prefs.remove(_kPosNumber);
    await prefs.remove(_kPosId);
    await prefs.remove(_kStoreId);
    await prefs.remove(_kStoreName);
    await prefs.remove(_kOrganizationId);
    await prefs.remove(_kAccountId);
    await prefs.remove(_kUsers);

    await prefs.remove(_kShiftId);
    await prefs.remove(_kActiveUserId);
    await prefs.remove(_kActiveUserName);
    await prefs.remove(_kReceiptPaperMm);

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
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShiftId, v);
  }

  Future<void> clearShiftId() async {
    _shiftId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kShiftId);

    notifyListeners();
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

  Future<void> clearActiveUserId() async {
    _activeUserId = null;
    _activeUserName = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActiveUserId);
    await prefs.remove(_kActiveUserName);

    notifyListeners();
  }
}

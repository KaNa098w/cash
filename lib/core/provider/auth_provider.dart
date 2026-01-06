// lib/core/provider/auth_provider.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert' show utf8;

import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';

class AuthTokenProvider extends ChangeNotifier {
  static const _kPosKey = 'posKey';
  static const _kDeviceId = 'deviceId';

  static const _kPosName = 'posName';
  static const _kPosId = 'posId';
  static const _kStoreId = 'storeId';
  static const _kOrganizationId = 'organizationId';
  static const _kAccountId = 'accountId';

  static const _kUsers = 'posUsers';

  // для безопасной локальной проверки PIN (хеш, не PIN)
  static const _kPinSalt = 'pinSalt';

  String? _posKey;
  String? get posKey => _posKey;
  bool get hasPosKey => _posKey != null && _posKey!.trim().isNotEmpty;

  String? _deviceId;
  String? get deviceId => _deviceId;

  String? _posName;
  String? get posName => _posName;

  String? _posId;
  String? get posId => _posId;

  String? _storeId;
  String? get storeId => _storeId;

  String? _organizationId;
  String? get organizationId => _organizationId;

  String? _accountId;
  String? get accountId => _accountId;

  String? _pinSalt;
  String get pinSalt => _pinSalt ?? '';

  List<PosUser> _users = [];
  List<PosUser> get users => List.unmodifiable(_users);

  bool get isProvisioned =>
      hasPosKey &&
      (_storeId != null && _storeId!.isNotEmpty) &&
      (_organizationId != null && _organizationId!.isNotEmpty) &&
      (_posId != null && _posId!.isNotEmpty) &&
      (_posName != null && _posName!.isNotEmpty) &&
      (_accountId != null && _accountId!.isNotEmpty) &&
      _users.isNotEmpty;

  /// Восстанавливаем объект provision из кэша (для оффлайн-входа).
  PosProvisionResponse? get cachedProvision {
    if (!isProvisioned) return null;

    return PosProvisionResponse(
      id: _posId!,
      name: _posName!,
      key: _posKey ?? '',
      accountId: _accountId!,
      storeId: _storeId!,
      organizationId: _organizationId!,
      users: _users,
      createdAt: null,
      updatedAt: null,
    );
  }

  /// sha256(pin|salt) — локальная проверка PIN без хранения PIN.
  String hashPin(String pin) {
    final bytes = utf8.encode('${pin.trim()}|$pinSalt');
    return sha256.convert(bytes).toString();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    _posKey = prefs.getString(_kPosKey);
    _deviceId = prefs.getString(_kDeviceId);

    _posName = prefs.getString(_kPosName);
    _posId = prefs.getString(_kPosId);
    _storeId = prefs.getString(_kStoreId);
    _organizationId = prefs.getString(_kOrganizationId);
    _accountId = prefs.getString(_kAccountId);

    // device id
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceId, _deviceId!);
    }

    // pin salt
    _pinSalt = prefs.getString(_kPinSalt);
    if (_pinSalt == null || _pinSalt!.isEmpty) {
      _pinSalt = const Uuid().v4();
      await prefs.setString(_kPinSalt, _pinSalt!);
    }

    // users
    final usersStr = prefs.getString(_kUsers);
    if (usersStr != null && usersStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(usersStr);
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

    // если меняем ключ — логично сбрасывать provisioning
    await clearProvisioned(keepDeviceId: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPosKey);

    notifyListeners();
  }

  /// Сохраняем provisioning + пользователей в кэш.
  /// Важно: PIN в кэш НЕ кладём, вместо этого кладём pin_hash.
  Future<void> setProvisioned(PosProvisionResponse resp) async {
    _posKey = resp.key;

    _posName = resp.name;
    _posId = resp.id;
    _storeId = resp.storeId;
    _organizationId = resp.organizationId;
    _accountId = resp.accountId;

    // хешируем PINы для оффлайн-проверки
    _users = resp.users.map((u) {
      final apiPin = u.pinCode.trim();
      final h = apiPin.isEmpty ? null : hashPin(apiPin);

      // ⚠️ не храним pinCode после provisioning
      return u.copyWith(pinHash: h, pinCode: '');
    }).toList();

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPosKey, _posKey ?? '');

    await prefs.setString(_kPosName, _posName ?? '');
    await prefs.setString(_kPosId, _posId ?? '');
    await prefs.setString(_kStoreId, _storeId ?? '');
    await prefs.setString(_kOrganizationId, _organizationId ?? '');
    await prefs.setString(_kAccountId, _accountId ?? '');

    final jsonUsers = jsonEncode(_users.map((u) => u.toJson()).toList());
    await prefs.setString(_kUsers, jsonUsers);
  }

  Future<void> clearProvisioned({bool keepDeviceId = true}) async {
    _posName = null;
    _posId = null;
    _storeId = null;
    _organizationId = null;
    _accountId = null;
    _users = [];

    if (!keepDeviceId) _deviceId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPosName);
    await prefs.remove(_kPosId);
    await prefs.remove(_kStoreId);
    await prefs.remove(_kOrganizationId);
    await prefs.remove(_kAccountId);
    await prefs.remove(_kUsers);

    if (!keepDeviceId) {
      await prefs.remove(_kDeviceId);
    }

    notifyListeners();
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthTokenProvider extends ChangeNotifier {
  static const _kPosKey = 'posKey';
  static const _kDeviceId = 'deviceId';

  static const _kPosName = 'posName';
  static const _kPosId = 'posId';
  static const _kStoreId = 'storeId';
  static const _kOrganizationId = 'organizationId';

  static const _kUsers = 'posUsers';

  String? _posKey;
  String? get posKey => _posKey;
  bool get hasPosKey => _posKey != null && _posKey!.isNotEmpty;

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

  List<PosUser> _users = [];
  List<PosUser> get users => _users;

  bool get isProvisioned =>
      (_posKey != null && _posKey!.isNotEmpty) &&
      (_storeId != null && _storeId!.isNotEmpty) &&
      (_organizationId != null && _organizationId!.isNotEmpty);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    _posKey = prefs.getString(_kPosKey);
    _deviceId = prefs.getString(_kDeviceId);

    _posName = prefs.getString(_kPosName);
    _posId = prefs.getString(_kPosId);
    _storeId = prefs.getString(_kStoreId);
    _organizationId = prefs.getString(_kOrganizationId);

    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceId, _deviceId!);
    }

    final usersStr = prefs.getString(_kUsers);
    if (usersStr != null && usersStr.isNotEmpty) {
      final decoded = jsonDecode(usersStr);
      if (decoded is List) {
        _users = decoded
            .whereType<Map<String, dynamic>>()
            .map(PosUser.fromJson)
            .toList();
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

  Future<void> setProvisioned(PosProvisionResponse resp) async {
    // resp.key — это тот же posKey, но сохраним на всякий
    _posKey = resp.key;

    _posName = resp.name;
    _posId = resp.id;
    _storeId = resp.storeId;
    _organizationId = resp.organizationId;

    _users = resp.users;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPosKey, _posKey ?? '');

    await prefs.setString(_kPosName, _posName ?? '');
    await prefs.setString(_kPosId, _posId ?? '');
    await prefs.setString(_kStoreId, _storeId ?? '');
    await prefs.setString(_kOrganizationId, _organizationId ?? '');

    // сохраняем users (под твою новую модель)
    final jsonUsers = jsonEncode(_users.map((u) => u.toJson()).toList());
    await prefs.setString(_kUsers, jsonUsers);
  }

  Future<void> clearProvisioned({bool keepDeviceId = true}) async {
    _posName = null;
    _posId = null;
    _storeId = null;
    _organizationId = null;
    _users = [];

    if (!keepDeviceId) _deviceId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPosName);
    await prefs.remove(_kPosId);
    await prefs.remove(_kStoreId);
    await prefs.remove(_kOrganizationId);
    await prefs.remove(_kUsers);

    if (!keepDeviceId) {
      await prefs.remove(_kDeviceId);
    }

    notifyListeners();
  }
}

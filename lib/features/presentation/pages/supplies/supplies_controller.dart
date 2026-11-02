import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'package:leemon_app/features/data/datasources/supplies_remote_datasource.dart';

class SuppliesController extends ChangeNotifier {
  SuppliesController(
      {required this.api, required this.posKey, required this.deviceId});
  final SuppliesRemoteDataSource api;
  final String posKey, deviceId;
  SupplyReferences references = const SupplyReferences();
  SupplyPage? page;
  SupplyDocument? selected;
  final filters = <String, dynamic>{};
  String? error;
  bool busy = false, _disposed = false;
  String? _manager;
  Map<String, dynamic>? pending;
  bool pendingReviewed = false;
  String get scope =>
      '${Uri.encodeComponent(posKey)}.${Uri.encodeComponent(deviceId)}';
  String get pendingKey => 'supplies.pending.$scope';
  String get draftKey => 'supplies.draft.$scope';
  bool get hasManagerKey => (_manager ?? '').isNotEmpty;
  bool get isDirector => api.isDirector;
  bool get canWrite => isDirector || hasManagerKey;
  String? get managerKey => _manager;
  void setManagerKey(String key) {
    _manager = key.trim();
    _notify();
  }

  void clearManagerKey() {
    _manager = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _manager = null;
    super.dispose();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(pendingKey);
    pending = raw == null ? null : supplyMap(jsonDecode(raw));
    await refresh();
  }

  Future<void> _persistPending(Map<String, dynamic>? value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = value == null
        ? await prefs.remove(pendingKey)
        : await prefs.setString(pendingKey, jsonEncode(value));
    if (!saved) {
      throw StateError('Не удалось сохранить состояние операции на кассе');
    }
    pending = value;
  }

  Future<void> _reload({int? pageNumber}) async {
    if (posKey.trim().isEmpty || deviceId.trim().isEmpty) {
      throw StateError(
          'Не найдены данные POS или устройства. Переподключите кассу.');
    }
    references = await api.references(posKey, deviceId);
    page = await api.list(posKey, deviceId,
        page: pageNumber ?? page?.page ?? 1, filters: filters);
    final id = pending?['document_id']?.toString() ?? selected?.id;
    if (id != null && id.isNotEmpty) {
      try {
        selected = await api.get(posKey, deviceId, id);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 &&
            (pending?['deleted'] == true || pending?['confirmed'] == false)) {
          selected = null;
        } else {
          rethrow;
        }
      }
    }
    if (pending?['confirmed'] == true) {
      if (pending?['attach_draft_identity'] == true && selected != null) {
        final draft = await loadDraft();
        if (draft != null) await saveDraft({...draft, 'id': selected!.id});
      }
      await _persistPending(null);
    }
  }

  Future<void> refresh({int? pageNumber}) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _reload(pageNumber: pageNumber);
      pendingReviewed = pending != null;
    } catch (e) {
      error = supplyError(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> open(String id) async {
    if (busy) return false;
    busy = true;
    error = null;
    pendingReviewed = false;
    _notify();
    try {
      selected = await api.get(posKey, deviceId, id);
      return true;
    } catch (e) {
      error = supplyError(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Never automatically retries a write. A durable marker survives a lost
  /// response or restart; the operator can inspect server data before retrying.
  Future<bool> mutate(
      String label, Future<String?> Function(String manager) operation,
      {String? documentId,
      bool deleting = false,
      bool attachDraftIdentity = false}) async {
    if (busy || pending != null) return false;
    if (posKey.trim().isEmpty || deviceId.trim().isEmpty) {
      error = 'Не найдены данные POS или устройства';
      _notify();
      return false;
    }
    if (!canWrite) {
      error = 'Укажите ключ управляющего';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    pendingReviewed = false;
    _notify();
    var marked = false;
    try {
      await _persistPending({
        'label': label,
        'document_id': documentId,
        'confirmed': false,
        'deleted': deleting,
        'attach_draft_identity': attachDraftIdentity
      });
      marked = true;
      final id = await operation(_manager ?? '');
      await _persistPending({
        'label': label,
        'document_id': id ?? documentId,
        'confirmed': true,
        'deleted': deleting,
        'attach_draft_identity': attachDraftIdentity
      });
      await _reload();
      return true;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) _manager = null;
      final status = e is DioException ? e.response?.statusCode : null;
      if (marked &&
          status != null &&
          status >= 400 &&
          status < 500 &&
          pending?['confirmed'] != true) {
        await _persistPending(null);
      }
      error = supplyError(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> acknowledgeReviewedOperation() async {
    if (busy || !pendingReviewed || pending?['confirmed'] == true) return;
    await _persistPending(null);
    error = null;
    _notify();
  }

  Future<void> saveDraft(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(draftKey, jsonEncode(value))) {
      throw StateError('Не удалось сохранить черновик на кассе');
    }
  }

  Future<Map<String, dynamic>?> loadDraft() async {
    final raw = (await SharedPreferences.getInstance()).getString(draftKey);
    return raw == null ? null : supplyMap(jsonDecode(raw));
  }

  Future<void> clearDraft() async {
    await (await SharedPreferences.getInstance()).remove(draftKey);
  }
}

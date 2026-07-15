import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/features/data/datasources/marketplace_orders_remote_datasource.dart';
import 'package:uuid/uuid.dart';

class MarketplaceOrdersController extends ChangeNotifier
    with WidgetsBindingObserver {
  MarketplaceOrdersController(this._remote) {
    WidgetsBinding.instance.addObserver(this);
  }

  final MarketplaceOrdersRemoteDataSource _remote;

  String _posKey = '';
  String _deviceId = '';
  bool _initialized = false;
  bool _loading = false;
  bool _actionLoading = false;
  String? _error;
  MarketplacePosInfo? _posInfo;
  MarketplaceOrderScope _scope = MarketplaceOrderScope.newOrders;
  List<MarketplaceOrder> _newOrders = const [];
  List<MarketplaceOrder> _activeOrders = const [];
  final Set<String> _knownNewOrderIds = <String>{};
  MarketplaceOrder? _latestIncomingOrder;
  int _notificationRevision = 0;
  final Map<String, String> _shipmentIdempotencyKeys = <String, String>{};
  MarketplaceOrder? _selectedOrder;
  Timer? _pollTimer;
  WebSocket? _socket;
  StreamSubscription? _socketSub;

  bool get loading => _loading;
  bool get actionLoading => _actionLoading;
  String? get error => _error;
  MarketplacePosInfo? get posInfo => _posInfo;
  MarketplaceOrderScope get scope => _scope;
  List<MarketplaceOrder> get newOrders => List.unmodifiable(_newOrders);
  List<MarketplaceOrder> get activeOrders => List.unmodifiable(_activeOrders);
  int get newCount => _newOrders.length;
  int get notificationCount => _newOrders.length;
  MarketplaceOrder? get latestIncomingOrder => _latestIncomingOrder;
  int get notificationRevision => _notificationRevision;
  MarketplaceOrder? get selectedOrder => _selectedOrder;
  List<MarketplaceOrder> get visibleOrders =>
      _scope == MarketplaceOrderScope.active ? _activeOrders : _newOrders;

  Future<void> configure({
    required String posKey,
    required String deviceId,
    bool force = false,
  }) async {
    final safeKey = posKey.trim();
    final safeDeviceId = deviceId.trim();
    if (safeKey.isEmpty || safeDeviceId.isEmpty) return;
    if (!force &&
        _initialized &&
        _posKey == safeKey &&
        _deviceId == safeDeviceId) {
      return;
    }

    _posKey = safeKey;
    _deviceId = safeDeviceId;
    _initialized = true;
    _error = null;
    notifyListeners();

    try {
      _posInfo = await _remote.fetchPosInfo(key: _posKey);
    } catch (_) {
      _posInfo = null;
    }
    await refreshAll();
    _startPolling();
    unawaited(_prepareRealtime());
  }

  Future<void> refreshAll() async {
    if (_posKey.isEmpty) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _remote.listOrders(
          key: _posKey,
          scope: MarketplaceOrderScope.newOrders,
          take: 20,
        ),
        _remote.listOrders(
          key: _posKey,
          scope: MarketplaceOrderScope.active,
          take: 20,
        ),
      ]);
      _applyNewOrders(results[0].items, notifyNew: false);
      _activeOrders = results[1].items;
      await _selectFallbackIfNeeded();
    } catch (e) {
      _error = _friendlyError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshNewOrders() async {
    if (_posKey.isEmpty) return;
    try {
      final page = await _remote.listOrders(
        key: _posKey,
        scope: MarketplaceOrderScope.newOrders,
        take: 20,
      );
      _applyNewOrders(page.items, notifyNew: true);
      await _selectFallbackIfNeeded();
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> deactivate() async {
    _initialized = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
  }

  Future<void> setScope(MarketplaceOrderScope next) async {
    if (_scope == next) return;
    _scope = next;
    _selectedOrder = null;
    notifyListeners();
    await _selectFallbackIfNeeded();
  }

  Future<void> selectOrder(String orderId) async {
    final safeOrderId = orderId.trim();
    if (_posKey.isEmpty || safeOrderId.isEmpty) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _selectedOrder = await _remote.getOrder(
        key: _posKey,
        orderId: safeOrderId,
      );
    } catch (e) {
      _error = _friendlyError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> acceptSelected() async {
    final order = _selectedOrder;
    if (order == null || _posKey.isEmpty) return;
    if (_actionLoading) return;
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _remote.acceptOrder(key: _posKey, orderId: order.id);
      await refreshAll();
      _scope = MarketplaceOrderScope.active;
      await selectOrder(order.id);
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<MarketplaceShipmentResult?> shipSelectedItem({
    required MarketplaceGroupedItem item,
    required num quantity,
  }) async {
    final order = _selectedOrder;
    if (order == null || _posKey.isEmpty) return null;
    if (_actionLoading) return null;
    if (quantity is! int || quantity < 1 || quantity > 100) {
      _error = 'Количество отгрузки должно быть целым числом от 1 до 100.';
      notifyListeners();
      return null;
    }
    if (quantity > item.remainingQuantity) {
      _error = 'Количество превышает остаток по заказу.';
      notifyListeners();
      return null;
    }
    final operationKey = '${order.id}:${item.productId}:$quantity';
    final idempotencyKey = _shipmentIdempotencyKeys.putIfAbsent(
      operationKey,
      () => const Uuid().v4(),
    );
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _remote.shipItem(
        key: _posKey,
        orderId: order.id,
        productId: item.productId,
        quantity: quantity,
        idempotencyKey: idempotencyKey,
      );
      _shipmentIdempotencyKeys.remove(operationKey);
      _selectedOrder = result.order;
      await _refreshListsQuietly();
      notifyListeners();
      return result;
    } catch (e) {
      // A timeout/network error has an unknown server outcome. Keep the key so
      // a manual retry is idempotent. A definitive 4xx response starts a new
      // operation on the next attempt.
      if (_isDefinitiveClientError(e)) {
        _shipmentIdempotencyKeys.remove(operationKey);
      }
      _error = _friendlyError(e);
      notifyListeners();
      return null;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<void> _selectFallbackIfNeeded() async {
    if (_selectedOrder != null) return;
    final first = visibleOrders.isNotEmpty ? visibleOrders.first : null;
    if (first != null) {
      try {
        _selectedOrder =
            await _remote.getOrder(key: _posKey, orderId: first.id);
      } catch (_) {
        _selectedOrder = first;
      }
    }
  }

  Future<void> _refreshListsQuietly() async {
    if (_posKey.isEmpty) return;
    final results = await Future.wait([
      _remote.listOrders(
        key: _posKey,
        scope: MarketplaceOrderScope.newOrders,
        take: 20,
      ),
      _remote.listOrders(
        key: _posKey,
        scope: MarketplaceOrderScope.active,
        take: 20,
      ),
    ]);
    _applyNewOrders(results[0].items, notifyNew: false);
    _activeOrders = results[1].items;
  }

  void _applyNewOrders(
    List<MarketplaceOrder> orders, {
    required bool notifyNew,
  }) {
    final incomingIds = orders.map((order) => order.id).toSet();
    if (notifyNew) {
      final unseenOrders = orders
          .where((order) => !_knownNewOrderIds.contains(order.id))
          .toList(growable: false);
      if (unseenOrders.isNotEmpty) {
        _latestIncomingOrder = unseenOrders.first;
        _notificationRevision++;
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
    }
    _knownNewOrderIds.addAll(incomingIds);
    _newOrders = orders;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(refreshNewOrders());
    });
  }

  Future<void> _prepareRealtime() async {
    final config = _posInfo?.realtime;
    if (config == null || !config.canConnect || kIsWeb) return;

    await _socketSub?.cancel();
    await _socket?.close();
    _socket = null;

    final uri = config.toUri();
    if (uri == null) return;

    try {
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 5));
      _socket = socket;
      socket.add(jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'channel': config.channel},
      }));
      _socketSub = socket.listen(
        (message) => _handleSocketMessage(message, config),
        onError: (_) {},
        onDone: () {},
        cancelOnError: true,
      );
    } catch (_) {
      await _socket?.close();
      _socket = null;
    }
  }

  void _handleSocketMessage(
    Object? message,
    MarketplaceRealtimeConfig config,
  ) {
    final payload = decodeMarketplacePayload(message);
    final event = payload['event']?.toString() ?? payload['type']?.toString();
    final data = decodeMarketplacePayload(payload['data']);
    final nestedEvent = data['event']?.toString() ?? data['type']?.toString();

    if (event == 'pusher:ping') {
      _socket?.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
      return;
    }

    if (event == config.event ||
        nestedEvent == config.event ||
        nestedEvent == 'marketplace_order_created') {
      unawaited(refreshNewOrders());
    }
  }

  String _friendlyError(Object error) {
    if (error is MarketplaceOrdersApiException) {
      if (error.statusCode == 403) {
        return 'Тариф организации неактивен.';
      }
      return error.message;
    }
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      switch (error.response?.statusCode) {
        case 401:
          return 'POS ключ или device_id не прошли проверку.';
        case 403:
          return 'Тариф организации неактивен.';
        case 404:
          return 'Заказ не найден или не доступен этой POS.';
        case 422:
          return 'Действие недоступно для этого заказа.';
      }
    }
    return error.toString();
  }

  bool _isDefinitiveClientError(Object error) {
    if (error is MarketplaceOrdersApiException) {
      final status = error.statusCode;
      return status != null && status >= 400 && status < 500;
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      return status != null && status >= 400 && status < 500;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshNewOrders());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _socketSub?.cancel();
    _socket?.close();
    super.dispose();
  }
}

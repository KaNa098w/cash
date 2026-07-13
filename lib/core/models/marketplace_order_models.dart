import 'dart:convert';

enum MarketplaceOrderScope { newOrders, active, all }

extension MarketplaceOrderScopeApi on MarketplaceOrderScope {
  String get apiValue {
    switch (this) {
      case MarketplaceOrderScope.newOrders:
        return 'new';
      case MarketplaceOrderScope.active:
        return 'active';
      case MarketplaceOrderScope.all:
        return 'all';
    }
  }
}

class MarketplacePosInfo {
  const MarketplacePosInfo({
    required this.id,
    required this.key,
    required this.deviceId,
    required this.storeId,
    required this.marketplaceOrdersChannel,
    required this.realtime,
  });

  factory MarketplacePosInfo.fromJson(Map<String, dynamic> json) {
    final raw = _unwrapData(json);
    final realtime = MarketplaceRealtimeConfig.fromJson(
      _map(raw['realtime']),
      fallbackChannel: _string(raw['marketplace_orders_channel']),
    );
    return MarketplacePosInfo(
      id: _string(raw['id']),
      key: _string(raw['key']),
      deviceId: _string(raw['device_id']),
      storeId: _string(raw['store_id']),
      marketplaceOrdersChannel: _string(raw['marketplace_orders_channel']),
      realtime: realtime,
    );
  }

  final String id;
  final String key;
  final String deviceId;
  final String storeId;
  final String marketplaceOrdersChannel;
  final MarketplaceRealtimeConfig realtime;
}

class MarketplaceRealtimeConfig {
  const MarketplaceRealtimeConfig({
    required this.enabled,
    required this.driver,
    required this.protocol,
    required this.host,
    required this.port,
    required this.path,
    required this.appKey,
    required this.channel,
    required this.event,
  });

  factory MarketplaceRealtimeConfig.fromJson(
    Map<String, dynamic> json, {
    String fallbackChannel = '',
  }) {
    final appKey = _string(json['app_key'] ?? json['key']);
    final path = _string(json['path']);
    return MarketplaceRealtimeConfig(
      enabled: json['enabled'] == true,
      driver: _string(json['driver']),
      protocol: _string(json['protocol']),
      host: _string(json['host']),
      port: _int(json['port']),
      path: path.isNotEmpty ? path : (appKey.isNotEmpty ? '/app/$appKey' : ''),
      appKey: appKey,
      channel: _string(json['channel']).isNotEmpty
          ? _string(json['channel'])
          : fallbackChannel,
      event: _string(json['event']).isNotEmpty
          ? _string(json['event'])
          : 'marketplace.order.created',
    );
  }

  final bool enabled;
  final String driver;
  final String protocol;
  final String host;
  final int? port;
  final String path;
  final String appKey;
  final String channel;
  final String event;

  bool get canConnect =>
      enabled &&
      host.isNotEmpty &&
      channel.isNotEmpty &&
      event.isNotEmpty &&
      (path.isNotEmpty || appKey.isNotEmpty);

  Uri? toUri() {
    if (!canConnect) return null;

    final safeProtocol = protocol == 'ws' || protocol == 'wss'
        ? protocol
        : protocol == 'http'
            ? 'ws'
            : 'wss';
    final safePath = (path.isNotEmpty ? path : '/app/$appKey')
        .replaceAll('{key}', appKey)
        .replaceAll('{app_key}', appKey);

    return Uri(
      scheme: safeProtocol,
      host: host,
      port: port,
      path: safePath.startsWith('/') ? safePath : '/$safePath',
      queryParameters: const {
        'protocol': '7',
        'client': 'leemon-pos-desktop',
        'version': '1.0',
      },
    );
  }
}

class MarketplaceOrdersPage {
  const MarketplaceOrdersPage({required this.items});

  factory MarketplaceOrdersPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] ?? json['data'] ?? const [];
    final list = rawItems is List ? rawItems : const [];
    return MarketplaceOrdersPage(
      items: list
          .whereType<Map>()
          .map((item) => MarketplaceOrder.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );
  }

  final List<MarketplaceOrder> items;
}

class MarketplaceOrder {
  const MarketplaceOrder({
    required this.id,
    required this.status,
    required this.customer,
    required this.items,
    required this.groupedItems,
  });

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    final rawGrouped = json['groupedItems'] ?? const [];
    final rawItems = json['items'] ?? const [];
    return MarketplaceOrder(
      id: _string(json['id']),
      status: _string(json['status']),
      customer: MarketplaceCustomer.fromJson(_map(json['customer'])),
      items: rawItems is List ? rawItems : const [],
      groupedItems: rawGrouped is List
          ? rawGrouped
              .whereType<Map>()
              .map((item) => MarketplaceGroupedItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
    );
  }

  final String id;
  final String status;
  final MarketplaceCustomer customer;
  final List<dynamic> items;
  final List<MarketplaceGroupedItem> groupedItems;

  bool get isAccepted =>
      status == 'processing' ||
      status == 'partially_shipped' ||
      status == 'shipped';

  bool get isShipped => status == 'shipped';
}

class MarketplaceCustomer {
  const MarketplaceCustomer({required this.name, required this.phone});

  factory MarketplaceCustomer.fromJson(Map<String, dynamic> json) {
    return MarketplaceCustomer(
      name: _string(json['name']),
      phone: _string(json['phone']),
    );
  }

  final String name;
  final String phone;
}

class MarketplaceGroupedItem {
  const MarketplaceGroupedItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.requestedQuantity,
    required this.confirmedQuantity,
    required this.cancelledQuantity,
    required this.shippedQuantity,
    required this.remainingQuantity,
    required this.status,
  });

  factory MarketplaceGroupedItem.fromJson(Map<String, dynamic> json) {
    return MarketplaceGroupedItem(
      productId: _string(json['productId'] ?? json['product_id']),
      name: _string(json['name']),
      sku: _string(json['sku']),
      requestedQuantity: _num(json['requestedQuantity']),
      confirmedQuantity: _num(json['confirmedQuantity']),
      cancelledQuantity: _num(json['cancelledQuantity']),
      shippedQuantity: _num(json['shippedQuantity']),
      remainingQuantity: _num(json['remainingQuantity']),
      status: _string(json['status']),
    );
  }

  final String productId;
  final String name;
  final String sku;
  final num requestedQuantity;
  final num confirmedQuantity;
  final num cancelledQuantity;
  final num shippedQuantity;
  final num remainingQuantity;
  final String status;
}

class MarketplaceAcceptResult {
  const MarketplaceAcceptResult({
    required this.ok,
    required this.status,
    required this.accepted,
    required this.assignmentId,
  });

  factory MarketplaceAcceptResult.fromJson(Map<String, dynamic> json) {
    return MarketplaceAcceptResult(
      ok: json['ok'] == true,
      status: (json['status'] as num?)?.toInt() ?? 0,
      accepted: json['accepted'] == true,
      assignmentId: _string(json['assignment_id']),
    );
  }

  final bool ok;
  final int status;
  final bool accepted;
  final String assignmentId;
}

class MarketplaceShipmentResult {
  const MarketplaceShipmentResult({
    required this.ok,
    required this.status,
    required this.order,
    required this.saleCreated,
    required this.saleId,
  });

  factory MarketplaceShipmentResult.fromJson(Map<String, dynamic> json) {
    return MarketplaceShipmentResult(
      ok: json['ok'] == true,
      status: (json['status'] as num?)?.toInt() ?? 0,
      order: MarketplaceOrder.fromJson(_map(json['order'])),
      saleCreated: json['sale_created'] == true,
      saleId: _string(json['sale_id']),
    );
  }

  final bool ok;
  final int status;
  final MarketplaceOrder order;
  final bool saleCreated;
  final String saleId;
}

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return json;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _string(Object? value) => value?.toString().trim() ?? '';

num _num(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, dynamic> decodeMarketplacePayload(Object? payload) {
  if (payload is Map<String, dynamic>) return payload;
  if (payload is Map) return Map<String, dynamic>.from(payload);
  if (payload is String && payload.trim().isNotEmpty) {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  return const {};
}

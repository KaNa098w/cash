import 'dart:convert';

enum MarketplaceOrderScope { newOrders, active, history }

extension MarketplaceOrderScopeApi on MarketplaceOrderScope {
  String get apiValue {
    switch (this) {
      case MarketplaceOrderScope.newOrders:
        return 'new';
      case MarketplaceOrderScope.active:
        return 'active';
      case MarketplaceOrderScope.history:
        return 'history';
    }
  }
}

class MarketplacePosInfo {
  const MarketplacePosInfo({
    required this.id,
    required this.name,
    required this.key,
    required this.deviceId,
    required this.storeId,
    required this.hasMarketplaceIntegration,
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
      name: _string(raw['name']),
      key: _string(raw['key']),
      deviceId: _string(raw['device_id']),
      storeId: _string(raw['store_id']),
      hasMarketplaceIntegration: raw['has_marketplace_integration'] == true,
      marketplaceOrdersChannel: _string(raw['marketplace_orders_channel']),
      realtime: realtime,
    );
  }

  final String id;
  final String name;
  final String key;
  final String deviceId;
  final String storeId;
  final bool hasMarketplaceIntegration;
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
    required this.number,
    required this.status,
    required this.customer,
    required this.items,
    required this.groupedItems,
    this.createdAt,
    this.total = 0,
    this.fulfillmentType = '',
    this.deliveryAddress = '',
  });

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    final delivery = _map(json['delivery']);
    final address = _map(json['address']);
    final totals = _map(json['totals'] ?? json['summary'] ?? json['pricing']);
    final rawGrouped = json['groupedItems'] ??
        json['grouped_items'] ??
        json['items'] ??
        const [];
    final rawItems = json['items'] ?? const [];
    return MarketplaceOrder(
      id: _string(json['id']),
      number: _string(json['number']),
      status: _string(json['status']),
      customer: MarketplaceCustomer.fromJson(
        _map(json['customer']),
        fallbackName: _string(json['recipientName'] ?? json['recipient_name']),
        fallbackPhone:
            _string(json['recipientNumber'] ?? json['recipient_number']),
      ),
      items: rawItems is List ? rawItems : const [],
      groupedItems: rawGrouped is List
          ? rawGrouped
              .whereType<Map>()
              .map((item) => MarketplaceGroupedItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      createdAt: _dateTime(
        json['created_at'] ?? json['createdAt'] ?? json['ordered_at'],
      ),
      total: _num(
        json['total'] ??
            json['total_amount'] ??
            json['totalAmount'] ??
            json['grand_total'] ??
            totals['total'] ??
            totals['total_amount'] ??
            totals['grand_total'],
      ).takeIfPositiveOr(
        _moneyAmount(json['totalPrice'] ?? json['total_price']),
      ),
      fulfillmentType: _string(
        json['fulfillment_type'] ??
            json['fulfillmentType'] ??
            json['delivery_type'] ??
            json['deliveryType'] ??
            json['deliveryMethod'] ??
            json['shipping_type'] ??
            (json['delivery'] is String ? json['delivery'] : null) ??
            (json['is_pickup'] == true ? 'pickup' : null) ??
            delivery['type'] ??
            delivery['method'],
      ),
      deliveryAddress: _string(
        json['delivery_address'] ??
            json['deliveryAddress'] ??
            json['shipping_address'] ??
            delivery['address'],
      ).isNotEmpty
          ? _string(
              json['delivery_address'] ??
                  json['deliveryAddress'] ??
                  json['shipping_address'] ??
                  delivery['address'],
            )
          : _fullAddress(address),
    );
  }

  final String id;
  final String number;
  final String status;
  final MarketplaceCustomer customer;
  final List<dynamic> items;
  final List<MarketplaceGroupedItem> groupedItems;
  final DateTime? createdAt;
  final num total;
  final String fulfillmentType;
  final String deliveryAddress;

  bool get isAccepted =>
      status == 'processing' ||
      status == 'partially_shipped' ||
      status == 'shipped';

  bool get isShipped => status == 'shipped';

  /// Human-readable order number supplied by the marketplace backend.
  /// UUID remains a fallback for older responses without `number`.
  String get displayNumber => number.isNotEmpty ? number : _shortId(id);

  String get fulfillmentLabel {
    final value = fulfillmentType.toLowerCase().trim();
    if (value == 'pickup' ||
        value == 'self_pickup' ||
        value == 'self-pickup' ||
        value == 'takeaway') {
      return 'Самовывоз';
    }
    if (value == 'delivery' || value == 'courier' || value == 'shipping') {
      return 'Доставка';
    }
    if (value == 'standard' || value == 'express' || value == 'intercity') {
      return 'Доставка';
    }
    return fulfillmentType.isEmpty ? 'Не указан' : fulfillmentType;
  }

  num get displayTotal {
    if (total > 0) return total;
    return groupedItems.fold<num>(0, (sum, item) {
      if (item.total > 0) return sum + item.total;
      return sum + item.unitPrice * item.requestedQuantity;
    });
  }
}

String _shortId(String id) {
  if (id.length <= 12) return id;
  return '${id.substring(0, 8)}...${id.substring(id.length - 4)}';
}

DateTime? _dateTime(Object? value) {
  final raw = value?.toString().trim() ?? '';
  return raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
}

String _fullAddress(Map<String, dynamic> address) {
  final parts = <String>[
    _string(address['address']),
    if (_string(address['entrance']).isNotEmpty)
      'подъезд ${_string(address['entrance'])}',
    if (_string(address['apartment']).isNotEmpty)
      'кв. ${_string(address['apartment'])}',
    if (_string(address['floor']).isNotEmpty)
      'этаж ${_string(address['floor'])}',
    if (_string(address['intercom']).isNotEmpty)
      'домофон ${_string(address['intercom'])}',
    _string(address['additionalInfo'] ?? address['additional_info']),
  ];
  return parts.where((part) => part.isNotEmpty).join(', ');
}

class MarketplaceCustomer {
  const MarketplaceCustomer({required this.name, required this.phone});

  factory MarketplaceCustomer.fromJson(
    Map<String, dynamic> json, {
    String fallbackName = '',
    String fallbackPhone = '',
  }) {
    return MarketplaceCustomer(
      name: _string(json['name']).isNotEmpty
          ? _string(json['name'])
          : fallbackName,
      phone: _string(json['phone']).isNotEmpty
          ? _string(json['phone'])
          : fallbackPhone,
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
    required this.images,
    this.unitPrice = 0,
    this.total = 0,
  });

  factory MarketplaceGroupedItem.fromJson(Map<String, dynamic> json) {
    final offer = _map(json['offer']);
    final product = _map(json['product'] ?? offer['product']);
    final rawImages = json['images'] ?? product['images'];
    final directImage = _string(
      json['image_url'] ??
          json['imageUrl'] ??
          json['image'] ??
          product['image_url'] ??
          product['imageUrl'] ??
          product['image'],
    );
    final images = <MarketplaceProductImage>[
      ...(rawImages is List ? rawImages : const [])
          .map(MarketplaceProductImage.tryParse)
          .whereType<MarketplaceProductImage>(),
      if (directImage.isNotEmpty)
        MarketplaceProductImage(url: directImage, sizes: const []),
    ];
    return MarketplaceGroupedItem(
      productId:
          _string(json['productId'] ?? json['product_id'] ?? product['id']),
      name: _string(
        json['name'] ??
            json['product_name'] ??
            json['productName'] ??
            product['name'],
      ),
      sku: _string(json['sku'] ?? offer['sku'] ?? product['sku']),
      requestedQuantity: _num(
        json['requestedQuantity'] ??
            json['requested_quantity'] ??
            json['quantity'] ??
            json['qty'],
      ),
      confirmedQuantity:
          _num(json['confirmedQuantity'] ?? json['confirmed_quantity']),
      cancelledQuantity:
          _num(json['cancelledQuantity'] ?? json['cancelled_quantity']),
      shippedQuantity:
          _num(json['shippedQuantity'] ?? json['shipped_quantity']),
      remainingQuantity: _remainingQuantity(json),
      status: _string(json['status']),
      images: images,
      unitPrice: _num(
        json['unit_price'] ??
            json['unitPrice'] ??
            json['price'] ??
            product['price'],
      ).takeIfPositiveOr(_moneyAmount(json['price'] ?? offer['price'])),
      total: _num(
        json['total'] ??
            json['line_total'] ??
            json['lineTotal'] ??
            json['total_amount'],
      ).takeIfPositiveOr(
        _moneyAmount(json['totalPrice'] ?? json['total_price']),
      ),
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
  final List<MarketplaceProductImage> images;
  final num unitPrice;
  final num total;

  String get imageUrl => images.isEmpty ? '' : images.first.preferredUrl;
}

class MarketplaceProductImage {
  const MarketplaceProductImage({required this.url, required this.sizes});

  factory MarketplaceProductImage.fromJson(Map<String, dynamic> json) {
    final rawSizes = json['sizes'];
    return MarketplaceProductImage(
      url: _string(json['url']),
      sizes: rawSizes is List
          ? rawSizes
              .whereType<Map>()
              .map((size) => MarketplaceProductImageSize.fromJson(
                    Map<String, dynamic>.from(size),
                  ))
              .where((size) => size.url.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }

  static MarketplaceProductImage? tryParse(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return MarketplaceProductImage(url: value.trim(), sizes: const []);
    }
    if (value is Map) {
      return MarketplaceProductImage.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  final String url;
  final List<MarketplaceProductImageSize> sizes;

  String get preferredUrl {
    if (sizes.isEmpty) return url;
    final sorted = [...sizes]..sort((a, b) => a.width.compareTo(b.width));
    for (final size in sorted) {
      if (size.width >= 140) return size.url;
    }
    return sorted.last.url;
  }
}

class MarketplaceProductImageSize {
  const MarketplaceProductImageSize({
    required this.width,
    required this.height,
    required this.url,
  });

  factory MarketplaceProductImageSize.fromJson(Map<String, dynamic> json) {
    return MarketplaceProductImageSize(
      width: _int(json['width']) ?? 0,
      height: _int(json['height']) ?? 0,
      url: _string(json['url']),
    );
  }

  final int width;
  final int height;
  final String url;
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

num _moneyAmount(Object? value) {
  if (value is num || value is String) return _num(value);
  final money = _map(value);
  final amount = _num(money['amount']);
  final precision = _int(money['precision']) ?? 0;
  if (precision <= 0) return amount;
  var divisor = 1;
  for (var i = 0; i < precision; i++) {
    divisor *= 10;
  }
  return amount / divisor;
}

num _remainingQuantity(Map<String, dynamic> json) {
  final explicit = json['remainingQuantity'] ?? json['remaining_quantity'];
  if (explicit != null) return _num(explicit);
  final requested =
      _num(json['requestedQuantity'] ?? json['requested_quantity']);
  final shipped = _num(json['shippedQuantity'] ?? json['shipped_quantity']);
  final cancelled =
      _num(json['cancelledQuantity'] ?? json['cancelled_quantity']);
  final remaining = requested - shipped - cancelled;
  return remaining < 0 ? 0 : remaining;
}

extension on num {
  num takeIfPositiveOr(num fallback) => this > 0 ? this : fallback;
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

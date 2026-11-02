import 'product_response.dart';

Map<String, dynamic> supplyMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
double supplyNumber(dynamic v) => v is num
    ? v.toDouble()
    : double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0;
bool supplyBool(dynamic v) => v == true || v == 1 || v == '1';
String supplyDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class SupplyReference {
  const SupplyReference(this.id, this.name);
  factory SupplyReference.fromJson(Map<String, dynamic> j) => SupplyReference(
      '${j['id'] ?? ''}', '${j['name'] ?? j['title'] ?? j['number'] ?? ''}');
  final String id, name;
}

class SupplyReferences {
  const SupplyReferences(
      {this.suppliers = const [],
      this.warehouses = const [],
      this.accounts = const []});
  final List<SupplyReference> suppliers, warehouses, accounts;
  factory SupplyReferences.fromJson(Map<String, dynamic> j) {
    List<SupplyReference> entries(String key) {
      final raw = j[key];
      final rows = raw is Map ? raw['data'] : raw;
      return rows is List
          ? rows
              .whereType<Map>()
              .map((v) => SupplyReference.fromJson(supplyMap(v)))
              .where((v) => v.id.isNotEmpty)
              .toList()
          : [];
    }

    return SupplyReferences(
        suppliers: entries('suppliers'),
        warehouses: entries('warehouses'),
        accounts: entries('accounts'));
  }
}

class SupplyLine {
  SupplyLine(
      {required this.productId,
      required this.name,
      this.barcode = '',
      this.unit = 'шт.',
      this.quantity = 1,
      this.arrivalPrice = 0,
      this.price = 0});
  factory SupplyLine.fromProduct(ProductModel p) => SupplyLine(
      productId: p.id ?? '',
      name: p.name,
      barcode: p.barcode ?? p.localBarcode ?? '',
      unit: p.measurementUnit,
      arrivalPrice: p.arrivalCost,
      price: p.sellingPrice);
  factory SupplyLine.fromJson(Map<String, dynamic> j) {
    final p = supplyMap(j['product']);
    return SupplyLine(
        productId: '${j['product_id'] ?? j['productId'] ?? p['id'] ?? ''}',
        name: '${j['name'] ?? j['product_name'] ?? p['name'] ?? 'Товар'}',
        barcode: '${j['barcode'] ?? p['barcode'] ?? ''}',
        unit: '${j['measurement_unit'] ?? p['measurement_unit'] ?? 'шт.'}',
        quantity: supplyNumber(j['quantity']),
        arrivalPrice: supplyNumber(j['arrival_price']),
        price: supplyNumber(j['price']));
  }
  final String productId, name, barcode, unit;
  double quantity, arrivalPrice, price;
  double get total => (quantity * arrivalPrice * 100).round() / 100;
  bool get valid =>
      productId.isNotEmpty &&
      quantity.isFinite &&
      quantity > 0 &&
      arrivalPrice.isFinite &&
      arrivalPrice >= 0 &&
      price.isFinite &&
      price >= 0;
  Map<String, dynamic> toRequest() => {
        'product_id': productId,
        'quantity': quantity,
        'arrival_price': arrivalPrice,
        'price': price
      };
  Map<String, dynamic> toDraft() => {
        ...toRequest(),
        'name': name,
        'barcode': barcode,
        'measurement_unit': unit
      };
}

class SupplyPayment {
  SupplyPayment(this.json);
  final Map<String, dynamic> json;
  String get id => '${json['id'] ?? ''}';
  String get accountId =>
      '${json['account_id'] ?? supplyMap(json['account'])['id'] ?? ''}';
  String get accountName =>
      '${supplyMap(json['account'])['name'] ?? json['account_name'] ?? 'Счёт'}';
  double get amount => supplyNumber(json['amount']);
  String get date => '${json['date'] ?? ''}'.split('T').first;
  String get comment => '${json['comment'] ?? ''}';
}

class SupplyDocument {
  SupplyDocument(this.json);
  final Map<String, dynamic> json;
  String get id => '${json['id'] ?? ''}';
  String get number => '${json['number'] ?? 'Без номера'}';
  String get date => '${json['date'] ?? ''}'.split('T').first;
  bool get completed => supplyBool(json['completed']);
  String get supplierId =>
      '${json['supplier_id'] ?? supplyMap(json['supplier'])['id'] ?? ''}';
  String get warehouseId =>
      '${json['warehouse_id'] ?? supplyMap(json['warehouse'])['id'] ?? ''}';
  String get supplierName =>
      '${supplyMap(json['supplier'])['name'] ?? json['supplier_name'] ?? 'Поставщик'}';
  String get warehouseName =>
      '${supplyMap(json['warehouse'])['name'] ?? json['warehouse_name'] ?? 'Склад'}';
  String get note => '${json['note'] ?? ''}';
  List<SupplyLine> get items => (json['items'] as List? ?? [])
      .whereType<Map>()
      .map((v) => SupplyLine.fromJson(supplyMap(v)))
      .toList();
  List<SupplyPayment> get payments => (json['payments'] as List? ?? [])
      .whereType<Map>()
      .map((v) => SupplyPayment(supplyMap(v)))
      .toList();
  double get total => json.containsKey('total_amount')
      ? supplyNumber(json['total_amount'])
      : json.containsKey('total')
          ? supplyNumber(json['total'])
          : items.fold(0, (sum, l) => sum + l.total);
  double get paid => json.containsKey('payments_total')
      ? supplyNumber(json['payments_total'])
      : payments.fold(0, (sum, p) => sum + p.amount);
  double get unpaid => json.containsKey('document_unpaid_amount')
      ? supplyNumber(json['document_unpaid_amount'])
      : (total - paid).clamp(0, double.infinity);
}

class SupplyPage {
  SupplyPage(
      {required this.items,
      this.page = 1,
      this.lastPage = 1,
      this.summary = const {}});
  final List<SupplyDocument> items;
  final int page, lastPage;
  final Map<String, dynamic> summary;
  factory SupplyPage.fromJson(Map<String, dynamic> j) {
    final meta = supplyMap(j['meta']);
    return SupplyPage(
        items: (j['data'] as List? ?? [])
            .whereType<Map>()
            .map((v) => SupplyDocument(supplyMap(v)))
            .toList(),
        page: supplyNumber(meta['current_page'] ?? j['current_page'] ?? 1)
            .toInt(),
        lastPage:
            supplyNumber(meta['last_page'] ?? j['last_page'] ?? 1).toInt(),
        summary: supplyMap(j['summary']));
  }
}

class RemoteApi {
  Future<ServerSyncResponse> pullProducts({String? sinceIso}) async {
// TODO: заменить реальным вызовом
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ServerSyncResponse(
      updated: [
        ServerProduct(
            id: '1',
            name: 'Чай черный',
            price: 600,
            vat: 12,
            version: 2,
            updatedAt: DateTime.now()),
      ],
      deletedIds: const [],
      serverNow: DateTime.now(),
    );
  }

  Future<void> pushSales(List<ServerSale> sales) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

class ServerSyncResponse {
  final List<ServerProduct> updated;
  final List<String> deletedIds;
  final DateTime serverNow;
  ServerSyncResponse(
      {required this.updated,
      required this.deletedIds,
      required this.serverNow});
}

class ServerProduct {
  final String id;
  final String name;
  final double price;
  final double vat;
  final int version;
  final DateTime updatedAt;
  ServerProduct(
      {required this.id,
      required this.name,
      required this.price,
      required this.vat,
      required this.version,
      required this.updatedAt});
}

class ServerSale {
  final String id;
  final DateTime createdAt;
  final String paymentKind;
  final double total;
  final double received;
  final List<ServerSaleItem> items;
  ServerSale(
      {required this.id,
      required this.createdAt,
      required this.paymentKind,
      required this.total,
      required this.received,
      required this.items});
}

class ServerSaleItem {
  final String productId;
  final double qty;
  final double price;
  final double discount;
  ServerSaleItem(
      {required this.productId,
      required this.qty,
      required this.price,
      required this.discount});
}

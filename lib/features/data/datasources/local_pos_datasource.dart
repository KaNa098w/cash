import '../../domain/entities/product.dart';

class LocalPosDataSource {
  final List<Product> _items = List.generate(
    12,
    (i) => Product(id: 'p$i', name: 'Типа товаргой', price: 2000, vat: i.isEven ? 20 : 10),
  );

  Future<List<Product>> search(String q) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _items.where((e) => e.name.toLowerCase().contains(q.toLowerCase())).toList();
  }
}

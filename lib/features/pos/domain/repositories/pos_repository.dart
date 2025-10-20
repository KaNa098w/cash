import '../entities/product.dart';

abstract class PosRepository {
  Future<List<Product>> searchProducts(String query);
}

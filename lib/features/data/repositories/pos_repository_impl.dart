import '../../domain/entities/product.dart';
import '../../domain/repositories/pos_repository.dart';
import '../datasources/local_pos_datasource.dart';

class PosRepositoryImpl implements PosRepository {
  final LocalPosDataSource ds;
  PosRepositoryImpl(this.ds);
  @override
  Future<List<Product>> searchProducts(String query) => ds.search(query);
}

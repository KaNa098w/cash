import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';

void main() {
  test('search returns only one product for a duplicated barcode', () {
    final cubit = ProductsCubit(_UnusedProductRepository());
    cubit.addProduct(_product(id: 'first', name: 'Молоко 1'));
    cubit.addProduct(_product(id: 'second', name: 'Молоко 2'));

    expect(cubit.search('4870000000001'), hasLength(1));
    expect(cubit.search('молоко'), hasLength(1));

    cubit.close();
  });
}

ProductModel _product({required String id, required String name}) {
  return ProductModel(
    id: id,
    name: name,
    measurementUnit: 'шт',
    arrivalCost: 100,
    sellingPrice: 150,
    wholesalePrice: 120,
    barcode: '4870000000001',
  );
}

class _UnusedProductRepository implements ProductRepository {
  @override
  Future<void> clearPopularProductsCache() async {}

  @override
  Future<void> clearProductsCache() async {}

  @override
  Future<PaginatedProducts> getPopularProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PaginatedProducts> getProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) {
    throw UnimplementedError();
  }
}

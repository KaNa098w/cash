import 'package:pos_desktop_clean/core/models/product_response.dart';


sealed class ProductsState {
  const ProductsState();
}

class ProductsInitial extends ProductsState {
  const ProductsInitial();
}

class ProductsLoading extends ProductsState {
  const ProductsLoading();
}

class ProductsLoaded extends ProductsState {
  final List<ProductModel> products;
  final int page;
  final bool hasMore;

  const ProductsLoaded({
    required this.products,
    required this.page,
    required this.hasMore,
  });
}

class ProductsError extends ProductsState {
  final String message;
  const ProductsError(this.message);
}

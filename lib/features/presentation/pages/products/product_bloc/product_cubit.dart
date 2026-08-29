// product_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/marking/gs1_datamatrix_validator.dart';
import 'package:leemon_app/core/models/product_response.dart'; // ✅ ProductModel
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_state.dart';

class ProductsCubit extends Cubit<ProductsState> {
  final ProductRepository repo;

  ProductsCubit(this.repo) : super(const ProductsInitial());

  static const _perPage = 50;
  _ProductSearchIndex _searchIndex = const _ProductSearchIndex.empty();

  /// Search uses normalized strings cached once per catalogue load. This
  /// avoids allocating 90k+ lowercase strings on every key press.
  List<ProductModel> search(String query, {int limit = 100}) {
    return _searchIndex.search(query, limit: limit);
  }

  ProductModel? findByGtin(String gtin) => _searchIndex.findByGtin(gtin);

  Future<List<ProductModel>> loadFirstPage({
    required String key,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    try {
      emit(const ProductsLoading());

      final result = await repo.getProducts(
        key: key,
        page: 1,
        perPage: _perPage,
        forceRefresh: forceRefresh,
        onPageProgress: onPageProgress,
      );

      _searchIndex = _ProductSearchIndex(result.items);

      emit(
        ProductsLoaded(
          products: result.items,
          page: 1,
          hasMore: false,
        ),
      );

      return result.items;
    } catch (e) {
      emit(ProductsError(e.toString()));
      rethrow;
    }
  }

  Future<List<ProductModel>> loadPopularFirstPage({
    required String key,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    try {
      final currentProducts = state is ProductsLoaded
          ? (state as ProductsLoaded).products
          : <ProductModel>[];
      emit(const ProductsLoading());

      final result = await repo.getPopularProducts(
        key: key,
        page: 1,
        perPage: _perPage,
        forceRefresh: forceRefresh,
        onPageProgress: onPageProgress,
      );

      final merged = <ProductModel>[];
      final seen = <String>{};

      String dedupeKey(ProductModel p) {
        final id = (p.id ?? '').trim();
        if (id.isNotEmpty) return 'id:$id';
        final barcode = (p.barcode ?? '').trim();
        final localBarcode = (p.localBarcode ?? '').trim();
        final name = p.name.trim().toLowerCase();
        return 'alt:$barcode|$localBarcode|$name';
      }

      for (final p in [...currentProducts, ...result.items]) {
        final key = dedupeKey(p);
        if (seen.add(key)) merged.add(p);
      }

      _searchIndex = _ProductSearchIndex(merged);

      emit(
        ProductsLoaded(
          products: merged,
          page: 1,
          hasMore: false,
        ),
      );

      return result.items;
    } catch (e) {
      emit(ProductsError(e.toString()));
      rethrow;
    }
  }

  Future<void> loadNextPage() async {
    // no-op
  }

  void updateProduct(ProductModel product) {
    final current = state;
    if (current is! ProductsLoaded) return;

    final productId = (product.id ?? '').trim();
    if (productId.isEmpty) return;

    final products = current.products
        .map((item) => (item.id ?? '').trim() == productId ? product : item)
        .toList(growable: false);
    _searchIndex = _ProductSearchIndex(products);

    emit(
      ProductsLoaded(
        products: products,
        page: current.page,
        hasMore: current.hasMore,
      ),
    );
  }

  void addProduct(ProductModel product) {
    final productId = (product.id ?? '').trim();
    if (productId.isEmpty) return;

    final current = state;
    final products = current is ProductsLoaded
        ? current.products
            .where((item) => (item.id ?? '').trim() != productId)
            .toList()
        : <ProductModel>[];
    final nextProducts = <ProductModel>[product, ...products];
    _searchIndex = _ProductSearchIndex(nextProducts);

    emit(
      ProductsLoaded(
        products: nextProducts,
        page: current is ProductsLoaded ? current.page : 1,
        hasMore: current is ProductsLoaded ? current.hasMore : false,
      ),
    );
  }

  Future<void> reset() async {
    _searchIndex = const _ProductSearchIndex.empty();
    emit(const ProductsInitial());
  }
}

class _ProductSearchIndex {
  const _ProductSearchIndex.empty()
      : _entries = const [],
        _byBarcode = const {},
        _byGtin = const {};

  _ProductSearchIndex(List<ProductModel> products)
      : _entries = products
            .where((product) => !product.isUniversal)
            .map(_ProductSearchEntry.new)
            .toList(growable: false),
        _byBarcode = _buildBarcodeMap(products),
        _byGtin = _buildGtinMap(products);

  final List<_ProductSearchEntry> _entries;
  final Map<String, List<ProductModel>> _byBarcode;
  final Map<String, ProductModel> _byGtin;

  List<ProductModel> search(String rawQuery, {required int limit}) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty || limit <= 0) return const [];
    if (RegExp(r'^\d{8,}$').hasMatch(query)) {
      return List<ProductModel>.unmodifiable(
        (_byBarcode[query] ?? const <ProductModel>[]).take(limit),
      );
    }
    final result = <ProductModel>[];
    for (final entry in _entries) {
      if (entry.name.contains(query) ||
          entry.barcode.contains(query) ||
          entry.localBarcode.contains(query)) {
        result.add(entry.product);
        if (result.length == limit) break;
      }
    }
    return result;
  }

  ProductModel? findByGtin(String gtin) => _byGtin[gtin];

  static Map<String, List<ProductModel>> _buildBarcodeMap(
      List<ProductModel> products) {
    final result = <String, List<ProductModel>>{};
    for (final product in products) {
      if (product.isUniversal) continue;
      for (final value in [product.barcode, product.localBarcode]) {
        final key = (value ?? '').toString().trim().toLowerCase();
        if (key.isNotEmpty) (result[key] ??= <ProductModel>[]).add(product);
      }
    }
    return result;
  }

  static Map<String, ProductModel> _buildGtinMap(List<ProductModel> products) {
    final result = <String, ProductModel>{};
    for (final product in products) {
      if (product.isUniversal) continue;
      for (final value in [product.gtin, product.ntin]) {
        final key = Gs1DataMatrixValidator.normalizeGtin14(value);
        if (key != null) result.putIfAbsent(key, () => product);
      }
    }
    return result;
  }
}

class _ProductSearchEntry {
  _ProductSearchEntry(this.product)
      : name = product.name.toLowerCase(),
        barcode = (product.barcode ?? '').toString().toLowerCase(),
        localBarcode = (product.localBarcode ?? '').toString().toLowerCase();

  final ProductModel product;
  final String name;
  final String barcode;
  final String localBarcode;
}

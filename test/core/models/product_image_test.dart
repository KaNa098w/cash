import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/domain/entities/product.dart';

void main() {
  test('product image prefers cover_url and falls back to images', () {
    final covered = ProductModel.fromJson({
      'id': '1',
      'name': 'Яблоки',
      'measurement_unit': 'кг',
      'cover_url': 'https://cdn.example/cover.jpg',
      'images': ['https://cdn.example/fallback.jpg'],
    });
    expect(covered.primaryImageUrl, 'https://cdn.example/cover.jpg');

    final fallback = ProductModel.fromJson({
      'id': '2',
      'name': 'Груши',
      'measurement_unit': 'кг',
      'cover_url': null,
      'images': ['', 'https://cdn.example/pear.jpg'],
    });
    expect(fallback.primaryImageUrl, 'https://cdn.example/pear.jpg');
  });

  test('cart product preserves image data through persistence', () {
    const product = Product(
      id: '1',
      name: 'Яблоки',
      price: 500,
      coverUrl: 'https://cdn.example/apple.jpg',
      images: ['https://cdn.example/apple-2.jpg'],
    );

    final restored = Product.fromJson(product.toJson());
    expect(restored.coverUrl, product.coverUrl);
    expect(restored.images, product.images);
    expect(restored.primaryImageUrl, product.coverUrl);
  });
}

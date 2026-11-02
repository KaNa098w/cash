import 'product_response.dart';

class ProductCreationForm {
  const ProductCreationForm(
      {required this.name,
      required this.barcode,
      required this.sellingPrice,
      this.arrivalCost = 0,
      this.wholesalePrice = 0,
      this.measurementUnit = MeasurementUnit.pieces,
      this.localBarcode = '',
      this.sku = '',
      this.categoryId,
      this.conversionValue,
      this.conversionUnit});
  final String name, barcode, localBarcode, sku;
  final String? categoryId, conversionUnit;
  final double sellingPrice, arrivalCost, wholesalePrice;
  final double? conversionValue;
  final MeasurementUnit measurementUnit;

  void validate() {
    if (name.trim().isEmpty) throw StateError('Укажите название товара');
    if (!RegExp(r'^\d{11,13}$').hasMatch(barcode.trim())) {
      throw StateError('Штрихкод должен содержать от 11 до 13 цифр');
    }
    for (final price in [arrivalCost, sellingPrice, wholesalePrice]) {
      if (!price.isFinite || price < 0) {
        throw StateError('Цены должны быть неотрицательными числами');
      }
    }
    if (conversionValue != null &&
        (!conversionValue!.isFinite ||
            conversionValue! <= 0 ||
            (conversionUnit ?? '').isEmpty)) {
      throw StateError('Укажите положительный коэффициент и единицу упаковки');
    }
  }

  Map<String, dynamic> toRequest() {
    validate();
    return {
      'name': name.trim(),
      'barcode': barcode.trim(),
      'measurement_unit': measurementUnit.apiValue,
      'arrival_cost': arrivalCost,
      'selling_price': sellingPrice,
      'wholesale_price': wholesalePrice,
      if (localBarcode.trim().isNotEmpty) 'local_barcode': localBarcode.trim(),
      if (sku.trim().isNotEmpty) 'sku': sku.trim(),
      if ((categoryId ?? '').isNotEmpty) 'category_id': categoryId,
      if (conversionValue != null) ...{
        'conversion_value': conversionValue,
        'conversion_unit': conversionUnit
      },
    };
  }
}

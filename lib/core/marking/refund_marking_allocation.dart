import 'package:leemon_app/core/models/sale_model.dart';
import 'gs1_datamatrix_validator.dart';

class RefundMarkingAllocation {
  static Map<String, double> available(
      List<MarkingPartModel> sold, List<MarkingPartModel> returned) {
    final result = <String, double>{};
    for (final part in sold) {
      final code = Gs1DataMatrixValidator.canonicalCode(part.code);
      result[code] = (result[code] ?? 0) + part.quantity;
    }
    for (final part in returned) {
      final code = Gs1DataMatrixValidator.canonicalCode(part.code);
      result[code] = (result[code] ?? 0) - part.quantity;
    }
    return result;
  }

  static bool covers(
      {required num quantity,
      required List<String> codes,
      required List<String> originalCodes,
      required List<MarkingPartModel> sold,
      List<MarkingPartModel> returned = const []}) {
    if (quantity <= 0 || originalCodes.isEmpty) return true;
    final selected = codes.map(Gs1DataMatrixValidator.canonicalCode).toSet();
    final original =
        originalCodes.map(Gs1DataMatrixValidator.canonicalCode).toSet();
    if (selected.isEmpty ||
        selected.length != codes.length ||
        !original.containsAll(selected)) {
      return false;
    }
    // Old history may not include marking_parts. Backend decides allocation;
    // never assume that one package code represents one primary unit.
    if (sold.isEmpty) return true;
    final capacities = available(sold, returned);
    return selected.fold<double>(
            0,
            (sum, code) =>
                sum + (capacities[code] ?? 0).clamp(0, double.infinity)) >=
        quantity;
  }
}

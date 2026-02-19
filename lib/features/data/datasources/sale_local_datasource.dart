import 'package:hive/hive.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';


class SaleLocalDataSource {
  static const _boxName = 'sales_box';
  static const _keyPending = 'pending_sales';

  Future<List<SaleModel>> loadPending() async {
    final box = await Hive.openBox(_boxName);

    final raw = box.get(_keyPending);
    if (raw is! List) return [];

    final result = <SaleModel>[];
    for (final e in raw) {
      if (e is Map) {
        result.add(SaleModel.fromJson(Map<String, dynamic>.from(e as Map)));
      }
    }
    return result;
  }

  Future<void> enqueue(SaleModel sale) async {
    final box = await Hive.openBox(_boxName);

    final current = await loadPending();
    current.add(sale);

    await box.put(_keyPending, current.map((e) => e.toJson()).toList());
  }

  Future<void> removeFromQueueByLocalId(String localId) async {
    final box = await Hive.openBox(_boxName);

    final current = await loadPending();
    current.removeWhere((e) => e.localId == localId);

    await box.put(_keyPending, current.map((e) => e.toJson()).toList());
  }

  Future<void> clear() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:pos_desktop_clean/core/models/sale_model.dart';
import 'package:pos_desktop_clean/features/data/datasources/refunds_remote_datasource.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/models/refund_pick.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/utils/formatters.dart';

class SalesHistoryController {
  final Map<String, bool> _refundLoading = {};
  final Map<String, Map<String, RefundPick>> _refundPicks = {};

  Timer? _refundPutDebounce;

  bool isRefundLoading(String saleId) => _refundLoading[saleId] == true;

  void setRefundLoading(String saleId, bool v, VoidCallback notify) {
    _refundLoading[saleId] = v;
    notify();
  }

  Map<String, RefundPick> salePickMap(String saleId) {
    return _refundPicks.putIfAbsent(saleId, () => <String, RefundPick>{});
  }

  int refundedQtyOf(SaleItemModel item) {
    final d = item as dynamic;
    final v = d.refund_quantity ?? d.refundQuantity ?? 0;
    return toIntRefunded(v);
  }

  int availableQtyOf(SaleItemModel item) {
    final total = toIntQty(item.quantity);
    final refunded = refundedQtyOf(item);
    final left = total - refunded;
    return left < 0 ? 0 : left;
  }

  RefundPick ensurePick({
    required String saleId,
    required SaleItemModel item,
  }) {
    final saleMap = salePickMap(saleId);
    final sid = item.id.toString();

    final totalQty = toIntQty(item.quantity);
    final refundedQty = refundedQtyOf(item);
    final maxQty = availableQtyOf(item);

    final pick = saleMap.putIfAbsent(
      sid,
      () => RefundPick(
        saleItemId: sid,
        productId: (item.product?.id ?? '').toString(),
        checked: false,
        quantity: 0,
        maxQuantity: maxQty,
        totalQuantity: totalQty,
        refundedQuantity: refundedQty,
        price: toNum(item.price),
      ),
    );

    final changed = pick.totalQuantity != totalQty ||
        pick.maxQuantity != maxQty ||
        pick.refundedQuantity != refundedQty;

    if (changed) {
      pick.totalQuantity = totalQty;
      pick.maxQuantity = maxQty;
      pick.refundedQuantity = refundedQty;

      pick.quantity = pick.quantity.clamp(0, maxQty);
      pick.checked = pick.quantity > 0;
    }

    final newProductId = (item.product?.id ?? '').toString();
    if (pick.productId.trim().isEmpty && newProductId.trim().isNotEmpty) {
      pick.productId = newProductId;
    }

    return pick;
  }

  void toggleItem({
    required String saleId,
    required SaleItemModel item,
    required bool checked,
    required VoidCallback notify,
  }) {
    final pick = ensurePick(saleId: saleId, item: item);

    if (pick.maxQuantity <= 0) {
      pick.checked = false;
      pick.quantity = 0;
      notify();
      return;
    }

    pick.checked = checked;
    if (checked) {
      if (pick.quantity <= 0) pick.quantity = 1;
      if (pick.quantity > pick.maxQuantity) pick.quantity = pick.maxQuantity;
    } else {
      pick.quantity = 0;
    }

    notify();
  }

  void changeQty({
    required String saleId,
    required SaleItemModel item,
    required int newQty,
    required VoidCallback notify,
  }) {
    final pick = ensurePick(saleId: saleId, item: item);

    final q = newQty.clamp(0, pick.maxQuantity);
    pick.quantity = q;
    pick.checked = q > 0;

    notify();
  }

  int selectedItemsCount(String saleId) {
    final m = _refundPicks[saleId];
    if (m == null) return 0;
    return m.values.where((e) => e.checked && e.quantity > 0).length;
  }

  num selectedTotal(String saleId) {
    final m = _refundPicks[saleId];
    if (m == null) return 0;
    num sum = 0;
    for (final e in m.values) {
      if (e.checked && e.quantity > 0) {
        sum += e.price * e.quantity;
      }
    }
    return sum;
  }

  void clearPicksForSale(String saleId, VoidCallback notify) {
    _refundPicks.remove(saleId);
    notify();
  }

  /// Если хочешь debounce PUT при каждом изменении — оставь.
  /// Если нет — просто не используй этот метод.
  void schedulePutRefundUpdate({
    required String saleId,
    required String refundId,
    required String key,
    required SaleModel sale,
    required List<dynamic> items, // RefundItemPayload
    required num totalAmount,
    required VoidCallback notifyLoading,
    required void Function(String msg) toast,
  }) {
    _refundPutDebounce?.cancel();

    _refundPutDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (isRefundLoading(saleId)) return;

      setRefundLoading(saleId, true, notifyLoading);
      try {
        final refundsRemote = GetIt.I<RefundsRemoteDatasource>();

        await refundsRemote.updateRefundV2(
          key: key,
          refundId: refundId,
          saleId: saleId,
          customerId: sale.customerId,
          totalAmount: totalAmount,
          items: items.cast<RefundItemPayload>(),
          date: DateTime.now(),
          returnAccessKey: '', // <— добавить в datasource
        );

        toast('Возврат обновлён');
      } catch (e) {
        toast('Ошибка обновления возврата: $e');
      } finally {
        setRefundLoading(saleId, false, notifyLoading);
      }
    });
  }

  void dispose() {
    _refundPutDebounce?.cancel();
  }
}

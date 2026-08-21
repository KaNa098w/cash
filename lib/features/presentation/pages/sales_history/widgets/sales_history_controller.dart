import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/datasources/refunds_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/models/refund_pick.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/utils/formatters.dart';

class SalesHistoryController {
  final Map<String, bool> _refundLoading = {};
  final Map<String, bool> _refundCoolingDown = {};
  final Map<String, bool> _receiptPrintLoading = {};
  final Map<String, bool> _invoicePrintLoading = {};
  final Map<String, bool> _receiptPrintCoolingDown = {};
  final Map<String, bool> _invoicePrintCoolingDown = {};
  final Map<String, Timer> _receiptPrintCooldownTimers = {};
  final Map<String, Timer> _invoicePrintCooldownTimers = {};
  final Map<String, Timer> _refundCooldownTimers = {};
  final Map<String, Map<String, RefundPick>> _refundPicks = {};

  Timer? _refundPutDebounce;

  bool isRefundLoading(String saleId) =>
      _refundLoading[saleId] == true || _refundCoolingDown[saleId] == true;
  bool isReceiptPrintLoading(String saleId) =>
      _receiptPrintLoading[saleId] == true;
  bool isInvoicePrintLoading(String saleId) =>
      _invoicePrintLoading[saleId] == true;
  bool isReceiptPrintDisabled(String saleId) =>
      isReceiptPrintLoading(saleId) || _receiptPrintCoolingDown[saleId] == true;
  bool isInvoicePrintDisabled(String saleId) =>
      isInvoicePrintLoading(saleId) || _invoicePrintCoolingDown[saleId] == true;

  void setRefundLoading(String saleId, bool v, VoidCallback notify) {
    if (v) {
      _refundCooldownTimers.remove(saleId)?.cancel();
      _refundCoolingDown[saleId] = false;
    }
    _refundLoading[saleId] = v;
    notify();
  }

  /// Atomically reserves refund submission for this sale.
  /// Returns false when another scan/tap is already processing it.
  bool tryStartRefund(String saleId, VoidCallback notify) {
    if (isRefundLoading(saleId)) return false;
    _refundLoading[saleId] = true;
    notify();
    return true;
  }

  void startRefundCooldown(
    String saleId,
    Duration duration,
    VoidCallback notify,
  ) {
    _refundCooldownTimers.remove(saleId)?.cancel();
    _refundLoading[saleId] = false;
    _refundCoolingDown[saleId] = true;
    notify();
    _refundCooldownTimers[saleId] = Timer(duration, () {
      _refundCooldownTimers.remove(saleId);
      _refundCoolingDown[saleId] = false;
      notify();
    });
  }

  void setReceiptPrintLoading(String saleId, bool v, VoidCallback notify) {
    _receiptPrintCooldownTimers.remove(saleId)?.cancel();
    _receiptPrintLoading[saleId] = v;
    if (v) _receiptPrintCoolingDown[saleId] = false;
    notify();
  }

  void setInvoicePrintLoading(String saleId, bool v, VoidCallback notify) {
    _invoicePrintCooldownTimers.remove(saleId)?.cancel();
    _invoicePrintLoading[saleId] = v;
    if (v) _invoicePrintCoolingDown[saleId] = false;
    notify();
  }

  void startReceiptPrintCooldownAfterLoading(
    String saleId,
    Duration loadingDuration,
    Duration cooldownDuration,
    VoidCallback notify,
  ) {
    _receiptPrintCooldownTimers.remove(saleId)?.cancel();
    _receiptPrintCooldownTimers[saleId] = Timer(loadingDuration, () {
      _receiptPrintLoading[saleId] = false;
      _receiptPrintCoolingDown[saleId] = true;
      notify();
      _receiptPrintCooldownTimers[saleId] = Timer(cooldownDuration, () {
        _receiptPrintCooldownTimers.remove(saleId);
        _receiptPrintCoolingDown[saleId] = false;
        notify();
      });
    });
  }

  void startInvoicePrintCooldownAfterLoading(
    String saleId,
    Duration loadingDuration,
    Duration cooldownDuration,
    VoidCallback notify,
  ) {
    _invoicePrintCooldownTimers.remove(saleId)?.cancel();
    _invoicePrintCooldownTimers[saleId] = Timer(loadingDuration, () {
      _invoicePrintLoading[saleId] = false;
      _invoicePrintCoolingDown[saleId] = true;
      notify();
      _invoicePrintCooldownTimers[saleId] = Timer(cooldownDuration, () {
        _invoicePrintCooldownTimers.remove(saleId);
        _invoicePrintCoolingDown[saleId] = false;
        notify();
      });
    });
  }

  Map<String, RefundPick> salePickMap(String saleId) {
    return _refundPicks.putIfAbsent(saleId, () => <String, RefundPick>{});
  }

  int refundedQtyOf(SaleItemModel item) {
    return toIntRefunded(item.refund_quantity ?? 0);
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
    List<String> previouslyReturnedMarkCodes = const <String>[],
  }) {
    final saleMap = salePickMap(saleId);
    // For synced items use server-assigned id; for offline (id empty) fall back to productId.
    final sid = item.id.isNotEmpty ? item.id : item.productId;

    final totalQty = toIntQty(item.quantity);
    final refundedQty = refundedQtyOf(item);
    final maxQty = availableQtyOf(item);

    final pick = saleMap.putIfAbsent(
      sid,
      () => RefundPick(
        saleItemId: sid,
        productId: item.productId.trim().isNotEmpty
            ? item.productId.trim()
            : (item.product?.id ?? '').toString(),
        checked: false,
        quantity: 0,
        maxQuantity: maxQty,
        totalQuantity: totalQty,
        refundedQuantity: refundedQty,
        price: toNum(item.price),
        originalMarkCodes: List<String>.from(item.markCodes),
        previouslyReturnedMarkCodes:
            List<String>.from(previouslyReturnedMarkCodes),
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

    final newProductId = item.productId.trim().isNotEmpty
        ? item.productId.trim()
        : (item.product?.id ?? '').toString();
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
    List<String> previouslyReturnedMarkCodes = const <String>[],
  }) {
    final pick = ensurePick(
      saleId: saleId,
      item: item,
      previouslyReturnedMarkCodes: previouslyReturnedMarkCodes,
    );

    if (pick.maxQuantity <= 0) {
      pick.checked = false;
      pick.quantity = 0;
      notify();
      return;
    }

    pick.checked = checked;
    if (checked) {
      if (pick.quantity <= 0) pick.quantity = pick.maxQuantity;
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
    List<String> previouslyReturnedMarkCodes = const <String>[],
  }) {
    final pick = ensurePick(
      saleId: saleId,
      item: item,
      previouslyReturnedMarkCodes: previouslyReturnedMarkCodes,
    );

    final q = newQty.clamp(0, pick.maxQuantity);
    pick.quantity = q;
    pick.checked = q > 0;
    if (pick.markCodes.length > q) {
      pick.markCodes = pick.markCodes.take(q).toList(growable: true);
    }

    notify();
  }

  int selectedItemsCount(String saleId) {
    final m = _refundPicks[saleId];
    if (m == null) return 0;
    return m.values.where((e) => e.checked && e.quantity > 0).length;
  }

  bool hasCompleteMarkCodes(String saleId) {
    final picks = _refundPicks[saleId];
    if (picks == null) return true;
    return picks.values
        .where((pick) => pick.checked && pick.quantity > 0)
        .every((pick) => pick.hasRequiredMarkCodes);
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
    required String? returnAccessKey,
    required String? userId,
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
          returnAccessKey: returnAccessKey,
          userId: userId,
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
    for (final timer in _refundCooldownTimers.values) {
      timer.cancel();
    }
    for (final timer in _receiptPrintCooldownTimers.values) {
      timer.cancel();
    }
    for (final timer in _invoicePrintCooldownTimers.values) {
      timer.cancel();
    }
    _receiptPrintCooldownTimers.clear();
    _invoicePrintCooldownTimers.clear();
    _refundCooldownTimers.clear();
    _refundCoolingDown.clear();
    _receiptPrintCoolingDown.clear();
    _invoicePrintCoolingDown.clear();
  }
}

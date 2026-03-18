import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';

/// type: true = ВЗНОС, false = РАСХОД
Future<bool> showDepositToCashSheet(BuildContext context, bool type) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DepositToCashSheet(type: type),
  );

  return res ?? false;
}

class _DepositToCashSheet extends StatefulWidget {
  const _DepositToCashSheet({required this.type});

  final bool type;

  @override
  State<_DepositToCashSheet> createState() => _DepositToCashSheetState();
}

class _DepositToCashSheetState extends State<_DepositToCashSheet> {
  String _text = '';
  bool _loading = false;

  bool _loadingTypes = false;
  List<Map<String, dynamic>> _expenseTypes = const [];
  String? _expenseTypeId;
  String? _expenseTypeTitle;

  num? get _amount {
    final v = _text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }

  bool get _isExpense => !widget.type; // ✅ type=false -> расход

  @override
  void initState() {
    super.initState();

    // Если это расход — заранее подгружаем типы расходов
    if (_isExpense) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExpenseTypes());
    }
  }

  Future<void> _loadExpenseTypes() async {
    setState(() => _loadingTypes = true);

    try {
      final types = await sl<PosSyncService>().loadExpenseTypes();

      if (!mounted) return;
      setState(() {
        _expenseTypes = types
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'name': item.name,
                ...item.rawJson,
              },
            )
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки типов расходов: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  Future<void> _pickExpenseType() async {
    if (_loadingTypes) return;

    // если ещё не подгружали — подгрузим
    if (_expenseTypes.isEmpty) {
      await _loadExpenseTypes();
    }
    if (!mounted) return;

    if (_expenseTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Типы расходов не найдены')),
      );
      return;
    }

    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.category_outlined, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Выберите тип расхода',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      icon: const Icon(Icons.close),
                      splashRadius: 22,
                      tooltip: 'Закрыть',
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // list container
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6E6EB)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _expenseTypes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = _expenseTypes[i];
                          final id = item['id']?.toString() ?? '';
                          final title = (item['name'] ??
                                  item['title'] ??
                                  item['label'] ??
                                  item['code'] ??
                                  id)
                              .toString();

                          final disabled = id.isEmpty;

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: disabled
                                  ? null
                                  : () => Navigator.of(ctx).pop(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFEDEDF2)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4FF),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                          Icons.receipt_long_outlined,
                                          size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.15,
                                          fontWeight: FontWeight.w500,
                                          color: disabled
                                              ? Colors.black38
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(
                                      Icons.chevron_right,
                                      color: disabled
                                          ? Colors.black26
                                          : Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // footer
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: Color(0xFFE6E6EB)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Text(
                      'ОТМЕНА',
                      style: TextStyle(
                          fontWeight: FontWeight.w500, letterSpacing: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _expenseTypeId = picked['id']?.toString();
      _expenseTypeTitle = (picked['name'] ??
              picked['title'] ??
              picked['label'] ??
              picked['code'] ??
              _expenseTypeId)
          .toString();
    });
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null || amount <= 0) return;

    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не найден key POS терминала')),
      );
      return;
    }

    // ✅ Для расхода обязателен expenseTypeId
    if (_isExpense && (_expenseTypeId == null || _expenseTypeId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите тип расхода')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final provider = context.read<AuthTokenProvider>();
      final deviceId = provider.deviceId?.trim() ?? '';
      final accountId = provider.accountId?.trim() ?? '';
      if (deviceId.isEmpty) {
        throw Exception('deviceId не найден');
      }
      if (accountId.isEmpty) {
        throw Exception('accountId не найден');
      }

      final result = await sl<PosSyncService>().createPayment(
        key: key,
        deviceId: deviceId,
        accountId: accountId,
        isExpense: _isExpense, // ✅ type=false -> расход
        expenseTypeId: _isExpense ? _expenseTypeId : null,
        amount: amount,
        date: DateTime.now(),
        userId: provider.activeUserId?.trim(),
      );

      if (result.result == QueueSendResult.manual) {
        throw Exception(result.errorMessage ?? 'Операция требует ручной обработки');
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isExpense ? 'Расход сохранён' : 'Взнос сохранён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final title = widget.type ? 'Взнос в кассу' : 'Расход из кассы';

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7FB),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, -6),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // grabber
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D6DA),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ✅ выбор типа расхода (только если расход)
              if (_isExpense) ...[
                InkWell(
                  onTap: _loading ? null : _pickExpenseType,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6E6EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.category_outlined, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _expenseTypeTitle ??
                                (_loadingTypes
                                    ? 'Загрузка типов...'
                                    : 'Выберите тип расхода'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_loadingTypes)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // amount display
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE6E6EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _text.isEmpty ? '0' : _text,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const Text(
                      '₸',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              AmountKeypad(
                text: _text,
                onChanged: (v) => setState(() => _text = v),
                showQuickRows: true,
                allowDecimal: true,
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: (_loading || (_amount == null) || (_amount! <= 0))
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'СОХРАНИТЬ',
                          style: TextStyle(
                              fontWeight: FontWeight.w500, letterSpacing: 0.4),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

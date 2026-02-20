import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_desktop_clean/features/data/utils/app_theme.dart';

typedef RefundAccessSubmit = Future<bool> Function(String barcode);

class RefundAccessDialog extends StatefulWidget {
  const RefundAccessDialog({
    super.key,
    required this.onScanned,
  });

  final RefundAccessSubmit onScanned;

  @override
  State<RefundAccessDialog> createState() => _RefundAccessDialogState();
}

class _RefundAccessDialogState extends State<RefundAccessDialog> {
  final FocusNode _focusNode = FocusNode();

  final StringBuffer _buf = StringBuffer();
  DateTime? _lastCharAt;

  bool _checking = false;
  String? _error;

  static const int _maxMsBetweenChars = 60;
  static const int _minLen = 6;
  static const int _maxLen = 64;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _reset([String? error]) {
    _buf.clear();
    _lastCharAt = null;
    _checking = false;
    _error = error;
    setState(() {});
  }

  bool _isFastEnough(DateTime now) {
    final prev = _lastCharAt;
    _lastCharAt = now;
    if (prev == null) return true;
    return now.difference(prev).inMilliseconds <= _maxMsBetweenChars;
  }

  Future<void> _submitCode(String code) async {
    if (_checking) return;

    _checking = true;
    _error = null;
    setState(() {});

    try {
      final ok = await widget.onScanned(code);
      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        _reset('Нет доступа (401). Сканируй снова.');
      }
    } catch (_) {
      if (!mounted) return;
      _reset('Ошибка запроса. Сканируй снова.');
    }
  }

  void _onKey(RawKeyEvent e) {
    if (_checking) return;
    if (e is! RawKeyDownEvent) return;

    final now = DateTime.now();

    if (e.logicalKey == LogicalKeyboardKey.enter) {
      final code = _buf.toString();
      if (code.length < _minLen) {
        _reset('Код слишком короткий. Сканируй снова.');
        return;
      }
      _submitCode(code);
      return;
    }

    if (e.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(false);
      return;
    }

    final ch = e.character;
    if (ch == null || ch.isEmpty) return;

    if (!_isFastEnough(now)) {
      _reset('Ввод вручную запрещён. Используй сканер.');
      return;
    }

    final c = ch.trim();
    if (c.isEmpty) return;

    if (_buf.length >= _maxLen) {
      _reset('Некорректный код. Сканируй снова.');
      return;
    }

    _buf.write(c);
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _onKey,
      child: Dialog(
        backgroundColor: ThemeColors.greyB,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Доступ к возврату',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: _checking
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE3E6EA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _checking ? 'Проверяем…' : 'Сканируй штрих-код доступа',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _checking
                          ? 'Отправляем запрос в сервер.'
                          : 'После скана код сразу уходит в create/update возврата. Ручной ввод запрещён.',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFCCC7)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFCF1322)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFCF1322)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _checking
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 25),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Отмена',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _checking ? null : () => _reset(null),
                      style: ElevatedButton.styleFrom(
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 25),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          backgroundColor: ThemeColors.darkPanel),
                      child: const Text(
                        'Сканировать заново',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

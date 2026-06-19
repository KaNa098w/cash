import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leemon_app/features/data/utils/app_theme.dart';

typedef RefundAccessSubmit = Future<bool> Function(String barcode);

class RefundAccessDialog extends StatefulWidget {
  const RefundAccessDialog({
    super.key,
    required this.onScanned,
    this.title = 'Доступ к возврату',
    this.scanTitle = 'Сканируй штрих-код доступа',
  });

  final RefundAccessSubmit onScanned;
  final String title;
  final String scanTitle;

  @override
  State<RefundAccessDialog> createState() => _RefundAccessDialogState();
}

class _RefundAccessDialogState extends State<RefundAccessDialog> {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _manualFocusNode = FocusNode();

  final StringBuffer _buf = StringBuffer();
  DateTime? _lastCharAt;

  bool _checking = false;
  String? _error;
  bool _manualUnlocked = false;
  int _lockTapCount = 0;
  final _manualCtrl = TextEditingController();

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
    _manualFocusNode.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _focusManualInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _focusNode.unfocus();
      _manualFocusNode.requestFocus();
      _manualCtrl.selection =
          TextSelection.collapsed(offset: _manualCtrl.text.length);
    });
  }

  void _onLockIconTap() {
    _lockTapCount++;
    if (_lockTapCount >= 10) {
      _lockTapCount = 0;
      setState(() {
        _manualUnlocked = true;
        _error = null;
      });
      _focusManualInput();
    }
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
    if (_manualUnlocked) return;
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
    final dialog = Dialog(
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
                GestureDetector(
                  onTap: _onLockIconTap,
                  child: const Icon(Icons.lock_outline, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed:
                      _checking ? null : () => Navigator.of(context).pop(false),
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
                    _checking ? 'Проверяем...' : widget.scanTitle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _checking
                        ? 'Отправляем запрос в сервер.'
                        : _manualUnlocked
                            ? 'Ручной ввод разрешён.'
                            : 'Ручной ввод запрещён.',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  if (_manualUnlocked && !_checking) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _focusManualInput,
                            child: TextField(
                              controller: _manualCtrl,
                              focusNode: _manualFocusNode,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'Введите код вручную',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                              onTap: _focusManualInput,
                              onSubmitted: (v) {
                                final code = v.trim();
                                if (code.length >= _minLen) {
                                  _manualCtrl.clear();
                                  _submitCode(code);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final code = _manualCtrl.text.trim();
                            if (code.length >= _minLen) {
                              _manualCtrl.clear();
                              _submitCode(code);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
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
    );

    if (_manualUnlocked) {
      return dialog;
    }

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _onKey,
      child: dialog,
    );
  }
}

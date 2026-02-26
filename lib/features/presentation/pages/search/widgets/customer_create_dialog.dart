import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/blue_field_widget.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/bottom_btn_widget.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

class CustomerLite {
  final String id;
  final String name;
  final String phone;
  final num balance;

  const CustomerLite({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
  });
}

Future<CustomerLite?> showCustomerCreateDialog(
  BuildContext context, {
  required String posKey,
}) {
  return showDialog<CustomerLite?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CustomerCreateDialog(posKey: posKey),
  );
}

class CustomerCreateDialog extends StatefulWidget {
  const CustomerCreateDialog({
    super.key,
    required this.posKey,
  });

  final String posKey;

  @override
  State<CustomerCreateDialog> createState() => _CustomerCreateDialogState();
}

class _CustomerCreateDialogState extends State<CustomerCreateDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _iinBin = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _iinFocus = FocusNode();

  TextEditingController? _active;

  bool _saving = false;
  String? _errorText;

  OverlayEntry? _keyboardEntry;

  CustomersRemoteDataSource get _ds => GetIt.I<CustomersRemoteDataSource>();

  @override
  void initState() {
    super.initState();

    void bind(FocusNode node, TextEditingController ctrl) {
      node.addListener(() {
        if (node.hasFocus) {
          setState(() => _active = ctrl); // ✅ активное поле меняется
        }
      });
    }

    bind(_nameFocus, _name);
    bind(_phoneFocus, _phone);
    bind(_iinFocus, _iinBin);

    _active = _name;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideKeyboard();

    _name.dispose();
    _phone.dispose();
    _iinBin.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _iinFocus.dispose();
    super.dispose();
  }

  void _showKeyboard() {
    if (_keyboardEntry != null) return;

    _keyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _active ?? _name,
            onEnter: () {
              if (_nameFocus.hasFocus) return _phoneFocus.requestFocus();
              if (_phoneFocus.hasFocus) return _iinFocus.requestFocus();
              _submit();
            },
            onClose: _hideKeyboard,
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_keyboardEntry!);
  }

  void _hideKeyboard() {
    _keyboardEntry?.remove();
    _keyboardEntry = null;
  }

  String _extractDioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message']?.toString();
      if (msg != null && msg.trim().isNotEmpty) return msg.trim();
    }
    return 'Ошибка сети/сервер вернул ошибку';
  }

  Future<void> _submit() async {
    if (_saving) return;

    final posKey = widget.posKey.trim();
    final name = _name.text.trim();
    final phone = _phone.text.trim();

    if (posKey.isEmpty) {
      setState(() => _errorText = 'posKey пустой (не выбрана POS/организация)');
      return;
    }
    if (name.isEmpty) {
      _nameFocus.requestFocus();
      setState(() => _errorText = 'Введите имя');
      return;
    }
    if (phone.isEmpty) {
      _phoneFocus.requestFocus();
      setState(() => _errorText = 'Введите телефон');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      // ✅ один вызов. второй вызов убираем.
      final created = await _ds.createCustomer(
        key: posKey,
        name: name,
        phone: phone,
      );

      if (!mounted) return;

      _hideKeyboard();
      Navigator.of(context).pop(CustomerLite(
        id: created.id,
        name: created.name,
        phone: created.phone,
        balance: 0,
      ));
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = _extractDioMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 520,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2F80ED), width: 2),
          boxShadow: const [
            BoxShadow(
              blurRadius: 26,
              offset: Offset(0, 18),
              color: Color(0x33000000),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Center(
                    child: Text(
                      'Добавление покупателя',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 38,
                  width: 38,
                  child: OutlinedButton(
                    onPressed: _showKeyboard, // ✅ overlay, не блокирует фон
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Icon(Icons.keyboard_alt_outlined, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ✅ Тап по полю делает его активным + можно вводить физ. клавой
            BlueField(
              controller: _name,
              focusNode: _nameFocus,
              hint: 'Имя',
            ),
            const SizedBox(height: 14),
            BlueField(
              controller: _phone,
              focusNode: _phoneFocus,
              hint: 'Телефон',
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorText!,
                  style: const TextStyle(
                    color: Color(0xFFD32F2F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: BottomBtn(
                    text: 'ОТМЕНИТЬ',
                    bg: const Color(0xFFBDBDBD),
                    onTap: () {
                      _hideKeyboard();
                      Navigator.of(context).pop(null);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      BottomBtn(
                        text: _saving ? 'СОЗДАЮ...' : 'СОЗДАТЬ',
                        bg: const Color(0xFF2DB7C8),
                        onTap: _submit,
                      ),
                      if (_saving)
                        const Positioned(
                          right: 12,
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _phone = TextEditingController(text: '+7 7');
  final _iinBin = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _iinFocus = FocusNode();

  TextEditingController? _active;
  bool _saving = false;
  bool _formattingPhone = false;
  String? _errorText;
  OverlayEntry? _keyboardEntry;

  CustomersRemoteDataSource get _ds => GetIt.I<CustomersRemoteDataSource>();

  @override
  void initState() {
    super.initState();

    void bind(FocusNode node, TextEditingController ctrl) {
      node.addListener(() {
        if (node.hasFocus) {
          setState(() => _active = ctrl);
        }
      });
    }

    bind(_nameFocus, _name);
    bind(_phoneFocus, _phone);
    bind(_iinFocus, _iinBin);
    _phone.addListener(_normalizePhoneField);

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
              if (_nameFocus.hasFocus) {
                _phoneFocus.requestFocus();
                return;
              }
              if (_phoneFocus.hasFocus) {
                _submit();
                return;
              }
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

  void _normalizePhoneField() {
    if (_formattingPhone) return;

    final formatted = _formatKzPhone(_phone.text);
    if (_phone.text == formatted) return;

    _formattingPhone = true;
    _phone.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _formattingPhone = false;
  }

  String _formatKzPhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) return '+7 7';

    if (digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    } else if (!digits.startsWith('7')) {
      digits = '7$digits';
    }

    if (digits.length == 1) {
      digits = '77';
    } else if (digits[1] != '7') {
      digits = '7${digits.substring(1)}';
    }

    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    final local = digits.substring(1);
    final parts = <String>[];

    if (local.isNotEmpty) {
      parts.add(local.substring(0, local.length < 3 ? local.length : 3));
    }
    if (local.length > 3) {
      parts.add(local.substring(3, local.length < 6 ? local.length : 6));
    }
    if (local.length > 6) {
      parts.add(local.substring(6, local.length < 8 ? local.length : 8));
    }
    if (local.length > 8) {
      parts.add(local.substring(8, local.length < 10 ? local.length : 10));
    }

    return '+7 ${parts.join(' ')}'.trimRight();
  }

  String _extractDioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message']?.toString();
      if (msg != null && msg.trim().isNotEmpty) return msg.trim();
    }
    return 'Ошибка сети или сервер вернул ошибку';
  }

  Future<void> _submit() async {
    if (_saving) return;

    final posKey = widget.posKey.trim();
    final name = _name.text.trim();
    final phone = _formatKzPhone(_phone.text.trim());
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');

    if (posKey.isEmpty) {
      setState(() => _errorText = 'posKey пустой');
      return;
    }
    if (name.isEmpty) {
      _nameFocus.requestFocus();
      setState(() => _errorText = 'Введите имя');
      return;
    }
    if (phoneDigits.length != 11 || !phoneDigits.startsWith('77')) {
      _phoneFocus.requestFocus();
      setState(
        () => _errorText = 'Введите телефон в формате +7 777 777 77 77',
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final created = await _ds.createCustomer(
        key: posKey,
        name: name,
        phone: phone,
      );

      if (!mounted) return;

      _hideKeyboard();
      Navigator.of(context).pop(
        CustomerLite(
          id: created.id,
          name: created.name,
          phone: _formatKzPhone(created.phone),
          balance: 0,
        ),
      );
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
          borderRadius: BorderRadius.circular(18),
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
                  height: 42,
                  width: 42,
                  child: OutlinedButton(
                    onPressed: _showKeyboard,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.keyboard_alt_outlined, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            BlueField(
              controller: _name,
              focusNode: _nameFocus,
              hint: 'Имя покупателя',
            ),
            const SizedBox(height: 14),
            BlueField(
              controller: _phone,
              focusNode: _phoneFocus,
              hint: '+7 777 777 77 77',
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s]')),
              ],
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

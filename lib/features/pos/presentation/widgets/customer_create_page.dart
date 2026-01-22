// lib/features/pos/presentation/pages/customers/customer_create_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/customer_create_state.dart';

import 'package:pos_desktop_clean/features/pos/presentation/widgets/onscreen_keyboar_widget.dart';

class CustomerCreatePage extends StatefulWidget {
  const CustomerCreatePage({super.key});

  @override
  State<CustomerCreatePage> createState() => _CustomerCreatePageState();
}

class _CustomerCreatePageState extends State<CustomerCreatePage> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _iin = TextEditingController();
  final _comment = TextEditingController();

  // --- focus + active input ---
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _iinFocus = FocusNode();
  final _commentFocus = FocusNode();

  TextEditingController? _activeController;

  // чтобы не открывать модалку повторно на rebuild/фокусах
  bool _keyboardOpened = false;

  @override
  void initState() {
    super.initState();

    void bind(FocusNode node, TextEditingController ctrl) {
      node.addListener(() {
        if (node.hasFocus) {
          _activeController = ctrl;

          // Если клавиатура уже открыта — мы её не переоткрываем.
          // Если хочешь, чтобы при смене фокуса она переоткрывалась
          // (и печатала в новый controller) — скажи, дам вариант.
        }
      });
    }

    bind(_nameFocus, _name);
    bind(_phoneFocus, _phone);
    bind(_iinFocus, _iin);
    bind(_commentFocus, _comment);

    _activeController = _name;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
      _openKeyboard(); // <-- сразу показываем клавиатуру снизу
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _iin.dispose();
    _comment.dispose();

    _nameFocus.dispose();
    _phoneFocus.dispose();
    _iinFocus.dispose();
    _commentFocus.dispose();

    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    context.read<CustomerCreateCubit>().createCustomer(
          fullName: _name.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          iin: _iin.text.trim().isEmpty ? null : _iin.text.trim(),
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        );
  }

  Future<void> _openKeyboard() async {
    if (_keyboardOpened) return;
    _keyboardOpened = true;

    final ctrl = _activeController ?? _name;
    

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, // клавиатура “прилипшая” снизу
      isDismissible: false, // не закрывать тапом мимо
      builder: (_) => OnScreenKeyboardSheet(
        controller: ctrl,
        onEnter: () {
          // Enter: переход по полям, на последнем — сохранение
          if (_commentFocus.hasFocus) {
            _submit();
            return;
          }
          if (_nameFocus.hasFocus) {
            _phoneFocus.requestFocus();
            return;
          }
          if (_phoneFocus.hasFocus) {
            _iinFocus.requestFocus();
            return;
          }
          if (_iinFocus.hasFocus) {
            _commentFocus.requestFocus();
            return;
          }
          _commentFocus.requestFocus();
        },
      ),
    );

    _keyboardOpened = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocProvider(
      create: (_) => CustomerCreateCubit(),
      child: BlocConsumer<CustomerCreateCubit, CustomerCreateState>(
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // если у тебя есть отдельный флаг успеха — тут закрывай страницу
          // if (state.success) Navigator.of(context).pop(true);
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: const Color(0xFFF6F7FB),
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              titleSpacing: 16,
              title: const Text(
                'Добавить покупателя',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  tooltip: 'Клавиатура',
                  onPressed: state.loading ? null : _openKeyboard,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton.icon(
                    onPressed:
                        state.loading ? null : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Закрыть'),
                  ),
                ),
              ],
            ),
            body: AbsorbPointer(
              absorbing: state.loading,
              child: LayoutBuilder(
                builder: (context, c) {
                  final maxW = c.maxWidth;
                  final contentW = maxW >= 980 ? 820.0 : maxW;

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentW),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const _HeaderCard(
                            icon: Icons.person_add_alt_1,
                            title: 'Новый покупатель',
                            subtitle: 'Заполни минимум ФИО. Телефон/ИИН — по желанию.',
                          ),
                          const SizedBox(height: 12),
                          Form(
                            key: _formKey,
                            child: _Card(
                              child: Column(
                                children: [
                                  const _SectionTitle(
                                    icon: Icons.badge_outlined,
                                    title: 'Основные данные',
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _Field(
                                          controller: _name,
                                          focusNode: _nameFocus,
                                          label: 'ФИО*',
                                          hint: 'Например: Алихан Нурбеков',
                                          prefixIcon: Icons.person_outline,
                                          textInputAction: TextInputAction.next,
                                          validator: (v) {
                                            final value = (v ?? '').trim();
                                            if (value.isEmpty) return 'Укажи ФИО';
                                            if (value.length < 3) return 'Слишком коротко';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: _Field(
                                          controller: _phone,
                                          focusNode: _phoneFocus,
                                          label: 'Телефон',
                                          hint: '+7 777 123 45 67',
                                          prefixIcon: Icons.phone_outlined,
                                          keyboardType: TextInputType.phone,
                                          textInputAction: TextInputAction.next,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _Field(
                                          controller: _iin,
                                          focusNode: _iinFocus,
                                          label: 'ИИН',
                                          hint: '12 цифр',
                                          prefixIcon: Icons.numbers_outlined,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.next,
                                          validator: (v) {
                                            final value = (v ?? '').trim();
                                            if (value.isEmpty) return null;
                                            if (value.length != 12) {
                                              return 'ИИН должен быть из 12 цифр';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: _Field(
                                          controller: _comment,
                                          focusNode: _commentFocus,
                                          label: 'Комментарий',
                                          hint: 'Например: постоянный клиент / доставка',
                                          prefixIcon: Icons.notes_outlined,
                                          maxLines: 1,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _submit(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  const Divider(height: 1),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: state.loading
                                              ? null
                                              : () {
                                                  _name.clear();
                                                  _phone.clear();
                                                  _iin.clear();
                                                  _comment.clear();
                                                  _nameFocus.requestFocus();
                                                  _activeController = _name;
                                                },
                                          icon: const Icon(Icons.restart_alt),
                                          label: const Text('Очистить'),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: state.loading ? null : _submit,
                                          icon: state.loading
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.save_outlined),
                                          label: Text(
                                            state.loading ? 'Сохранение...' : 'Сохранить',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            elevation: 0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Клавиатура открывается снизу автоматически.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _Card(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline, color: Colors.black54),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Совет: если используешь поиск по телефону/ИИН — заполняй эти поля, '
                                    'тогда покупателя будет проще находить в будущем.',
                                    style: TextStyle(color: Colors.black87, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- UI helpers ----------------

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9ECF3)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x0A000000),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HeaderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            offset: Offset(0, 12),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black87),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;

  final String label;
  final String hint;
  final IconData prefixIcon;

  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.focusNode,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon),
        filled: true,
        fillColor: const Color(0xFFF6F7FB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E9F2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E9F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

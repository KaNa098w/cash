import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/features/presentation/widgets/show_pos_action_dialog.dart'
    show exitAppFully;

class CashierLoginStep extends StatefulWidget {
  const CashierLoginStep({
    super.key,
    required this.provision,
    required this.onSelectUser,
    required this.onSubmitPin,
    required this.onCancel,
    this.selectedUser,
    this.errorText,
    this.pinLength = 4,

    // ЛЕВАЯ ПАНЕЛЬ
    this.backgroundColor = const Color(0xFF373D46),

    // Munara logo (центр слева)
    this.brandLogo,

    // Leemon logo (снизу слева)
    this.partnerLogo,
    this.siteText = 'Сайт: leemon.kz',
    this.contactsText = 'Контакты менеджера: +7 702 136 70 77',
    this.onWipeAllData,
  });

  final PosProvisionResponse provision;

  final PosUser? selectedUser;
  final String? errorText;

  final ValueChanged<PosUser> onSelectUser;
  final void Function(PosUser user, String pin) onSubmitPin;
  final VoidCallback onCancel;

  final int pinLength;

  final Color backgroundColor;

  /// Прямо как на скрине: большой "munara." + иконка крыши.
  /// Передай сюда SvgPicture.asset(...) или Image.asset(...).
  final Widget? brandLogo;

  /// Нижний логотип leemon слева.
  /// Передай SvgPicture.asset(...) или Image.asset(...).
  final Widget? partnerLogo;

  final String siteText;
  final String contactsText;
  final Future<void> Function()? onWipeAllData;

  @override
  State<CashierLoginStep> createState() => _CashierLoginStepState();
}

class _CashierLoginStepState extends State<CashierLoginStep> {
  late PosUser? _selected;
  String _pin = '';
  String? _localError;
  int _secretTapCount = 0;
  DateTime? _lastSecretTapAt;
  bool _wipingData = false;
  final _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedUser ??
        (widget.provision.users.isNotEmpty
            ? widget.provision.users.first
            : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _ok();
      return KeyEventResult.handled;
    }
    final label = event.character;
    if (label != null && RegExp(r'^[0-9]$').hasMatch(label)) {
      _digit(label);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant CashierLoginStep oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextSelected = widget.selectedUser;
    if (nextSelected != null && oldWidget.selectedUser?.id != nextSelected.id) {
      setState(() {
        _selected = nextSelected;
        _pin = '';
        _localError = null;
      });
    }

    if (oldWidget.provision.users.length != widget.provision.users.length) {
      if (_selected == null && widget.provision.users.isNotEmpty) {
        setState(() => _selected = widget.provision.users.first);
      }
    }
  }

  void _setPin(String v) {
    setState(() {
      _pin = v;
      _localError = null;
    });
  }

  void _digit(String d) {
    if (_pin.length >= widget.pinLength) return;
    _setPin(_pin + d);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    _setPin(_pin.substring(0, _pin.length - 1));
  }

  void _cancel() {
    setState(() {
      _pin = '';
      _localError = null;
    });
    widget.onCancel();
  }

  void _ok() {
    final u = _selected;
    if (u == null) {
      setState(() => _localError = 'Выбери кассира');
      return;
    }
    final pin = _pin.trim();
    if (pin.length != widget.pinLength) {
      setState(() => _localError = 'PIN должен быть ${widget.pinLength} цифры');
      return;
    }
    widget.onSubmitPin(u, pin);
  }

  Future<void> _handleSecretTap() async {
    final now = DateTime.now();
    final last = _lastSecretTapAt;
    _lastSecretTapAt = now;

    if (last == null || now.difference(last).inSeconds > 2) {
      _secretTapCount = 1;
    } else {
      _secretTapCount += 1;
    }

    if (_secretTapCount < 10) return;
    _secretTapCount = 0;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить все данные?'),
            content: const Text(
              'Это действие удалит все локальные данные кассы с устройства. Продолжить?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || widget.onWipeAllData == null || _wipingData) return;
    setState(() => _wipingData = true);
    try {
      await widget.onWipeAllData!.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные успешно удалены')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить данные: $e')),
      );
    } finally {
      if (mounted) setState(() => _wipingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          ColoredBox(
            color: widget.backgroundColor,
            child: LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 900;

                if (!isWide) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _LoginCard(
                        users: widget.provision.users,
                        selected: _selected,
                        onUserChanged: (u) {
                          setState(() {
                            _selected = u;
                            _pin = '';
                            _localError = null;
                          });
                          widget.onSelectUser(u);
                        },
                        pin: _pin,
                        pinLength: widget.pinLength,
                        errorText: widget.errorText ?? _localError,
                        onDigit: _digit,
                        onBackspace: _backspace,
                        onCancel: _cancel,
                        onOk: _ok,
                      ),
                    ),
                  );
                }

                // ✅ как на фото: широкая левая зона и карточка справа с отступом
                const loginCardWidth = 317.0;
                const rightCardOffset = 56.0;
                final leftPaneWidth =
                    (c.maxWidth - rightCardOffset - loginCardWidth)
                        .clamp(420.0, c.maxWidth);

                return Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: leftPaneWidth,
                        height: double.infinity,
                        child: _BrandPane(
                          brandLogo: widget.brandLogo,
                          partnerLogo: widget.partnerLogo,
                          siteText: widget.siteText,
                          contactsText: widget.contactsText,
                        ),
                      ),
                    ),
                    Positioned(
                      right: rightCardOffset,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _LoginCard(
                          users: widget.provision.users,
                          selected: _selected,
                          onUserChanged: (u) {
                            setState(() {
                              _selected = u;
                              _pin = '';
                              _localError = null;
                            });
                            widget.onSelectUser(u);
                          },
                          pin: _pin,
                          pinLength: widget.pinLength,
                          errorText: widget.errorText ?? _localError,
                          onDigit: _digit,
                          onBackspace: _backspace,
                          onCancel: _cancel,
                          onOk: _ok,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: 56,
            height: 56,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _wipingData ? null : _handleSecretTap,
              child: const SizedBox.expand(),
            ),
          ),
          const Positioned(
            top: 24,
            right: 28,
            child: _ExitAppButton(),
          ),
        ],
      ),
    );
  }
}

class _ExitAppButton extends StatelessWidget {
  const _ExitAppButton();

  Future<void> _confirmExit(BuildContext context) async {
    final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFD15850),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Выйти из приложения?',
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Приложение будет закрыто. Все несинхронизированные операции останутся в очереди и отправятся позже.',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF374151),
                                side: const BorderSide(
                                  color: Color(0xFFD1D5DB),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Отмена',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: const Color(0xFFD15850),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Выйти',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;

    if (shouldExit) {
      exitAppFully();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _confirmExit(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Выход из приложения',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/svg/log_out.svg',
                width: 18,
                height: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPane extends StatelessWidget {
  const _BrandPane({
    required this.brandLogo,
    required this.partnerLogo,
    required this.siteText,
    required this.contactsText,
  });

  final Widget? brandLogo;
  final Widget? partnerLogo;
  final String siteText;
  final String contactsText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoWidth = (constraints.maxWidth * 0.72).clamp(320.0, 520.0);
        return Stack(
          children: [
            // Центр: munara логотип
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: logoWidth,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: brandLogo ?? const _FallbackMunaraLogo(),
                ),
              ),
            ),

            // ✅ Низ слева: leemon + тексты (теперь всегда видно)
            Positioned(
              left: 28,
              bottom: 18,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 34,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: partnerLogo ?? const _FallbackLeemonLogo(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(siteText, style: GoogleFonts.inter()),
                            const SizedBox(height: 2),
                            Text(contactsText, style: GoogleFonts.inter()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.users,
    required this.selected,
    required this.onUserChanged,
    required this.pin,
    required this.pinLength,
    required this.errorText,
    required this.onDigit,
    required this.onBackspace,
    required this.onCancel,
    required this.onOk,
  });

  final List<PosUser> users;
  final PosUser? selected;
  final ValueChanged<PosUser> onUserChanged;

  final String pin;
  final int pinLength;
  final String? errorText;

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onCancel;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    final uniqueUsers = <String, PosUser>{};
    for (final user in users) {
      uniqueUsers[user.id] = user;
    }
    final safeUsers = uniqueUsers.values.toList();
    PosUser? safeSelected;
    if (selected != null) {
      for (final user in safeUsers) {
        if (user.id == selected!.id) {
          safeSelected = user;
          break;
        }
      }
    }
    final canOk = safeSelected != null && pin.trim().length == pinLength;
    final pinCtrl = TextEditingController(text: pin)
      ..selection = TextSelection.collapsed(offset: pin.length);

    const _btnRadius = 9.0; // 8.71px
    const _btnH = 71.0;

    return Container(
      width: 317,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22000000), width: 1),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          const Text(
            'ВХОД В КАССУ',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xFF536074),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: _BlueFieldShell(
              child: DropdownButtonFormField<PosUser>(
                value: safeSelected,
                isExpanded: true,
                items: safeUsers
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(
                          u.name.isEmpty ? 'Без имени' : u.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  onUserChanged(v);
                },
                decoration: const InputDecoration(
                  hintText: 'Кассир',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: _BlueFieldShell(
              child: TextField(
                controller: pinCtrl,
                readOnly: true,
                obscureText: true,
                enableInteractiveSelection: false,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  errorText: errorText,
                  errorMaxLines: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PinKeypad(
            onDigit: onDigit,
            onBackspace: onBackspace,
            onDot: () {},
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 122, // 121.66px
                  height: _btnH,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD15850), // #D15850
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_btnRadius),
                      ),
                    ),
                    onPressed: onCancel,
                    child: const Text(
                      'ОТМЕНА',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Colors.white),
                    ),
                  ),
                ),
                SizedBox(
                  width: 124, // 124px
                  height: _btnH,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF33CC99), // #33CC99
                      disabledBackgroundColor: const Color(0xFF33CC99),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_btnRadius),
                      ),
                    ),
                    onPressed: canOk ? onOk : null,
                    child: const Text(
                      'OK',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _BlueFieldShell extends StatelessWidget {
  const _BlueFieldShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD), width: 1),
      ),
      child: child,
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    this.onDot,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onDot;

  static const double gap = 10;

  TextStyle _keyTextStyle(BuildContext context) {
    // Один общий стиль для всех текстовых клавиш
    return GoogleFonts.inter(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      // если нужен единый цвет — раскомментируй:
      // color: Theme.of(context).colorScheme.onSurface,
    );
  }

  Widget _key(Widget child, {VoidCallback? onTap}) {
    return _KeyButton(child: child, onTap: onTap);
  }

  Widget _digitKey(BuildContext context, String value) {
    return _key(
      Text(value, style: _keyTextStyle(context)),
      onTap: () => onDigit(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = _keyTextStyle(context);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _digitKey(context, '7'),
            const SizedBox(width: gap),
            _digitKey(context, '8'),
            const SizedBox(width: gap),
            _digitKey(context, '9'),
          ],
        ),
        const SizedBox(height: gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _digitKey(context, '4'),
            const SizedBox(width: gap),
            _digitKey(context, '5'),
            const SizedBox(width: gap),
            _digitKey(context, '6'),
          ],
        ),
        const SizedBox(height: gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _digitKey(context, '1'),
            const SizedBox(width: gap),
            _digitKey(context, '2'),
            const SizedBox(width: gap),
            _digitKey(context, '3'),
          ],
        ),
        const SizedBox(height: gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _key(Text('.', style: ts), onTap: onDot),
            const SizedBox(width: gap),
            _digitKey(context, '0'),
            const SizedBox(width: gap),
            _key(const Icon(Icons.backspace_outlined, size: 22),
                onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  static const double w = 80;
  static const double h = 62; // было 61.78px
  static const double r = 6;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return SizedBox(
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: const Color(0x11000000), width: 1),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF000000).withOpacity(0.25),
                    offset: const Offset(4, 4),
                    blurRadius: 2,
                    spreadRadius: 0,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(r),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(r),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _FallbackMunaraLogo extends StatelessWidget {
  const _FallbackMunaraLogo();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/svg/munara_logo.svg',
      width: 501, // подгони под твой svg
      fit: BoxFit.contain,
    );
  }
}

class _RoofPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF35C89A)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height * 0.55)
      ..lineTo(size.width * 0.82, size.height * 0.55)
      ..lineTo(size.width * 0.5, size.height * 0.2)
      ..lineTo(size.width * 0.18, size.height * 0.55)
      ..lineTo(0, size.height * 0.55)
      ..close();

    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FallbackLeemonLogo extends StatelessWidget {
  const _FallbackLeemonLogo();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/svg/leemon.svg', // поменяй путь если у тебя другой
      height: 34,
      width: 174,
      fit: BoxFit.contain,
    );
  }
}

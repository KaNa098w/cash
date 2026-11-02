import 'package:flutter/material.dart';

class FooterControlsOnly extends StatelessWidget {
  const FooterControlsOnly({
    super.key,
    required this.smallAmountText,
    required this.bigAmountText,
    this.showAdjustmentButtons = true,
    this.showPayCardButton = true,
    this.onMinus,
    this.onPlus,
    this.onQuick,
    this.onCancel,
    this.onPayCard,
    this.onPay,
    this.paymentLabel = 'ОПЛАТА',
    this.minusLabel = '-',
    this.plusLabel = '+',
    this.quickLabel = 'Товары',
    this.cancelLabel = 'ОТМЕНА',
    this.payCardLabel = 'Быстрая\nпродажа',
    this.quickEnabled,
    this.quickBackgroundColor,
    this.quickForegroundColor = Colors.black,
    this.paymentBackgroundColor,
    this.paymentDisabledBackgroundColor,
    this.paymentForegroundColor = Colors.white,
  });

  final bool showAdjustmentButtons;
  final bool showPayCardButton;
  final String smallAmountText;
  final String bigAmountText;

  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onQuick;
  final VoidCallback? onCancel;
  final VoidCallback? onPayCard;
  final VoidCallback? onPay;
  final String paymentLabel;
  final String minusLabel;
  final String plusLabel;
  final String quickLabel;
  final String cancelLabel;
  final String payCardLabel;
  final bool? quickEnabled;
  final Color? quickBackgroundColor;
  final Color quickForegroundColor;
  final Color? paymentBackgroundColor;
  final Color? paymentDisabledBackgroundColor;
  final Color paymentForegroundColor;

  static const _btnGrey = Color(0xFFCDCDCD);
  static const _btnRed = Color(0xFFCB5B52);
  static const _btnYellow = Color(0xFFF9B32C);

  static const double _gap = 10;

  static const double _kSmallBtnW = 116;
  static const double _kSmallBtnH = 70;
  static const double _r = 8.70588;

  static const double _totalW = 338;
  static const double _totalH = 58;
  static const double _designRowW = _kSmallBtnW * 2 + _totalW + _gap * 2;
  static const double _designContentH = _totalH + _gap + _kSmallBtnH;
  static const double _outerRightPad = 8;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : _designRowW;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (_designContentH + 32 + bottomInset);
        final availableRowWidth =
            (maxWidth - _outerRightPad).clamp(0.0, maxWidth);
        final widthScale = (availableRowWidth / _designRowW).clamp(0.74, 1.0);
        final safeHeight = (maxHeight - bottomInset).clamp(0.0, maxHeight);
        final heightScale =
            (safeHeight / (_designContentH + 8)).clamp(0.74, 1.0);
        final scale = widthScale < heightScale ? widthScale : heightScale;

        double s(double value) => value * scale;
        final rowGap = s(_gap);
        final smallBtnW = s(_kSmallBtnW);
        final smallBtnH = s(_kSmallBtnH);
        final totalW = s(showAdjustmentButtons ? _totalW : _designRowW);
        final totalH = s(_totalH);
        final payW =
            s(_PayBtn._w + (showPayCardButton ? 0 : _kSmallBtnW + _gap));
        final payH = smallBtnH;
        final radius = s(_r);
        final contentHeight = totalH + rowGap + smallBtnH;
        final verticalPad = ((safeHeight - contentHeight) / 2).clamp(4.0, 16.0);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            0,
            verticalPad,
            _outerRightPad,
            verticalPad + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showAdjustmentButtons) ...[
                    _SmallBtn(
                      width: smallBtnW,
                      height: totalH,
                      radius: radius,
                      background: _btnGrey,
                      onTap: onMinus,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: s(6), vertical: s(4)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            minusLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: s(minusLabel == '-' ? 26 : 18),
                              fontWeight: minusLabel == '-'
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: Colors.black,
                              height: 1,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: rowGap),
                    _SmallBtn(
                      width: smallBtnW,
                      height: totalH,
                      radius: radius,
                      background: _btnGrey,
                      onTap: onPlus,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: s(6), vertical: s(4)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            plusLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: s(plusLabel == '+' ? 26 : 18),
                              fontWeight: plusLabel == '+'
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: Colors.black,
                              height: 1,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: rowGap),
                  ],
                  SizedBox(
                    width: totalW,
                    height: totalH,
                    child: _TotalBox(
                      smallText: smallAmountText,
                      bigText: bigAmountText,
                      radius: radius,
                      smallFontSize: s(15),
                      bigFontSize: s(24),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rowGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showPayCardButton) ...[
                    _SmallBtn(
                      width: smallBtnW,
                      height: smallBtnH,
                      radius: radius,
                      background: _btnGrey,
                      onTap: onPayCard,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: s(6),
                          vertical: s(4),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            payCardLabel,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: s(18),
                              fontWeight: FontWeight.w700,
                              color: onPayCard == null
                                  ? const Color(0xFF5F6368)
                                  : Colors.black,
                              height: 1.06,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: rowGap),
                  ],
                  _SmallBtn(
                    width: smallBtnW,
                    height: smallBtnH,
                    radius: radius,
                    background: !(quickEnabled ?? (onPayCard != null))
                        ? const Color(0xFFBDBDBD)
                        : (quickBackgroundColor ?? _btnYellow),
                    onTap: onQuick,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: s(6),
                        vertical: s(4),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          quickLabel,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: s(18),
                            fontWeight: FontWeight.w700,
                            color: quickForegroundColor,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rowGap),
                  _SmallBtn(
                    width: smallBtnW,
                    height: smallBtnH,
                    radius: radius,
                    background: _btnRed,
                    onTap: onCancel,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cancelLabel,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: s(18),
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rowGap),
                  _PayBtn(
                    label: paymentLabel,
                    onTap: onPay,
                    backgroundColor: paymentBackgroundColor,
                    disabledBackgroundColor: paymentDisabledBackgroundColor,
                    foregroundColor: paymentForegroundColor,
                    width: payW,
                    height: payH,
                    radius: radius,
                    fontSize: s(22),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.width,
    required this.height,
    required this.radius,
    required this.background,
    required this.child,
    this.onTap,
  });

  final double width;
  final double height;
  final double radius;
  final Color background;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _DepthButton(
        width: width,
        height: height,
        radius: radius,
        background: background,
        disabledBackground: background,
        onTap: onTap,
        child: child,
      );
}

class _DepthButton extends StatefulWidget {
  const _DepthButton(
      {required this.width,
      required this.height,
      required this.radius,
      required this.background,
      required this.disabledBackground,
      required this.child,
      this.onTap});
  final double width, height, radius;
  final Color background, disabledBackground;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_DepthButton> createState() => _DepthButtonState();
}

class _DepthButtonState extends State<_DepthButton> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final pressed = enabled && _pressed;
    final color = enabled ? widget.background : widget.disabledBackground;
    final radius = BorderRadius.circular(widget.radius);
    final depth = enabled ? 4.0 : 1.0;
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(color, Colors.black, enabled ? 0.23 : 0.08),
          borderRadius: radius,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: pressed ? 0.08 : 0.15),
                    blurRadius: pressed ? 3 : 8,
                    offset: Offset(0, pressed ? 1 : 4),
                  )
                ]
              : const [],
        ),
        child: Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            top: pressed ? depth : 0,
            bottom: pressed ? 0 : depth,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(color, Colors.white, enabled ? 0.10 : 0.03)!,
                    color,
                    Color.lerp(color, Colors.black, enabled ? 0.035 : 0.015)!,
                  ],
                  stops: const [0, 0.45, 1],
                ),
                border: Border.all(
                  color: _focused && enabled
                      ? const Color(0xFF223D58)
                      : Colors.white.withValues(alpha: enabled ? 0.23 : 0.08),
                  width: _focused && enabled ? 2 : 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: radius,
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  onFocusChange: (value) => setState(() => _focused = value),
                  child: Center(child: widget.child),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TotalBox extends StatelessWidget {
  const _TotalBox({
    required this.smallText,
    required this.bigText,
    required this.radius,
    required this.smallFontSize,
    required this.bigFontSize,
  });

  final String smallText;
  final String bigText;
  final double radius;
  final double smallFontSize;
  final double bigFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                smallText,
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontSize: smallFontSize,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF7A7A7A),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              bigText,
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontSize: bigFontSize,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayBtn extends StatelessWidget {
  final String label;
  const _PayBtn({
    required this.label,
    this.onTap,
    required this.width,
    required this.height,
    required this.radius,
    required this.fontSize,
    this.backgroundColor,
    this.disabledBackgroundColor,
    this.foregroundColor = Colors.white,
  });

  final VoidCallback? onTap;
  final double width;
  final double height;
  final double radius;
  final double fontSize;
  final Color? backgroundColor;
  final Color? disabledBackgroundColor;
  final Color foregroundColor;

  static const _btnGreen = Color(0xFF4BCA9B);
  static const _btnDisabled = Color.fromARGB(255, 132, 186, 163);

  static const double _w = FooterControlsOnly._totalW -
      FooterControlsOnly._kSmallBtnW -
      FooterControlsOnly._gap;

  @override
  Widget build(BuildContext context) {
    return _DepthButton(
      width: width,
      height: height,
      radius: radius,
      background: backgroundColor ?? _btnGreen,
      disabledBackground: disabledBackgroundColor ?? _btnDisabled,
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'NotoSans',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: onTap == null
              ? foregroundColor.withValues(alpha: 0.7)
              : foregroundColor,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

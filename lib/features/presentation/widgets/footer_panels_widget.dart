import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FooterControlsOnly extends StatelessWidget {
  const FooterControlsOnly({
    super.key,
    required this.smallAmountText,
    required this.bigAmountText,
    this.onMinus,
    this.onPlus,
    this.onQuick,
    this.onCancel,
    this.onPayCard,
    this.onPay,
  });

  final String smallAmountText;
  final String bigAmountText;

  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onQuick;
  final VoidCallback? onCancel;
  final VoidCallback? onPayCard;
  final VoidCallback? onPay;

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
        final totalW = s(_totalW);
        final totalH = s(_totalH);
        final payW = s(_PayBtn._w);
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
                  _SmallBtn(
                    width: smallBtnW,
                    height: totalH,
                    radius: radius,
                    background: _btnGrey,
                    onTap: onMinus,
                    child: Text(
                      '-',
                      style: GoogleFonts.inter(
                        fontSize: s(26),
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
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
                    child: Text(
                      '+',
                      style: GoogleFonts.inter(
                        fontSize: s(26),
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  SizedBox(width: rowGap),
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
                          'Быстрая\nпродажа',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: s(18),
                            fontWeight: FontWeight.w500,
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
                  _SmallBtn(
                    width: smallBtnW,
                    height: smallBtnH,
                    radius: radius,
                     background: onPayCard == null
                        ? const Color(0xFFBDBDBD)
                        : _btnYellow,
                    onTap: onQuick,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: s(6),
                        vertical: s(4),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Товары',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: s(18),
                            fontWeight: FontWeight.w500,
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
                    height: smallBtnH,
                    radius: radius,
                    background: _btnRed,
                    onTap: onCancel,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '\u041e\u0422\u041c\u0415\u041d\u0410',
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
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
                    onTap: onPay,
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: background,
          disabledBackgroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: child,
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
                style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
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
  const _PayBtn({
    this.onTap,
    required this.width,
    required this.height,
    required this.radius,
    required this.fontSize,
  });

  final VoidCallback? onTap;
  final double width;
  final double height;
  final double radius;
  final double fontSize;

  static const _btnGreen = Color(0xFF4BCA9B);
  static const _btnDisabled = Color.fromARGB(255, 132, 186, 163);

  static const double _w = FooterControlsOnly._totalW -
      FooterControlsOnly._kSmallBtnW -
      FooterControlsOnly._gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _btnGreen,
          disabledBackgroundColor: _btnDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: Text(
          '\u041e\u041f\u041b\u0410\u0422\u0410',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: onTap == null ? Colors.white70 : Colors.white,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

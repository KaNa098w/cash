import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  static const double _kSmallBtnW = 102;
  static const double _kSmallBtnH = 66;
  static const double _r = 8;

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
                        fontSize: s(22),
                        fontWeight: FontWeight.w700,
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
                        fontSize: s(22),
                        fontWeight: FontWeight.w700,
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
                    onTap: onQuick,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '\u0411\u044b\u0441\u0442\u0440\u044b\u0435\n\u0442\u043e\u0432\u0430\u0440\u044b',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: s(14),
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.05,
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
                          fontSize: s(13),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rowGap),
                  _SmallBtn(
                    width: smallBtnW,
                    height: smallBtnH,
                    radius: radius,
                    background: _btnYellow,
                    onTap: onPayCard,
                    child: SvgPicture.asset(
                      'assets/svg/card.svg',
                      width: s(22),
                      height: s(22),
                      colorFilter:
                          const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  SizedBox(width: rowGap),
                  _PayBtn(
                    onTap: onPay,
                    width: payW,
                    height: payH,
                    radius: radius,
                    fontSize: s(18),
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
          backgroundColor: background,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: Text(
          '\u041e\u041f\u041b\u0410\u0422\u0410',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

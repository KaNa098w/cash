import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  static const double _gap = 8;

  static const double _kSmallBtnW = 116;
  static const double _kSmallBtnH = 70;
  static const double _r = 8;

  static const double _totalW = 349;
  static const double _totalH = 62;
  static const double _designRowW = 597;
  static const double _outerRightPad = 8;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : _designRowW;
        final availableRowWidth =
            (maxWidth - _outerRightPad).clamp(0.0, maxWidth);
        final scale = (availableRowWidth / _designRowW).clamp(0.74, 1.0);

        double s(double value) => value * scale;
        final rowGap = s(_gap);
        final smallBtnW = s(_kSmallBtnW);
        final smallBtnH = s(_kSmallBtnH);
        final totalW = s(_totalW);
        final totalH = s(_totalH);
        final payW = s(_PayBtn._w);
        final payH = smallBtnH;
        final radius = s(_r);

        return Padding(
          padding: EdgeInsets.fromLTRB(0, 16, _outerRightPad, 16 + bottomInset),
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
                      '−',
                      style: TextStyle(
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
                      style: TextStyle(
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
                      smallFontSize: s(12),
                      bigFontSize: s(18),
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
                    child: Text(
                      'Быстрые\nтовары',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: s(12),
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        height: 1.05,
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
                        'ОТМЕНА',
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: TextStyle(
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
                style: TextStyle(
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
                fontSize: bigFontSize,
                fontWeight: FontWeight.w800,
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

  static const double _w = 225;

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
          'ОПЛАТА',
          style: TextStyle(
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

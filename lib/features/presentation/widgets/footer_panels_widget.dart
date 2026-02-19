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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _SmallBtn(
                width: _kSmallBtnW,
                height: _totalH,
                radius: _r,
                background: _btnGrey,
                onTap: onMinus,
                child: const Text(
                  '−',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              _SmallBtn(
                width: _kSmallBtnW,
                height: _totalH,
                radius: _r,
                background: _btnGrey,
                onTap: onPlus,
                child: const Text(
                  '+',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              SizedBox(
                width: _totalW,
                height: _totalH,
                child: _TotalBox(
                  smallText: smallAmountText,
                  bigText: bigAmountText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _SmallBtn(
                width: _kSmallBtnW,
                height: _kSmallBtnH,
                radius: _r,
                background: _btnGrey,
                onTap: onQuick,
                child: const Text(
                  'Быстрые\nтовары',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              _SmallBtn(
                width: _kSmallBtnW,
                height: _kSmallBtnH,
                radius: _r,
                background: _btnRed,
                onTap: onCancel,
                child: const Text(
                  'ОТМЕНА',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              _SmallBtn(
                width: _kSmallBtnW,
                height: _kSmallBtnH,
                radius: _r,
                background: _btnYellow,
                onTap: onPayCard,
                child: SvgPicture.asset(
                  'assets/svg/card.svg',
                  width: 22,
                  height: 22,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: _gap),
              _PayBtn(onTap: onPay),
            ],
          ),
        ],
      ),
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
  });

  final String smallText;
  final String bigText;

  static const double _r = 8;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_r),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                smallText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF7A7A7A),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              bigText,
              style: const TextStyle(
                fontSize: 18,
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
  const _PayBtn({this.onTap});

  final VoidCallback? onTap;

  static const _btnGreen = Color(0xFF4BCA9B);
  static const double _r = 8;

  static const double _w = 225;
  static const double _h = 71;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      height: _h,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _btnGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_r),
          ),
        ),
        child: const Text(
          'ОПЛАТА',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class PaymentPanelAnchor extends StatefulWidget {
  const PaymentPanelAnchor({
    super.key,
    required this.child, // твоя _PayBtn
    required this.panelBuilder, // что показываем
    this.panelWidth = 420,
    this.gap = 12,
  });

  final Widget child;
  final WidgetBuilder panelBuilder;
  final double panelWidth;
  final double gap;

  @override
  State<PaymentPanelAnchor> createState() => _PaymentPanelAnchorState();
}

class _PaymentPanelAnchorState extends State<PaymentPanelAnchor> {
  final LayerLink _link = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void toggle() {
    if (_entry != null) {
      _remove();
      return;
    }

    final overlay = Overlay.of(context);

    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(290, 71);

    _entry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final screenW = media.size.width;
        final screenH = media.size.height;

        // панель показываем справа от кнопки, но если не влезает — прижимаем к правому краю
        final maxW = widget.panelWidth.clamp(280, screenW - 16);
        final maxH = (screenH * 0.75).clamp(240, 720);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _remove,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              // смещаем панель так, чтобы её ПРАВЫЙ край совпал с правым краем кнопки
              offset: Offset(size.width - maxW, size.height + widget.gap),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxW.toDouble(),
                    maxHeight: maxH.toDouble(),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.panelBuilder(ctx),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: toggle,
        child: Container(
          key: _anchorKey,
          child: widget.child,
        ),
      ),
    );
  }
}

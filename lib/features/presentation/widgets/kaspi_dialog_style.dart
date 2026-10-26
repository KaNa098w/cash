import 'package:flutter/material.dart';

const kaspiInk = Color(0xFF152237);
const kaspiMuted = Color(0xFF69778B);
const kaspiGreen = Color(0xFF15996C);
const kaspiSurface = Color(0xFFF4F7FA);

class KaspiDialogHeader extends StatelessWidget {
  const KaspiDialogHeader(
      {super.key, required this.title, required this.subtitle, this.onClose});
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
        decoration: const BoxDecoration(
            color: kaspiInk,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Row(children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: const Color(0xFFF04444),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.contactless_rounded,
                  color: Colors.white, size: 30)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFFB7C3D4), fontSize: 13)),
              ])),
          if (onClose != null)
            IconButton(
                tooltip: 'Закрыть',
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
      );
}

enum KaspiStatusTone { neutral, busy, success, error }

class KaspiStatusCard extends StatelessWidget {
  const KaspiStatusCard(
      {super.key,
      required this.title,
      required this.message,
      this.tone = KaspiStatusTone.neutral});
  final String title;
  final String message;
  final KaspiStatusTone tone;
  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      KaspiStatusTone.busy => const Color(0xFF2374CB),
      KaspiStatusTone.success => kaspiGreen,
      KaspiStatusTone.error => const Color(0xFFBD452F),
      KaspiStatusTone.neutral => kaspiMuted,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .18))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 24,
            height: 24,
            child: tone == KaspiStatusTone.busy
                ? CircularProgressIndicator(strokeWidth: 2.5, color: color)
                : Icon(
                    switch (tone) {
                      KaspiStatusTone.success => Icons.check_circle_rounded,
                      KaspiStatusTone.error => Icons.info_outline_rounded,
                      _ => Icons.wifi_rounded,
                    },
                    color: color,
                    size: 24)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          Text(message,
              style:
                  const TextStyle(color: kaspiInk, fontSize: 14, height: 1.45)),
        ])),
      ]),
    );
  }
}

ButtonStyle kaspiPrimaryButton() => FilledButton.styleFrom(
      backgroundColor: kaspiGreen,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFE0E7ED),
      disabledForegroundColor: const Color(0xFF8C98A6),
      minimumSize: const Size(0, 58),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      textStyle: const TextStyle(
          fontFamily: 'NotoSans', fontSize: 16, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

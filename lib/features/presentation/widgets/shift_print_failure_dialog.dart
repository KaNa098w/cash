import 'package:flutter/material.dart';

Future<bool> showShiftPrintFailureDialog(
    BuildContext context, Object error) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Сбой печати отчёта',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => SafeArea(
      child: Center(
        child: Dialog(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DB),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.print_outlined,
                              size: 38, color: Color(0xFFB45309)),
                        ),
                        Positioned(
                          right: -5,
                          bottom: -5,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFF8FAFC), width: 3),
                            ),
                            child: const Icon(Icons.priority_high_rounded,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Не удалось напечатать отчёт',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 23,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Проверьте подключение принтера и бумагу.\nВсё равно закрыть смену?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, height: 1.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_open_rounded,
                            size: 20, color: Color(0xFF15966A)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Смена пока открыта',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A))),
                              SizedBox(height: 4),
                              Text(
                                'Можно вернуться, проверить принтер и повторить закрытие.',
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Theme(
                    data: Theme.of(dialogContext)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      iconColor: const Color(0xFF64748B),
                      collapsedIconColor: const Color(0xFF64748B),
                      title: const Text('Подробности ошибки',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF64748B))),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: SelectableText('$error',
                              style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.45,
                                  color: Color(0xFF9A3412))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final cancel = OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      child: const Text('Не закрывать смену',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    );
                    final proceed = FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: const Color(0xFF22B982),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      child: const Text('Закрыть без печати',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    );
                    if (constraints.maxWidth < 430) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [proceed, const SizedBox(height: 10), cancel],
                      );
                    }
                    return Row(children: [
                      Expanded(child: cancel),
                      const SizedBox(width: 12),
                      Expanded(child: proceed),
                    ]);
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.95, end: 1).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    ),
  );
  return result == true;
}

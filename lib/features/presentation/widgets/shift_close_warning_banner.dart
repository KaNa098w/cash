import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

class ShiftCloseWarningBanner extends StatefulWidget {
  const ShiftCloseWarningBanner({super.key});

  @override
  State<ShiftCloseWarningBanner> createState() =>
      _ShiftCloseWarningBannerState();
}

class _ShiftCloseWarningBannerState extends State<ShiftCloseWarningBanner> {
  static const _warningAfter = Duration(hours: 24);

  Timer? _timer;
  DateTime? _openedAt;
  String? _loadedShiftId;
  bool? _loadedFiscalizationEnabled;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    final auth = context.read<AuthTokenProvider>();
    final shiftId = (auth.shiftId ?? '').trim();
    if (!auth.fiscalizationEnabled || shiftId.isEmpty) {
      if (_openedAt != null ||
          _loadedShiftId != shiftId ||
          _loadedFiscalizationEnabled != auth.fiscalizationEnabled) {
        setState(() {
          _loadedShiftId = shiftId;
          _loadedFiscalizationEnabled = auth.fiscalizationEnabled;
          _openedAt = null;
        });
      }
      _refreshing = false;
      return;
    }

    try {
      final sessions = await sl<PosSyncService>().loadSessions();
      final session = sessions.cast<LocalSession?>().firstWhere(
            (candidate) => candidate?.matches(shiftId) == true,
            orElse: () => null,
          );
      if (!mounted) return;
      setState(() {
        _loadedShiftId = shiftId;
        _loadedFiscalizationEnabled = auth.fiscalizationEnabled;
        _openedAt = session?.openedAt;
      });
    } catch (_) {
      // Не показываем ложное предупреждение, если локальную смену прочитать
      // не удалось. Следующий периодический запуск повторит проверку.
    } finally {
      _refreshing = false;
    }
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours ч ${minutes.toString().padLeft(2, '0')} мин';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthTokenProvider>();
    final currentShiftId = (auth.shiftId ?? '').trim();
    if (currentShiftId != _loadedShiftId ||
        auth.fiscalizationEnabled != _loadedFiscalizationEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
    if (!auth.fiscalizationEnabled) return const SizedBox.shrink();
    final openedAt = _openedAt;
    if (openedAt == null) return const SizedBox.shrink();
    final elapsed = DateTime.now().difference(openedAt);
    if (elapsed < _warningAfter) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFFFFF4E5),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF5B942), width: 1.5),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final message = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF79009),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Смену необходимо закрыть',
                        style: TextStyle(
                          color: Color(0xFF7A2E0E),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Смена открыта ${_durationLabel(elapsed)}. Сдайте смену, чтобы сформировать Z-отчёт и продолжить работу кассы.',
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final button = FilledButton.icon(
              onPressed: () => context.go('/close-shift'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC2410C),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text(
                'Сдать смену',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [message, const SizedBox(height: 10), button],
              );
            }
            return Row(
              children: [
                Expanded(child: message),
                const SizedBox(width: 20),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}

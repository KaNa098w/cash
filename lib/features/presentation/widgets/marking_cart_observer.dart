import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'conversion_product_dialog.dart';

/// Rechecks quantity, codes, additions, removals and store changes. A check is
/// read-only on the server; no sale or fiscal receipt is registered here.
class MarkingCartObserver extends StatefulWidget {
  const MarkingCartObserver({super.key, required this.child});
  final Widget child;
  @override
  State<MarkingCartObserver> createState() => _MarkingCartObserverState();
}

class _MarkingCartObserverState extends State<MarkingCartObserver> {
  PosCubit? _cubit;
  StreamSubscription<PosState>? _subscription;
  Timer? _debounce;
  String? _snapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthTokenProvider>();
    final cubit = context.read<PosCubit>();
    cubit.markingScope =
        '${auth.posKey ?? ''}/${auth.storeId ?? ''}/${auth.deviceId ?? ''}';
    if (_cubit != cubit) {
      _subscription?.cancel();
      _cubit = cubit;
      _subscription = cubit.stream.listen((_) => _schedule());
    }
    _schedule();
  }

  void _schedule() {
    final cubit = _cubit!;
    final snapshot = cubit.markingSnapshot;
    if (_snapshot == snapshot) return;
    _snapshot = snapshot;
    _debounce?.cancel();
    if (cubit.state.items.isEmpty ||
        cubit.state.activeTicket.checkout != null) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted ||
          cubit.isClosed ||
          cubit.state.activeTicket.checkout != null ||
          cubit.markingCheckPassed ||
          cubit.lastMarkingCheckAttempt == cubit.markingSnapshot) {
        return;
      }
      await ensureCartMarkingReady(context);
      if (!mounted) return;
      _snapshot = cubit.markingSnapshot;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

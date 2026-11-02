import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/service/pos_maintenance_service.dart';
import 'package:leemon_app/features/presentation/widgets/pos_maintenance_dialog.dart';

void main() {
  for (final size in [const Size(1024, 768), const Size(500, 600)]) {
    testWidgets('maintenance fits $size during cleanup and after completion',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      final service = PosMaintenanceService(
        clearDiskCache: () => gate.future,
        clearMemoryCache: () => 1572864,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PosMaintenanceDialog(service: service)),
      ));
      expect(find.text('Наводим порядок'), findsOneWidget);
      expect(tester.takeException(), isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Всё готово'), findsOneWidget);
      expect(find.text('1.5 МБ'), findsOneWidget);
      await tester.ensureVisible(find.text('Продолжить работу'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('partial cleanup offers a retry and reports its result',
      (tester) async {
    var attempts = 0;
    final service = PosMaintenanceService(
      clearDiskCache: () async {
        if (++attempts == 1) throw StateError('Busy file');
      },
      clearMemoryCache: () => 0,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PosMaintenanceDialog(service: service)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Очищено частично'), findsOneWidget);
    await tester.ensureVisible(find.text('Повторить очистку'));
    await tester.tap(find.text('Повторить очистку'));
    await tester.pumpAndSettle();
    expect(find.text('Всё готово'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}

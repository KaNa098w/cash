import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/service/pos_maintenance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlapping maintenance shares one run and preserves payment data',
      () async {
    final protectedValues = {
      'persisted_pos_state_v1': 'basket',
      'kaspi.payment.sale-id': 'pending',
      'fiscal_receipts_v1': 'receipt',
      'auth_token': 'token',
    };
    SharedPreferences.setMockInitialValues(protectedValues);
    final gate = Completer<void>();
    var diskCalls = 0;
    var memoryCalls = 0;
    final service = PosMaintenanceService(
      clearDiskCache: () {
        diskCalls++;
        return gate.future;
      },
      clearMemoryCache: () {
        memoryCalls++;
        return 2048;
      },
    );
    final first = service.optimize();
    final second = service.optimize();
    expect(identical(first, second), isTrue);
    gate.complete();
    final result = await first;
    expect(result.diskError, isNull);
    expect(result.memoryBytes, 2048);
    expect(diskCalls, 1);
    expect(memoryCalls, 1);
    final prefs = await SharedPreferences.getInstance();
    for (final entry in protectedValues.entries) {
      expect(prefs.getString(entry.key), entry.value);
    }
    await service.optimize();
    expect(diskCalls, 2);
  });

  test('a failed disk cleanup still clears memory and permits retry', () async {
    var fail = true;
    var memoryCalls = 0;
    final service = PosMaintenanceService(
      clearDiskCache: () async {
        if (fail) throw StateError('Cache file is busy');
      },
      clearMemoryCache: () {
        memoryCalls++;
        return 0;
      },
    );
    expect((await service.optimize()).diskError, isA<StateError>());
    expect(memoryCalls, 1);
    fail = false;
    expect((await service.optimize()).diskError, isNull);
    expect(memoryCalls, 2);
  });
}

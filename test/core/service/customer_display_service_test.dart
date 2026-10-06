import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/service/customer_display_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const enabled = CustomerDisplaySettings(enabled: true, port: 'COM7');

  test('amount retains cents and empty basket is 0.00', () {
    expect(ascii.decode(customerDisplayBytes(enabled, 123.45)), '123.45\r\n');
    expect(ascii.decode(customerDisplayBytes(enabled, 0)), '0.00\r\n');
    expect(
        () => customerDisplayBytes(enabled, double.nan), throwsArgumentError);
    expect(() => customerDisplayBytes(enabled, 1000000), throwsStateError);
    expect(
        customerDisplayBytes(
            const CustomerDisplaySettings(
                protocol: CustomerDisplayProtocol.epson),
            1.25),
        [0x0c, 0x0b, ...ascii.encode('    1.25')]);
  });

  test('settings survive restart; disabled by default', () async {
    expect((await CustomerDisplaySettings.load()).enabled, isFalse);
    await const CustomerDisplaySettings(
            enabled: true,
            port: 'COM12',
            baudRate: 2400,
            columns: 20,
            protocol: CustomerDisplayProtocol.epson)
        .save();
    final saved = await CustomerDisplaySettings.load();
    expect(saved.port, 'COM12');
    expect(saved.enabled, isTrue);
    expect(saved.baudRate, 2400);
    expect(saved.columns, 20);
    expect(saved.protocol, CustomerDisplayProtocol.epson);
  });

  test('basket updates coalesce; clearing and disabling reset display',
      () async {
    final sent = <String>[];
    final service = CustomerDisplayService(
        writer: (_, bytes) async => sent.add(ascii.decode(bytes)));
    addTearDown(service.dispose);
    await service.initialize();
    service.updateTotal(90);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(sent, isEmpty);
    await service.configure(enabled);
    service.updateTotal(100.25);
    service.updateTotal(200.50);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(sent, ['200.50\r\n']);
    service.updateTotal(0);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(sent.last, '0.00\r\n');
    await service.configure(const CustomerDisplaySettings());
    final count = sent.length;
    service.updateTotal(999);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(sent.length, count);
    expect(sent.last, '0.00\r\n');
  });

  test('port error is visible and subsequent update can recover', () async {
    var fail = true;
    final service = CustomerDisplayService(writer: (_, __) async {
      if (fail) throw StateError('Порт занят');
    });
    addTearDown(service.dispose);
    await service.configure(enabled);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(service.error, contains('Порт занят'));
    fail = false;
    service.updateTotal(50.75);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(service.error, isNull);
    expect(service.lastSent, '50.75');
  });

  test('test writes are serialized and restore latest basket', () async {
    final sent = <String>[];
    final tested = Completer<void>();
    final service = CustomerDisplayService(writer: (_, bytes) async {
      final value = ascii.decode(bytes);
      sent.add(value);
      if (value == '123.45\r\n' && !tested.isCompleted) tested.complete();
    });
    addTearDown(service.dispose);
    await service.configure(enabled);
    final testing = service.test(enabled, 123.45);
    await tested.future;
    service.updateTotal(321.99);
    await testing;
    expect(sent.first, '123.45\r\n');
    expect(sent.last, '321.99\r\n');
  });
  test('enabling requires explicit port', () async {
    final service = CustomerDisplayService(writer: (_, __) async {});
    addTearDown(service.dispose);
    await expectLater(
        service.configure(const CustomerDisplaySettings(enabled: true)),
        throwsStateError);
  });
}

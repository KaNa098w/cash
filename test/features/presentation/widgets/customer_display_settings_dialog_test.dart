import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/service/customer_display_service.dart';
import 'package:leemon_app/core/service/scale_service.dart';
import 'package:leemon_app/features/presentation/widgets/customer_display_settings_dialog.dart';

void main() {
  for (final width in [1100.0, 500.0]) {
    testWidgets('display settings fit $width px and show diagnostics',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({'customer_display_port': 'COM7'});
      final service = CustomerDisplayService(writer: (_, __) async {});
      addTearDown(service.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: service,
          child: MaterialApp(
              home: Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showCustomerDisplaySettingsDialog(
                              context,
                              diagnoseHardware: () async =>
                                  const ScaleHardwareDiagnostics(
                                      ports: ['COM7', 'COM9'],
                                      usbSerialAdapter: null)),
                          child: const Text('Open')))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Дисплей покупателя'), findsOneWidget);
      expect(find.text('COM7, COM9'), findsOneWidget);
      expect(find.text('Сумма корзины'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(service.settings.enabled, isTrue);
      expect(service.settings.port, 'COM7');
      expect(find.text('Дисплей покупателя'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:leemon_app/features/presentation/pages/invoices/invoice_text_field.dart';
import 'package:leemon_app/features/presentation/widgets/show_pos_action_dialog.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/payment_invoice.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/invoices_remote_datasource.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/invoices/invoice_issue_dialog.dart';
import 'package:leemon_app/features/presentation/pages/invoices/invoice_history_dialog.dart';

class TestAuth extends AuthTokenProvider {
  @override
  String get posKey => 'KEY';
  @override
  String get deviceId => 'DEVICE';
  @override
  String get storeId => 'STORE';
  @override
  String get activeUserId => 'USER';
  @override
  String get shiftId => 'SHIFT';
}

class EmptyRepo implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

class FakeCustomers extends CustomersRemoteDataSource {
  FakeCustomers() : super(Dio());
  @override
  Future<List<CustomerDto>> listCustomers(
          {required String key,
          int? page,
          int? size,
          bool hasDebt = false}) async =>
      [CustomerDto(id: 'C', name: 'Иван', phone: '')];
}

class FakeInvoices extends InvoicesRemoteDataSource {
  FakeInvoices() : super(Dio());
  bool emptyBanks = false;
  Object? failure;
  final sent = <Map<String, dynamic>>[];
  final confirmations = <Map<String, dynamic>>[];
  PaymentInvoice invoice = PaymentInvoice({
    'id': 'I',
    'number': 15,
    'status': 'issued',
    'due_at': '2099-01-01',
    'total_amount': 3000,
    'customer_details': {'name': 'Иван'},
    'items': []
  });
  final createdCustomers = <Map<String, String>>[];
  @override
  Future<CustomerDto> createCustomer(String key,
      {required String name,
      required String userId,
      String phone = '',
      String bin = '',
      String legalName = '',
      String legalAddress = ''}) async {
    createdCustomers.add({
      'name': name,
      'phone': phone,
      'bin': bin,
      'legal_name': legalName,
      'legal_address': legalAddress
    });
    return CustomerDto(
        id: 'NEW',
        name: name,
        phone: phone,
        bin: bin,
        legalName: legalName,
        legalAddress: legalAddress);
  }

  @override
  Future<List<OrganizationBankAccount>> bankAccounts(String key) async =>
      emptyBanks
          ? []
          : [
              OrganizationBankAccount({'id': 'B1', 'name': 'Первый'}),
              OrganizationBankAccount(
                  {'id': 'B2', 'name': 'Основной', 'is_default': true}),
            ];
  @override
  Future<PaymentInvoice> create(
      String key, Map<String, dynamic> payload) async {
    sent.add(Map<String, dynamic>.from(jsonDecode(jsonEncode(payload))));
    if (failure != null) throw failure!;
    return invoice;
  }

  @override
  Future<PaymentInvoice> confirm(
      String key, String id, Map<String, dynamic> payload) async {
    confirmations.add(Map<String, dynamic>.from(payload));
    if (failure != null) throw failure!;
    invoice = PaymentInvoice({
      ...invoice.json,
      'status': 'paid',
      'sale_id': 'SALE',
      'paid_at': '2026-09-21T14:30:00Z'
    });
    return invoice;
  }

  @override
  Future<PaymentInvoicePage> list(String key, {int page = 1}) async =>
      PaymentInvoicePage([invoice], page, 1);
  @override
  Future<PaymentInvoice> get(String key, String id) async => invoice;
}

void main() {
  late FakeInvoices api;
  late PosCubit cubit;
  late TestAuth auth;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    api = FakeInvoices();
    sl.registerSingleton<InvoicesRemoteDataSource>(api);
    sl.registerSingleton<CustomersRemoteDataSource>(FakeCustomers());
    auth = TestAuth();
    cubit = PosCubit(EmptyRepo());
    await Future<void>.delayed(Duration.zero);
    cubit.addWithQty(const Product(id: 'P', name: 'Товар', price: 1500), 2);
    cubit.setCustomerForActiveTicket(
        const PosCustomer(id: 'C', name: 'Иван', phone: ''));
  });
  tearDown(() async {
    await cubit.close();
    auth.dispose();
    await sl.reset();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthTokenProvider>.value(
        value: auth,
        child: BlocProvider.value(
            value: cubit,
            child: MaterialApp(
                home: Builder(
                    builder: (ctx) => Scaffold(
                        body: TextButton(
                            onPressed: () => showInvoiceIssueDialog(ctx),
                            child: const Text('Открыть'))))))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('compact invoice searches customers with touch keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester);
    await tester.ensureVisible(find.text('Выбрать покупателя'));
    await tester.tap(find.text('Выбрать покупателя'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
        (w) => w is InvoiceTextField && w.label == 'Поиск покупателя'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('и').last);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Иван').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Иван').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch form creates buyer with legal details and links invoice',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester);
    await tester.tap(find.text('Новый покупатель'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find
          .byWidgetPredicate((w) => w is InvoiceTextField && w.label == label);
      await tester.ensureVisible(field);
      await tester.tap(
          find.descendant(of: field, matching: find.byType(TextFormField)));
      await tester.pumpAndSettle();
      expect(
          find.text('Клавиатура'),
          label == 'ИИН/БИН' || label == 'Телефон (необязательно)'
              ? findsNothing
              : findsOneWidget);
      await tester.enterText(find.byType(TextField).last, value);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
    }

    await fill('Имя или название покупателя', 'Компания');
    await fill('Телефон (необязательно)', '+77011234567');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await fill('ИИН/БИН', '123456789012');
    await fill('Юридическое название', 'ТОО Компания');
    await fill('Юридический адрес', 'Алматы, Абая 1');
    await tester.tap(find.widgetWithText(FilledButton, 'Выставить счёт'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(api.createdCustomers.single['bin'], '123456789012');
    expect(api.createdCustomers.single['legal_address'], 'Алматы, Абая 1');
    expect(api.sent.single['customer_id'], 'NEW');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'issue uses default bank, clears only after success and opens server invoice',
      (tester) async {
    await open(tester);
    expect(find.text('Основной'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Выставить счёт'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(api.sent.single['organization_bank_account_id'], 'B2');
    expect(api.sent.single['customer_id'], 'C');
    expect(api.sent.single['items'][0]['total_price'], 3000);
    expect(cubit.state.items, isEmpty);
    expect(find.text('Счёт № 15'), findsOneWidget);
    expect(find.text('Открыть PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing bank details disable invoice issuance', (tester) async {
    api.emptyBanks = true;
    await open(tester);
    expect(find.text('Не настроены банковские реквизиты организации'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Выставить счёт'))
            .onPressed,
        isNull);
    expect(api.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'network retry after closing dialog preserves exact invoice payload',
      (tester) async {
    api.failure = DioException(
        requestOptions: RequestOptions(path: '/invoices'),
        type: DioExceptionType.receiveTimeout);
    await open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Выставить счёт'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(cubit.state.activeTicket.invoiceCheckout, isNotNull);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    api.failure = null;
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Выставить счёт'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(api.sent, hasLength(2));
    expect(api.sent[1], api.sent[0]);
    expect(cubit.state.items, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'expired issued invoice cannot be confirmed; cancelled has no mutations',
      (tester) async {
    for (final status in ['issued', 'cancelled', 'paid']) {
      api.invoice = PaymentInvoice({
        'id': 'I',
        'status': status,
        'due_at': '2020-01-01',
        'sale_id': status == 'paid' ? 'S' : null
      });
      await tester.pumpWidget(MaterialApp(
          home: InvoiceDetailsDialog(
              invoice: api.invoice, auth: auth, key: ValueKey(status))));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Подтвердить оплату');
      if (status == 'issued') {
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(find.text('Просрочен'), findsOneWidget);
      } else {
        expect(confirm, findsNothing);
        expect(find.text('Отменить счёт'), findsNothing);
      }
      if (status == 'paid') {
        expect(find.text('Связанная продажа'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'confirmation retries identical payment and exposes linked sale on success',
      (tester) async {
    api.failure = DioException(
        requestOptions: RequestOptions(path: '/confirm-payment'),
        type: DioExceptionType.receiveTimeout);
    await tester.pumpWidget(MaterialApp(
        home: InvoiceDetailsDialog(invoice: api.invoice, auth: auth)));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить оплату'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      // The invoice behind the confirmation dialog remains busy.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (attempt == 1) {
        expect(
            find.text(
                'Повторное подтверждение использует сохранённые дату и комментарий.'),
            findsOneWidget);
      }
      await tester.tap(find.text('Деньги поступили'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      api.failure = null;
    }
    expect(api.confirmations, hasLength(2));
    expect(api.confirmations[0], api.confirmations[1]);
    expect(find.text('Оплачен'), findsOneWidget);
    expect(find.text('Связанная продажа'), findsOneWidget);
    expect(find.text('Подтвердить оплату'), findsNothing);
    expect(find.text('Отменить счёт'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'UUID conflict preserves original invoice while displaying server field error',
      (tester) async {
    final request = RequestOptions(path: '/invoices');
    api.failure = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 422, data: {
          'errors': {
            'client_invoice_id': ['Этот идентификатор уже использован']
          }
        }));
    await open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Выставить счёт'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(cubit.state.activeTicket.invoiceCheckout, isNotNull);
    expect(find.text('Этот идентификатор уже использован'), findsOneWidget);
    expect(cubit.state.items, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cash register menu opens invoice history', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthTokenProvider>.value(
        value: auth,
        child: MaterialApp(
            home: Builder(
                builder: (ctx) => Scaffold(
                    body: TextButton(
                        onPressed: () => showPosActionsDialog(ctx),
                        child: const Text('Меню')))))));
    await tester.tap(find.text('Меню'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('СЧЕТА'));
    await tester.pumpAndSettle();
    expect(find.text('Счета на оплату'), findsOneWidget);
    expect(find.text('Счёт № 15'), findsOneWidget);
    expect(find.text('СОЗДАТЬ\nТОВАР'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

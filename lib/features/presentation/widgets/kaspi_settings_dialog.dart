import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:leemon_app/core/service/kaspi_payment_service.dart';
import 'package:leemon_app/core/service/kaspi_terminal.dart';
import 'package:leemon_app/core/service/kaspi_account_binding.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'kaspi_dialog_style.dart';

Future<void> showKaspiSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const KaspiSettingsDialog(),
    );

class KaspiSettingsDialog extends StatefulWidget {
  const KaspiSettingsDialog({super.key, this.terminal, this.loadAccounts});
  final KaspiTerminal? terminal;
  final Future<List<LocalAccount>> Function()? loadAccounts;
  @override
  State<KaspiSettingsDialog> createState() => _KaspiSettingsDialogState();
}

class _KaspiSettingsDialogState extends State<KaspiSettingsDialog> {
  final _host = TextEditingController();
  bool _busy = true, _registering = false;
  String _registeredHost = '';
  List<LocalAccount> _accounts = [];
  String? _accountId;
  bool _enabled = false, _bindingDirty = false;
  String _message = 'Читаем настройки терминала…';
  String _statusTitle = 'Подготовка';
  KaspiStatusTone _tone = KaspiStatusTone.busy;
  KaspiTerminal get _terminal => widget.terminal ?? KaspiTerminal.instance;
  bool get _valid =>
      InternetAddress.tryParse(_host.text)?.type == InternetAddressType.IPv4;
  bool get _addressChanged => _host.text != _registeredHost;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _terminal.initialize();
      final binding = await KaspiAccountBinding.load();
      final accounts = widget.loadAccounts != null
          ? await widget.loadAccounts!()
          : sl.isRegistered<PosSyncService>()
              ? await sl<PosSyncService>().loadAccounts()
              : <LocalAccount>[];
      if (!mounted) return;
      _accounts = accounts
          .where((a) => a.visibleToPos && a.normalizedType == 'bank')
          .toList();
      _enabled = binding.enabled;
      _accountId = _accounts.any((a) => a.id == binding.accountId)
          ? binding.accountId
          : null;
      _host.text = _terminal.host;
      _registeredHost = _terminal.host;
      _statusTitle = _terminal.registered
          ? 'Касса зарегистрирована'
          : 'Подключите терминал';
      _message = _terminal.registered
          ? 'Нажмите «Проверить связь», чтобы убедиться, что терминал готов к оплате.'
          : 'Введите IP-адрес, откройте настройку доступа на терминале и нажмите «Подключить».';
      _tone = KaspiStatusTone.neutral;
    } catch (_) {
      _statusTitle = 'Не удалось загрузить настройки';
      _message = 'Укажите IP-адрес и подключите терминал заново.';
      _tone = KaspiStatusTone.error;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _edit(String token) {
    if (_busy) return;
    final value = _host.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    var start = selection.start;
    final end = selection.end;
    String next;
    if (token == 'clear') {
      next = '';
      start = 0;
    } else if (token == 'backspace') {
      if (start == end && start > 0) start--;
      next = value.text.replaceRange(start, end, '');
    } else {
      next = value.text.replaceRange(start, end, token);
      if (!RegExp(r'^\d{0,3}(\.\d{0,3}){0,3}$').hasMatch(next)) {
        return;
      }
      start += token.length;
    }
    setState(() {
      _host.value = TextEditingValue(
          text: next, selection: TextSelection.collapsed(offset: start));
      _tone = KaspiStatusTone.neutral;
      _statusTitle =
          _addressChanged ? 'Новый адрес терминала' : 'Настройка подключения';
      _message = _addressChanged
          ? 'После ввода адреса нажмите «Подключить» и разрешите доступ на терминале.'
          : 'Можно проверить связь с сохранённым терминалом.';
    });
  }

  Future<void> _run(bool register) async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _registering = register;
      _tone = KaspiStatusTone.busy;
      _statusTitle =
          register ? 'Подтвердите доступ на терминале' : 'Проверяем связь';
      _message = register
          ? 'На экране Kaspi появится запрос Leemon-POS. Нажмите «Разрешить» и дождитесь подключения.'
          : 'Соединяемся с Kaspi по адресу ${_host.text}. Это может занять несколько секунд.';
    });
    try {
      if (register) await _terminal.register(_host.text);
      await _terminal.checkConnection();
      if (!mounted) return;
      _registeredHost = _terminal.host;
      _statusTitle = 'Терминал готов к оплате';
      _message =
          'Связь установлена. Отправка суммы зависит от сохранённой привязки счёта ниже.';
      _tone = KaspiStatusTone.success;
    } catch (e) {
      if (!mounted) return;
      _statusTitle = 'Не удалось подключиться';
      _message = e is KaspiPaymentException
          ? e.message
          : 'Проверьте IP-адрес, подключение к одному роутеру и защиту интеграции на терминале.';
      _tone = KaspiStatusTone.error;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _registering = false;
      });
    }
  }

  Widget _key(String token, {bool compact = false}) => Expanded(
      child: SizedBox(
          height: compact ? 48 : 60,
          child: FilledButton(
            key: ValueKey('kaspi-key-$token'),
            onPressed: _busy ? null : () => _edit(token),
            style: FilledButton.styleFrom(
                backgroundColor:
                    token == '.' ? const Color(0xFFE2F3EC) : Colors.white,
                foregroundColor: token == '.' ? kaspiGreen : kaspiInk,
                disabledBackgroundColor: const Color(0xFFE9EEF2),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE0E7ED)))),
            child: token == 'backspace'
                ? const Icon(Icons.backspace_outlined,
                    size: 25, semanticLabel: 'Удалить символ')
                : Text(token,
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w700)),
          )));

  Widget _input({bool compact = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('IP-адрес терминала',
                style: TextStyle(
                    color: kaspiInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
                controller: _host,
                readOnly: true,
                enabled: !_busy,
                showCursor: true,
                keyboardType: TextInputType.none,
                style: TextStyle(
                    fontSize: compact ? 24 : 27,
                    color: kaspiInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1),
                decoration: InputDecoration(
                    hintText: '192.168.1.100',
                    hintStyle:
                        const TextStyle(color: Color(0xFFADB7C4), fontSize: 25),
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: compact
                        ? IconButton(
                            tooltip: 'Очистить адрес',
                            onPressed: _busy ? null : () => _edit('clear'),
                            icon: const Icon(Icons.close_rounded))
                        : null,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 18, vertical: compact ? 12 : 19),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD9E2EA))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFD9E2EA))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: kaspiGreen, width: 2)))),
            if (!compact) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(
                    _valid
                        ? Icons.check_circle_rounded
                        : Icons.touch_app_outlined,
                    size: 17,
                    color: _valid ? kaspiGreen : kaspiMuted),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(
                        _valid
                            ? 'Адрес введён верно'
                            : 'Четыре числа от 0 до 255 через точку',
                        style:
                            const TextStyle(fontSize: 12, color: kaspiMuted))),
              ]),
            ],
            SizedBox(height: compact ? 12 : 18),
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['.', '0', 'backspace']
            ]) ...[
              Row(children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  _key(row[i], compact: compact),
                ]
              ]),
              SizedBox(height: compact ? 8 : 10),
            ],
            if (!compact)
              SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton.icon(
                      onPressed: _busy ? null : () => _edit('clear'),
                      icon: const Icon(Icons.restart_alt_rounded, size: 20),
                      label: const Text('Очистить адрес'),
                      style:
                          TextButton.styleFrom(foregroundColor: kaspiMuted))),
          ]);

  Widget _step(String number, String title, String description) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFFE5F2EC),
                borderRadius: BorderRadius.circular(9)),
            child: Text(number,
                style: const TextStyle(
                    color: kaspiGreen, fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: kaspiInk, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(
                  color: kaspiMuted, fontSize: 13, height: 1.45)),
        ])),
      ]));

  Future<void> _saveBinding() async {
    if (_busy || (_enabled && _accountId == null)) return;
    setState(() => _busy = true);
    try {
      await KaspiAccountBinding(enabled: _enabled, accountId: _accountId)
          .save();
      if (!mounted) return;
      _bindingDirty = false;
      _statusTitle = 'Настройки сохранены';
      _message = _enabled
          ? 'Сумма отправляется только при оплате через выбранный счёт.'
          : 'Отправка сумм на терминал отключена. Безналичные продажи работают без терминала.';
      _tone = KaspiStatusTone.success;
    } catch (e) {
      if (!mounted) return;
      _statusTitle = 'Не удалось сохранить';
      _message = e is KaspiPaymentException
          ? e.message
          : 'Повторите сохранение настроек.';
      _tone = KaspiStatusTone.error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _binding() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE4EB))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('Отправлять сумму на терминал',
                    style: TextStyle(
                        color: kaspiInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w800))),
            Switch(
                key: const ValueKey('kaspi-binding-enabled'),
                value: _enabled,
                activeThumbColor: kaspiGreen,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _enabled = value;
                          _bindingDirty = true;
                        })),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
              key: ValueKey('kaspi-binding-account-$_accountId'),
              initialValue: _accountId,
              isExpanded: true,
              itemHeight: 56,
              decoration: const InputDecoration(
                  labelText: 'Банковский счёт',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 16)),
              hint: const Text('Выберите счёт'),
              items: _accounts
                  .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name.isEmpty ? 'Счёт ${a.id}' : a.name,
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _busy || !_enabled
                  ? null
                  : (value) => setState(() {
                        _accountId = value;
                        _bindingDirty = true;
                      })),
          const SizedBox(height: 10),
          Text(
              _accounts.isEmpty
                  ? 'Нет банковских счетов. Выполните синхронизацию кассы.'
                  : _bindingDirty
                      ? 'Изменения ещё не сохранены.'
                      : _enabled
                          ? 'Только этот счёт будет отправлять сумму на терминал.'
                          : 'По умолчанию отключено. Название счёта не влияет на подключение.',
              style: const TextStyle(
                  color: kaspiMuted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  key: const ValueKey('kaspi-binding-save'),
                  onPressed: _busy ||
                          !_bindingDirty ||
                          (_enabled && _accountId == null)
                      ? null
                      : _saveBinding,
                  icon: const Icon(Icons.save_outlined, size: 20),
                  label: const Text('Сохранить'),
                  style: kaspiPrimaryButton())),
        ]),
      );

  Widget _guide() => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _binding(),
            const SizedBox(height: 16),
            KaspiStatusCard(
                title: _statusTitle, message: _message, tone: _tone),
            const SizedBox(height: 24),
            const Text('Первое подключение',
                style: TextStyle(
                    color: kaspiInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 17)),
            const SizedBox(height: 18),
            _step('1', 'Одна сеть',
                'Подключите кассу и терминал к одному роутеру.'),
            _step('2', 'Разрешите интеграцию',
                'На Kaspi откройте панель главного кассира, «Защита интеграции», затем «Настроить доступ».'),
            _step('3', 'Подтвердите запрос',
                'Нажмите «Подключить» в кассе, затем «Разрешить» на терминале.'),
            const Divider(height: 24, color: Color(0xFFE1E7ED)),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: kaspiMuted, size: 18),
              SizedBox(width: 9),
              Expanded(
                  child: Text(
                      'Терминал работает только для сохранённого счёта при включённой отправке. При смешанной оплате передаётся только безналичная часть.',
                      style: TextStyle(
                          color: kaspiMuted, fontSize: 12, height: 1.5))),
            ]),
          ]);

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: kaspiSurface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
            width: 920,
            height: math.min(740, MediaQuery.sizeOf(context).height - 48),
            child: Column(children: [
              KaspiDialogHeader(
                  title: 'Kaspi POS',
                  subtitle: 'Подключение платёжного терминала',
                  onClose: _busy ? null : () => Navigator.of(context).pop()),
              Expanded(child: LayoutBuilder(builder: (context, constraints) {
                return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: constraints.maxWidth >= 720
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Expanded(
                                    child: _input(
                                        compact: constraints.maxHeight < 440)),
                                const SizedBox(width: 32),
                                Expanded(child: _guide())
                              ])
                        : Column(children: [
                            _input(compact: constraints.maxHeight < 440),
                            const SizedBox(height: 24),
                            _guide()
                          ]));
              })),
              Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: Color(0xFFE1E7ED)))),
                  child: Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            key: const ValueKey('kaspi-check'),
                            onPressed: _busy ||
                                    !_valid ||
                                    _addressChanged ||
                                    !_terminal.registered
                                ? null
                                : () => _run(false),
                            icon: const Icon(Icons.wifi_find_rounded, size: 21),
                            label: const Text('Проверить связь'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: kaspiInk,
                                minimumSize: const Size(0, 58),
                                textStyle: const TextStyle(
                                    fontFamily: 'NotoSans',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                side: const BorderSide(
                                    color: Color(0xFFDCE4EB))))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton.icon(
                            key: const ValueKey('kaspi-connect'),
                            onPressed:
                                _busy || !_valid ? null : () => _run(true),
                            icon: _busy && _registering
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kaspiMuted))
                                : const Icon(Icons.link_rounded, size: 23),
                            label: Text(_busy && _registering
                                ? 'Подключаем…'
                                : 'Подключить'),
                            style: kaspiPrimaryButton())),
                  ])),
            ])),
      ));
}

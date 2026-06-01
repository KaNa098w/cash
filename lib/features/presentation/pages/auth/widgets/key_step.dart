import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:leemon_app/core/di/api/app_config.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/prod_dev_widget.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeyStep extends StatefulWidget {
  final ThemeData theme;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitted;
  final bool loading;
  final VoidCallback? onSubmit;
  final String? hint;

  const KeyStep({
    super.key,
    required this.theme,
    required this.controller,
    required this.focusNode,
    required this.submitted,
    required this.loading,
    required this.onSubmit,
    this.hint,
  });

  @override
  State<KeyStep> createState() => _KeyStepState();
}

class _KeyStepState extends State<KeyStep> {
  static const _envKey = 'app_environment';

  int _secretTapCount = 0;
  DateTime? _lastSecretTapAt;
  OverlayEntry? _keyboardEntry;

  @override
  void didUpdateWidget(covariant KeyStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.loading && widget.loading) {
      _hideKeyboard();
    }
  }

  @override
  void dispose() {
    _hideKeyboard();
    super.dispose();
  }

  void _ensureKeySelection() {
    final ctrl = widget.controller;
    final selection = ctrl.selection;
    if (selection.isValid) return;

    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
  }

  void _showKeyboard() {
    if (widget.loading) return;
    widget.focusNode.requestFocus();
    _ensureKeySelection();
    if (_keyboardEntry != null) return;

    _keyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => widget.controller,
            onEnter: () {
              if (widget.loading) return;
              widget.onSubmit?.call();
            },
            onClose: _hideKeyboard,
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_keyboardEntry!);
  }

  void _hideKeyboard() {
    _keyboardEntry?.remove();
    _keyboardEntry = null;
  }

  Future<void> _onLeemonTap() async {
    final now = DateTime.now();
    final last = _lastSecretTapAt;
    _lastSecretTapAt = now;

    if (last == null || now.difference(last).inSeconds > 2) {
      _secretTapCount = 1;
    } else {
      _secretTapCount += 1;
    }

    if (_secretTapCount < 10) return;
    _secretTapCount = 0;

    await _showEnvironmentDialog();
  }

  Future<void> _showEnvironmentDialog() async {
    var selected = AppConfig.I.environment;

    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;

            return StatefulBuilder(
              builder: (context, setLocalState) {
                final isProdSelected = selected == AppEnvironment.prod;
                final currentEnvLabel = AppConfig.I.isProd ? 'prod' : 'dev';

                return Dialog(
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.settings_ethernet_rounded,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Выбор окружения',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Переключение API окружения приложения',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.textTheme.bodySmall?.color
                                            ?.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Закрыть',
                                onPressed: () => Navigator.of(ctx).pop(false),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Current env chip / card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: cs.outline.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Текущее окружение: ',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: (AppConfig.I.isProd
                                            ? Colors.red
                                            : Colors.green)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: (AppConfig.I.isProd
                                              ? Colors.red
                                              : Colors.green)
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Text(
                                    currentEnvLabel.toUpperCase(),
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppConfig.I.isProd
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Options
                          EnvOptionTile(
                            title: 'Production',
                            subtitle: 'Боевой сервер (реальные данные)',
                            badgeText: 'prod',
                            badgeColor: Colors.red,
                            icon: Icons.verified_rounded,
                            selected: selected == AppEnvironment.prod,
                            onTap: () => setLocalState(
                                () => selected = AppEnvironment.prod),
                          ),
                          const SizedBox(height: 10),
                          EnvOptionTile(
                            title: 'Development',
                            subtitle: 'Тестовый сервер (разработка / проверка)',
                            badgeText: 'dev',
                            badgeColor: Colors.green,
                            icon: Icons.build_circle_rounded,
                            selected: selected == AppEnvironment.dev,
                            onTap: () => setLocalState(
                                () => selected = AppEnvironment.dev),
                          ),

                          const SizedBox(height: 14),

                          // Warning block
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  (isProdSelected ? Colors.orange : cs.primary)
                                      .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: (isProdSelected
                                        ? Colors.orange
                                        : cs.primary)
                                    .withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isProdSelected
                                      ? Icons.warning_amber_rounded
                                      : Icons.tips_and_updates_outlined,
                                  size: 18,
                                  color: isProdSelected
                                      ? Colors.orange.shade800
                                      : cs.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isProdSelected
                                        ? 'Внимание: в PROD могут использоваться реальные данные. Убедись, что это нужное окружение.'
                                        : 'DEV подходит для тестирования, отладки и проверки новых изменений.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.35,
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Actions
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Отмена'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  icon:
                                      const Icon(Icons.check_rounded, size: 18),
                                  label: const Text('Применить'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _envKey,
      selected == AppEnvironment.dev ? 'dev' : 'prod',
    );

    AppConfig.init(env: selected);
    sl<Dio>().options.baseUrl = AppConfig.I.baseUrl;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Окружение переключено на ${selected == AppEnvironment.dev ? 'dev' : 'prod'}',
        ),
      ),
    );
  }

  /// Красивый пункт выбора окружения

  @override
  Widget build(BuildContext context) {
    final showError = widget.submitted && widget.controller.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Подключение кассы',
          style: widget.theme.textTheme.headlineSmall!
              .copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Введи ключ кассы. Затем выбери пользователя и введи PIN.',
          style: widget.theme.textTheme.bodyMedium!
              .copyWith(color: Colors.black54),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.hint!,
            style: widget.theme.textTheme.bodySmall!
                .copyWith(color: Colors.black45),
          ),
        ],
        const SizedBox(height: 22),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: !widget.loading,
          onTap: _ensureKeySelection,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.loading ? null : widget.onSubmit?.call(),
          decoration: InputDecoration(
            labelText: 'Ключ кассы',
            hintText: 'Введите ключ вашей кассы',
            errorText: showError ? 'Ключ обязателен' : null,
            suffixIcon: IconButton(
              tooltip: 'Клавиатура',
              onPressed: widget.loading ? null : _showKeyboard,
              icon: const Icon(Icons.keyboard_alt_outlined),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: widget.loading ? null : widget.onSubmit,
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Продолжить',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Text(
              '© ${DateTime.now().year} ',
              style: widget.theme.textTheme.bodySmall!
                  .copyWith(color: Colors.black54),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onLeemonTap,
              child: Text(
                'Leemon',
                style: widget.theme.textTheme.bodySmall!.copyWith(
                  color: Colors.black54,
                ),
              ),
            ),
            Text(
              '. Все права защищены.',
              style: widget.theme.textTheme.bodySmall!
                  .copyWith(color: Colors.black54),
            ),
          ],
        ),
      ],
    );
  }
}

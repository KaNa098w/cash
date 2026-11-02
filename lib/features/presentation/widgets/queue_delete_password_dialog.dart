import 'package:flutter/material.dart';

Future<bool> confirmQueueDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const QueueDeletePasswordDialog(),
    ) ==
    true;

class QueueDeletePasswordDialog extends StatefulWidget {
  const QueueDeletePasswordDialog({super.key});

  @override
  State<QueueDeletePasswordDialog> createState() => _PasswordState();
}

class _PasswordState extends State<QueueDeletePasswordDialog> {
  final _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _key(String key) {
    setState(() {
      _invalid = false;
      final value = _controller.text;
      if (key == '⌫') {
        _controller.text =
            value.isEmpty ? '' : value.substring(0, value.length - 1);
      } else if (key == 'C') {
        _controller.clear();
      } else if (value.length < 4) {
        _controller.text = value + key;
      }
    });
  }

  void _submit() {
    if (_controller.text == '2020') {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _invalid = true;
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Пароль для удаления'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                readOnly: true,
                obscureText: true,
                enableInteractiveSelection: false,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 10),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '••••',
                  errorText: _invalid ? 'Неверный пароль' : null,
                ),
              ),
              const SizedBox(height: 16),
              for (final row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['C', '0', '⌫']
              ])
                Row(children: [
                  for (final key in row)
                    Expanded(
                        child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () => _key(key),
                            child:
                                Text(key, style: const TextStyle(fontSize: 24)),
                          )),
                    )),
                ]),
            ],
          )),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: _controller.text.length == 4 ? _submit : null,
              child: const Text('Удалить')),
        ],
      );
}

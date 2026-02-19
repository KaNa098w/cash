import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LiveDateText extends StatefulWidget {
  const LiveDateText({super.key});

  @override
  State<LiveDateText> createState() => _LiveDateTextState();
}

class _LiveDateTextState extends State<LiveDateText> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();

    // один раз инициализируем локаль (лучше вынести в main(), но так тоже ок)

    // обновляем каждую минуту, чтобы время/дата были актуальны
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat("d MMMM | EEEE", 'ru_RU').format(_now);
    // если нужно ещё и время: HH:mm
    // final dateStr = DateFormat("d MMMM | EEEE, HH:mm", 'ru_RU').format(_now);

    return Text(
      dateStr,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
      ),
    );
  }
}

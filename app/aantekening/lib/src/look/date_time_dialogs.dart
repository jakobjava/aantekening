/// Asking for a day, or a time of day, on glass as every dialog is.
library;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'motion.dart';

/// Asks for a day, from [initial]: a click on one picks it.
Future<DateTime?> askForDate(BuildContext context, DateTime initial) =>
    showAppDialog<DateTime>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('Date'),
        content: SizedBox(
          // As large as the calendar lays itself out: a heading over six
          // weeks and the days' names.
          width: 330,
          height: 346,
          child: CalendarDatePicker(
            initialDate: initial,
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
            onDateChanged: (day) => Navigator.of(context).pop(day),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

/// Asks for a time of day, from [initial], typed as hours and minutes.
Future<TimeOfDay?> askForTime(BuildContext context, TimeOfDay initial) =>
    showAppDialog<TimeOfDay>(
      context: context,
      builder: (context) => _TimeDialog(initial: initial),
    );

class _TimeDialog extends StatefulWidget {
  const _TimeDialog({required this.initial});

  final TimeOfDay initial;

  @override
  State<_TimeDialog> createState() => _TimeDialogState();
}

class _TimeDialogState extends State<_TimeDialog> {
  late final TextEditingController _typed = TextEditingController(
    text: _shown(widget.initial),
  );

  bool _wrong = false;

  static String _shown(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// The time [typed] says — "9:05", "09.05" or "0905" — or null if it is
  /// none.
  static TimeOfDay? parse(String typed) {
    final match = RegExp(r'^(\d{1,2})[:.]?(\d{2})$').firstMatch(typed.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _finish() {
    final time = parse(_typed.text);
    if (time == null) {
      setState(() => _wrong = true);
      return;
    }
    Navigator.of(context).pop(time);
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassDialog(
    title: const Text('Time'),
    content: SizedBox(
      width: 200,
      child: TextField(
        controller: _typed,
        autofocus: true,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          hintText: 'HH:MM',
          errorText: _wrong ? 'Hours and minutes, as 14:30' : null,
        ),
        onChanged: (_) {
          if (_wrong) setState(() => _wrong = false);
        },
        onSubmitted: (_) => _finish(),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _finish, child: const Text('Set')),
    ],
  );
}

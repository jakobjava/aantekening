/// What the AI's pages share, small and of no page in particular: when
/// something was, what a conversation is called, asking to go on or for a
/// name, and why a sound would not play.
library;

import 'dart:io';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';

import '../look/glass.dart';
import '../look/motion.dart';

/// When [millis] was, as a person says it: "today", "3 days ago".
String whenOf(int millis) {
  final then = DateTime.fromMillisecondsSinceEpoch(millis);
  final days = DateTime.now().difference(then).inDays;
  return switch (days) {
    0 => 'today',
    1 => 'yesterday',
    < 30 => '$days days ago',
    _ =>
      '${then.year}-${then.month.toString().padLeft(2, '0')}-'
          '${then.day.toString().padLeft(2, '0')}',
  };
}

/// What a conversation is called in the lists: its title, or what it is.
String threadTitle(AiThread thread) =>
    thread.title.isEmpty ? 'Conversation' : thread.title;

/// Why sound could not be played, from [error], and what to do about it:
/// on Linux, a WAV is read by GStreamer's good plugins, which not every
/// system has.
String playbackTrouble(Object error) =>
    'The sound could not be played'
    '${Platform.isLinux ? ' — on Linux it needs GStreamer’s good plugins: '
              'install gst-plugins-good (Arch) or '
              'gstreamer1.0-plugins-good (Debian, Ubuntu)' : ''}. ($error)';

/// Asks whether to go on with what [title] asks, [body] saying what
/// follows.
Future<bool> confirmStep(
  BuildContext context,
  String title,
  String body,
) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Go on'),
          ),
        ],
      ),
    ) ??
    false;

/// Asks for a new name for something kept, [current] to start from.
Future<String?> askName(BuildContext context, String current) =>
    showAppDialog<String>(
      context: context,
      builder: (context) => _NameDialog(current: current),
    );

/// The dialog behind [askName]: its field let go of with it, once it has
/// gone, not as soon as it is answered.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.current});

  final String current;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassDialog(
    title: const Text('Rename'),
    content: TextField(
      controller: _name,
      autofocus: true,
      onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_name.text.trim()),
        child: const Text('Rename'),
      ),
    ],
  );
}

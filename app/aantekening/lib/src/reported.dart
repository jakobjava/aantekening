/// What the person asks for done so that, if it cannot be, they are told
/// why, rather than left to find it in errors.log.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'error_log.dart';
import 'look/motion.dart';

/// Does [action], which the person asked for in [context]; if it fails,
/// says so along the foot of the window — [failed], what could not be
/// done, then why — and notes it in the error log.
///
/// Where to say it is found at once, so it is said even once [context]
/// has gone: a dialog it asked through closed, the picker taken away.
Future<void> runReported(
  BuildContext context,
  String failed,
  FutureOr<void> Function() action,
) => _run(
  context.mounted ? ScaffoldMessenger.maybeOf(context) : null,
  failed,
  action,
);

/// [action] as a command for a menu or a key, done as [runReported] does
/// it, and saying what went wrong where [context] would have as the
/// command was made.
VoidCallback reportedly(
  BuildContext context,
  String failed,
  FutureOr<void> Function() action,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return () => unawaited(_run(messenger, failed, action));
}

Future<void> _run(
  ScaffoldMessengerState? messenger,
  String failed,
  FutureOr<void> Function() action,
) async {
  try {
    await action();
  } on Object catch (error, stack) {
    ErrorLog.note('$error', stack, context: failed);
    if (messenger != null && messenger.mounted) {
      messenger.showMessage('$failed: $error');
    }
  }
}

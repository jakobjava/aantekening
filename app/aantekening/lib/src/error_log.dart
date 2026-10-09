/// What went wrong, kept in a file of its own beside the app: for a report
/// of a problem to say what happened, where the window could only say that
/// something did.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Notes every error nothing else caught — in building or drawing the
/// window, or in work done meanwhile — with when it happened, in
/// `logs/errors.log` in the app's own folder. Nothing in it leaves the
/// computer.
abstract final class ErrorLog {
  /// The file errors are noted in, once its folder is known.
  static File? file;

  /// How large the file grows before its oldest half goes.
  static const int _most = 1 << 20;

  /// What happened before the file was known, noted once it is.
  static final List<String> _waiting = <String>[];

  /// Starts noting errors, passing each on as before.
  static void install() {
    final before = FlutterError.onError;
    FlutterError.onError = (details) {
      note(
        details.exceptionAsString(),
        details.stack,
        context: details.context?.toDescription(),
      );
      before?.call(details);
    };
    final uncaught = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      note('$error', stack, context: 'uncaught');
      return uncaught?.call(error, stack) ?? false;
    };
  }

  /// Notes errors in the folder [support] from now on, with those noted
  /// before it was known.
  static void keepIn(String support) {
    file = File(p.join(support, 'logs', 'errors.log'));
    final waiting = List.of(_waiting);
    _waiting.clear();
    waiting.forEach(_write);
  }

  /// Notes [error], with the [stack] it came from and the [context] it
  /// came about in.
  static void note(String error, StackTrace? stack, {String? context}) {
    final entry = StringBuffer()
      ..writeln(
        '── ${DateTime.now().toIso8601String()}'
        '${context == null ? '' : '  $context'}',
      )
      ..writeln(error.trim());
    if (stack != null) {
      entry.writeln(stack.toString().trim().split('\n').take(40).join('\n'));
    }
    if (file == null) {
      if (_waiting.length < 50) _waiting.add(entry.toString());
      return;
    }
    _write(entry.toString());
  }

  static void _write(String entry) {
    final log = file;
    if (log == null) return;
    // Noting an error must never be one: whatever goes wrong here is let
    // go of.
    try {
      log.parent.createSync(recursive: true);
      if (log.existsSync() && log.lengthSync() > _most) {
        final kept = log.readAsStringSync();
        log.writeAsStringSync(kept.substring(kept.length - _most ~/ 2));
      }
      log.writeAsStringSync('$entry\n', mode: FileMode.append, flush: true);
    } on Object {
      // Not noted.
    }
  }
}

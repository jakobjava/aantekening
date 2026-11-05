/// What went wrong, kept in a file of its own beside the app: for a report
/// of a problem to say what happened, where the window could only say that
/// something did.
library;

import 'dart:convert';
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

  /// The error noted last, with where it came about; when; and how many
  /// times it has come again since. An error made in every frame is
  /// counted, and noted again with its count only every [_quiet], rather
  /// than written sixty times a second.
  static String? _last;
  static DateTime _lastAt = DateTime(0);
  static int _again = 0;
  static const Duration _quiet = Duration(seconds: 10);

  /// How long the file is, as far as this app has written it.
  static int? _length;

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
    _length = null;
    final waiting = List.of(_waiting);
    _waiting.clear();
    waiting.forEach(_write);
  }

  /// Notes [error], with the [stack] it came from and the [context] it
  /// came about in.
  static void note(String error, StackTrace? stack, {String? context}) {
    final now = DateTime.now();
    final what = '$context\n$error';
    if (what == _last && now.difference(_lastAt) < _quiet) {
      _again++;
      return;
    }
    final entry = StringBuffer();
    if (_again > 0) {
      entry.writeln('── the error before came $_again more times');
    }
    _last = what;
    _lastAt = now;
    _again = 0;
    entry.writeln(
      '── ${now.toIso8601String()}'
      '${context == null ? '' : '  $context'}',
    );
    entry.writeln(error.trim());
    if (stack != null) {
      entry.writeln(stack.toString().trim().split('\n').take(40).join('\n'));
    }
    if (file == null) {
      if (_waiting.length < 50) _waiting.add(entry.toString());
      return;
    }
    _write(entry.toString(), flush: context == 'uncaught');
  }

  /// Writes [entry] at the end of the file — on the disk before going on,
  /// if [flush], as an error nothing caught is, which may be the last.
  static void _write(String entry, {bool flush = false}) {
    final log = file;
    if (log == null) return;
    // Noting an error must never be one: whatever goes wrong here is let
    // go of.
    try {
      var length = _length;
      if (length == null) {
        log.parent.createSync(recursive: true);
        length = log.existsSync() ? log.lengthSync() : 0;
      }
      if (length > _most) {
        // From the first whole line of its newer half.
        final kept = log.readAsStringSync();
        final half = kept.length - _most ~/ 2;
        final line = kept.indexOf('\n', half);
        final newer = kept.substring(line < 0 ? half : line + 1);
        log.writeAsStringSync(newer);
        length = utf8.encode(newer).length;
      }
      final written = '$entry\n';
      log.writeAsStringSync(written, mode: FileMode.append, flush: flush);
      _length = length + utf8.encode(written).length;
    } on Object {
      // Not noted.
    }
  }
}

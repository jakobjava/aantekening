import 'dart:io';

import 'package:aantekening/src/error_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('notes errors, those before its file was known too, and keeps the '
      'newest', () {
    final folder = Directory.systemTemp.createTempSync('error_log_');
    addTearDown(() {
      ErrorLog.file = null;
      folder.deleteSync(recursive: true);
    });
    ErrorLog.note('Before the folder', StackTrace.current, context: 'start');
    ErrorLog.keepIn(folder.path);
    ErrorLog.note('After it', null);
    final log = File(p.join(folder.path, 'logs', 'errors.log'));
    final text = log.readAsStringSync();
    expect(text, contains('Before the folder'));
    expect(text, contains('start'));
    expect(text.indexOf('After it'), greaterThan(text.indexOf('Before')));

    // Grown past its size, its oldest half goes.
    for (var i = 0; i < 3000; i++) {
      ErrorLog.note('Error $i ${'x' * 400}', null);
    }
    expect(log.lengthSync(), lessThan(1100 * 1024));
    expect(log.readAsStringSync(), contains('Error 2999'));
    expect(log.readAsStringSync(), isNot(contains('Before the folder')));
  });
}

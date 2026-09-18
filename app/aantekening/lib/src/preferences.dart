/// Settings that belong to this person on this machine rather than to their
/// notes, such as how the ribbon is arranged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A few values kept in a small JSON file beside the workspace, not in it, so
/// copying a workspace to another machine carries notes and nothing else.
class Preferences {
  Preferences._(this._file, this._values);

  /// Preferences that are not written anywhere: for tests, and for when the
  /// file cannot be used.
  Preferences.inMemory([Map<String, Object?>? values])
    : this._(null, <String, Object?>{...?values});

  /// Reads [file], or starts empty if it is missing or unreadable.
  static Future<Preferences> open(File file) async {
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) {
          return Preferences._(file, Map<String, Object?>.of(decoded));
        }
      }
    } on Object {
      // A damaged file must not stop the app; it is rewritten on the next
      // change.
    }
    return Preferences._(file, <String, Object?>{});
  }

  final File? _file;
  final Map<String, Object?> _values;
  Future<void> _writing = Future<void>.value();

  Object? operator [](String key) => _values[key];

  /// Sets [key], or removes it with null, and writes the file.
  ///
  /// Writes happen one after another, each replacing the file whole, so a
  /// crash mid-write leaves the previous version rather than half of one.
  Future<void> set(String key, Object? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    final file = _file;
    if (file == null) return Future<void>.value();
    final contents = const JsonEncoder.withIndent('  ').convert(_values);
    return _writing = _writing.then((_) => _write(file, contents));
  }

  static Future<void> _write(File file, String contents) async {
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(file.path);
    } on Object {
      // Preferences are a convenience; failing to save one is not worth
      // interrupting anyone over.
    }
  }
}

/// This machine's preferences.
final preferencesProvider = FutureProvider<Preferences>((ref) async {
  try {
    final override = Platform.environment['AANTEKENING_HOME'];
    final directory = override != null && override.isNotEmpty
        ? override
        : (await getApplicationSupportDirectory()).path;
    return await Preferences.open(File(p.join(directory, 'preferences.json')));
  } on Object {
    return Preferences.inMemory();
  }
});

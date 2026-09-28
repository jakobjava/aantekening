/// The typefaces text on a page can be set in.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The typefaces offered for text: those that come with the app, and those
/// installed on this computer.
abstract final class Typefaces {
  /// Those the app brings, which look the same on every computer.
  static const List<String> bundled = <String>[
    'IBM Plex Sans',
    'IBM Plex Mono',
    'Carlito',
  ];

  /// Those offered where the ones installed cannot be listed: the ones
  /// most computers have, or have one drawn to the same measure.
  static const List<String> common = <String>[
    'Arial',
    'Calibri',
    'Cambria',
    'Comic Sans MS',
    'Consolas',
    'Courier New',
    'Georgia',
    'Segoe UI',
    'Times New Roman',
    'Verdana',
  ];

  /// The families installed on this computer, in alphabetical order, or
  /// null where they cannot be listed.
  static Future<List<String>?> installed() async {
    try {
      if (Platform.isLinux) {
        final listed = await Process.run('fc-list', <String>[':', 'family']);
        if (listed.exitCode == 0) return fromFontconfig('${listed.stdout}');
      } else if (Platform.isWindows) {
        final machine = await Process.run('reg', <String>['query', _fontKey]);
        final user = await Process.run('reg', <String>[
          'query',
          'HKCU\\${_fontKey.substring('HKLM\\'.length)}',
        ]);
        return fromRegistry('${machine.stdout}\n${user.stdout}');
      }
    } on ProcessException {
      // Nothing to list them with: the common ones are offered instead.
    }
    return null;
  }

  static const String _fontKey =
      r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts';

  /// The families in what `fc-list : family` prints: each font's first
  /// name for its family, hidden ones left out.
  static List<String> fromFontconfig(String listing) => _sorted(<String>[
    for (final line in listing.split('\n'))
      line.split(',').first.replaceAll(r'\', '').trim(),
  ]);

  /// The families in what `reg query` prints of the fonts installed: each
  /// font file's name without its format or style, a collection's names
  /// each on its own.
  static List<String> fromRegistry(String listing) => _sorted(<String>[
    for (final line in listing.split('\n'))
      if (_registryName.firstMatch(line) case final match?)
        for (final name in match[1]!.split(' & ')) _withoutStyle(name),
  ]);

  static final RegExp _registryName = RegExp(
    r'^\s+(.+?)\s+\((?:TrueType|OpenType|All res)\)\s+REG_',
  );

  /// [name] without the styles a font file of the family adds to it.
  static String _withoutStyle(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    while (words.length > 1 && _styles.contains(words.last.toLowerCase())) {
      words.removeLast();
    }
    return words.join(' ');
  }

  static const Set<String> _styles = <String>{
    'regular',
    'italic',
    'oblique',
    'bold',
    'semibold',
    'demibold',
    'light',
    'semilight',
    'extralight',
    'thin',
    'medium',
    'black',
    'heavy',
  };

  static List<String> _sorted(List<String> families) {
    final unique = <String>{
      for (final family in families)
        if (family.isNotEmpty && !family.startsWith('.')) family,
    }.toList();
    return unique..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

/// The families installed on this computer, read once, or null where they
/// cannot be listed.
final installedTypefacesProvider = FutureProvider<List<String>?>(
  (ref) => Typefaces.installed(),
);

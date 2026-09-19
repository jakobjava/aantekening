/// The spelling dictionaries on this machine: those that can be downloaded,
/// and those downloaded or added from files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// A language whose dictionary can be downloaded, with the SHA-256 of each
/// of its files, so nothing but those files is ever installed.
@immutable
class CatalogDictionary {
  const CatalogDictionary(
    this.code,
    this.name, {
    required this.affixHash,
    required this.wordListHash,
    required this.licenseHash,
  });

  /// The language's tag, as the dictionary is filed under.
  final String code;
  final String name;
  final String affixHash;
  final String wordListHash;
  final String licenseHash;
}

/// The dictionaries offered for download: Hunspell dictionaries collected
/// by wooorm/dictionaries, fetched from one fixed commit of it.
///
/// A language is added by giving its tag there and the hashes of its files
/// at that commit.
abstract final class DictionaryCatalog {
  static const String _source =
      'https://raw.githubusercontent.com/wooorm/dictionaries/'
      '8cfea406b505e4d7df52d5a19bce525df98c54ab/dictionaries';

  static const List<CatalogDictionary> languages = <CatalogDictionary>[
    CatalogDictionary(
      'en-GB',
      'English (British)',
      affixHash:
          '8ae1f19d4840d957728ad90555d5a8dff6cc5c046279c95ff0c00fc0a0136c7b',
      wordListHash:
          '869fe17ba4ee4b5401c60a666ee2d6a3dcc237f460b7294435df1cc6a799aa57',
      licenseHash:
          '81b644347b40804c25811267efbea024a30b2bb1642fefa9c9c50f7b0bbcb67f',
    ),
    CatalogDictionary(
      'nl',
      'Dutch',
      affixHash:
          'b430d9cf5f4170d9e5072397927e1402b34aa877d1f4c8fbc00dab6370d87312',
      wordListHash:
          'be192fdc36efd39dde0fb9a5a113143e0a906782e81ed68a74a710edced378d0',
      licenseHash:
          'fd9e95c360245eab3c388885062820754785faa4123964994cfdecb950b71948',
    ),
    CatalogDictionary(
      'de',
      'German',
      affixHash:
          '57fdd1b16aac2131003c91e0cf2a488becb970382a402a9ce089307301cb3ef0',
      wordListHash:
          'b5c781a0cf6f285fb6b9b8ab02fbea104b987104a1efdda8a835837e89e3ec77',
      licenseHash:
          '03abf202c6e207d41f054083cafccbb174a30f6b330ea8dba3aeef0a279cb83e',
    ),
  ];

  static Uri _uriOf(CatalogDictionary dictionary, String file) =>
      Uri.parse('$_source/${dictionary.code}/$file');
}

/// A dictionary on this machine.
@immutable
class InstalledDictionary {
  const InstalledDictionary(this.code, this.name, this.files);

  final String code;
  final String name;
  final DictionaryFiles files;
}

/// A dictionary that could not be installed, and why.
class DictionaryException implements Exception {
  const DictionaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The folder the dictionaries are kept in, one folder each, named by its
/// code: the affix file, the word list, their licence if they came with
/// one, and the name to show.
class DictionaryFolder {
  const DictionaryFolder(this.directory);

  final Directory directory;

  static const String _affixFile = 'index.aff';
  static const String _wordList = 'index.dic';
  static const String _license = 'license';
  static const String _about = 'dictionary.json';
  static const String _partial = '.partial';

  /// The dictionaries installed, by name.
  Future<List<InstalledDictionary>> list() async {
    if (!await directory.exists()) return const <InstalledDictionary>[];
    final installed = <InstalledDictionary>[];
    await for (final entry in directory.list()) {
      // One still being written, or left half written, is not installed.
      if (entry is! Directory || entry.path.endsWith(_partial)) continue;
      final dictionary = await _read(entry);
      if (dictionary != null) installed.add(dictionary);
    }
    return installed..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Downloads [dictionary] with [client], checking each file against its
  /// hash before installing any of them.
  Future<InstalledDictionary> download(
    CatalogDictionary dictionary,
    http.Client client,
  ) async {
    Future<List<int>> fetch(String file, String hash) async {
      final uri = DictionaryCatalog._uriOf(dictionary, file);
      final http.Response response;
      try {
        response = await client.get(uri);
      } on Object catch (error) {
        throw DictionaryException(
          'The ${dictionary.name} dictionary could not be downloaded: $error',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw DictionaryException(
          'The ${dictionary.name} dictionary could not be downloaded: '
          'the server answered ${response.statusCode}.',
        );
      }
      if (sha256.convert(response.bodyBytes).toString() != hash) {
        throw DictionaryException(
          'The ${dictionary.name} dictionary that was downloaded is not the '
          'one expected, so it was not installed.',
        );
      }
      return response.bodyBytes;
    }

    return _install(
      dictionary.code,
      dictionary.name,
      affixFile: await fetch(_affixFile, dictionary.affixHash),
      wordList: await fetch(_wordList, dictionary.wordListHash),
      license: await fetch(_license, dictionary.licenseHash),
    );
  }

  /// Installs the dictionary in [affixFile] and [wordList], files in
  /// Hunspell's format such as LibreOffice uses, named after them.
  Future<InstalledDictionary> import(String affixFile, String wordList) async {
    final affixes = await File(affixFile).readAsBytes();
    final words = await File(wordList).readAsBytes();
    // A word list starts with the number of words in it, after a byte order
    // mark if it has one.
    final start = String.fromCharCodes(words.take(64)).replaceFirst('ï»¿', '');
    final count = const LineSplitter().convert(start).firstOrNull?.trim();
    if (count == null || int.tryParse(count) == null) {
      throw DictionaryException(
        '${p.basename(wordList)} is not the word list of a Hunspell '
        'dictionary.',
      );
    }
    final name = p.basenameWithoutExtension(affixFile);
    return _install(
      'file-${name.replaceAll(RegExp(r'[^\w-]'), '_')}',
      name,
      affixFile: affixes,
      wordList: words,
    );
  }

  /// Removes the dictionary filed under [code].
  Future<void> remove(String code) async {
    final folder = Directory(p.join(directory.path, code));
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  /// Writes a dictionary's files beside its folder and then puts them in
  /// its place, so a dictionary is never left half written.
  Future<InstalledDictionary> _install(
    String code,
    String name, {
    required List<int> affixFile,
    required List<int> wordList,
    List<int>? license,
  }) async {
    final folder = Directory(p.join(directory.path, code));
    final writing = Directory('${folder.path}$_partial');
    if (await writing.exists()) await writing.delete(recursive: true);
    await writing.create(recursive: true);
    await File(p.join(writing.path, _affixFile)).writeAsBytes(affixFile);
    await File(p.join(writing.path, _wordList)).writeAsBytes(wordList);
    if (license != null) {
      await File(p.join(writing.path, _license)).writeAsBytes(license);
    }
    await File(p.join(writing.path, _about))
        .writeAsString(jsonEncode(<String, Object?>{'name': name}));
    if (await folder.exists()) await folder.delete(recursive: true);
    await writing.rename(folder.path);
    return (await _read(folder))!;
  }

  Future<InstalledDictionary?> _read(Directory folder) async {
    final affixFile = File(p.join(folder.path, _affixFile));
    final wordList = File(p.join(folder.path, _wordList));
    final about = File(p.join(folder.path, _about));
    if (!await affixFile.exists() ||
        !await wordList.exists() ||
        !await about.exists()) {
      return null;
    }
    final code = p.basename(folder.path);
    String name = code;
    try {
      if (jsonDecode(await about.readAsString()) case {
        'name': final String saved,
      }) {
        name = saved;
      }
    } on FormatException {
      // The code serves as its name.
    }
    return InstalledDictionary(code, name, (
      affixFile: affixFile.path,
      wordList: wordList.path,
    ));
  }
}

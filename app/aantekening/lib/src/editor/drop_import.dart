/// What is dropped on a page from outside the app: files from a file
/// manager, pictures from a browser, text from anywhere.
library;

import 'dart:convert';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../files/import_flow.dart' show importers;
import 'media_import.dart';

/// One thing dropped on a page, read as what it becomes there.
sealed class Dropped {
  const Dropped();
}

/// Pictures — GIFs among them, which play — or a PDF's pages.
final class DroppedMedia extends Dropped {
  const DroppedMedia(this.items, {required this.printout});

  final List<BlockEmbed> items;

  /// Whether they are a PDF's pages, which ask where they go.
  final bool printout;
}

/// Text: dragged out of something, a text file's, or a LaTeX document's,
/// its formulas typeset.
final class DroppedText extends Dropped {
  const DroppedText(this.blocks);

  final List<TextBlock> blocks;
}

/// Notes from another program, read as an import of them is.
final class DroppedNotes extends Dropped {
  const DroppedNotes(this.importer, this.paths);

  final NotesImporter importer;
  final List<String> paths;
}

/// A file of any other kind, attached: shown as its name, and opened with
/// whatever opens it.
final class DroppedFile extends Dropped {
  const DroppedFile(this.embed);

  final BlockEmbed embed;
}

/// Reads what was dropped on a page: each of [paths] — a file, or the
/// address of one on the web — or else [text], dragged by itself. What
/// cannot be read is said in [failures], and left out.
///
/// Notes from one program dropped together are read as one import.
Future<List<Dropped>> readDropped(
  AantekeningStore store, {
  required List<String> paths,
  String? text,
  required http.Client client,
  List<String>? failures,
}) async {
  final dropped = <Dropped>[];
  final notes = <NotesImporter, List<String>>{};
  for (final path in paths) {
    try {
      final web = Uri.tryParse(path);
      if (web != null && (web.scheme == 'http' || web.scheme == 'https')) {
        dropped.add(await _fromWeb(store, web, client));
        continue;
      }
      if (await FileSystemEntity.isDirectory(path)) {
        failures?.add('${p.basename(path)} is a folder');
        continue;
      }
      if (_notesImporter(path) case final importer?) {
        (notes[importer] ??= <String>[]).add(path);
        continue;
      }
      dropped.add(await _fromFile(store, File(path)));
    } on Object catch (error) {
      failures?.add('${p.basename(path)}: $error');
    }
  }
  for (final MapEntry(key: importer, value: paths) in notes.entries) {
    dropped.add(DroppedNotes(importer, paths));
  }
  if (paths.isEmpty && text != null && text.trim().isNotEmpty) {
    dropped.add(DroppedText(_plain(text)));
  }
  return dropped;
}

/// The importer that reads notes from the file at [path], if it holds
/// another program's: LaTeX is typeset where it is dropped instead, and a
/// zip file attached.
NotesImporter? _notesImporter(String path) {
  final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (extension == 'tex' || extension == 'zip') return null;
  for (final importer in importers) {
    if (importer.source != ImportSource.folder &&
        importer.extensions.contains(extension)) {
      return importer;
    }
  }
  return null;
}

/// The extensions of text files, dropped as their text.
const Set<String> _textFiles = <String>{'.txt', '.md', '.markdown', '.text'};

Future<Dropped> _fromFile(AantekeningStore store, File file) async {
  final extension = p.extension(file.path).toLowerCase();
  if (extension == '.tex') {
    final source = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return DroppedText(LatexText.read(source).blocks);
  }
  if (_textFiles.contains(extension)) {
    final plain = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return DroppedText(_plain(plain));
  }
  final mimeType = AssetStore.mimeTypeForPath(file.path);
  if (mimeType == 'application/pdf' || MediaImport.isPicture(mimeType)) {
    return DroppedMedia(
      await MediaImport.importFile(store, file),
      printout: mimeType == 'application/pdf',
    );
  }
  final name = p.basename(file.path);
  final asset = await store.assets.importFile(file, name: name);
  return DroppedFile(
    BlockEmbed(
      kind: EmbedKind.file,
      assetId: asset.id,
      width: _fileSize.width,
      height: _fileSize.height,
      name: name,
    ),
  );
}

/// How large an attached file is shown: as a line of text naming it.
const ({double width, double height}) _fileSize = (width: 240, height: 48);

/// A picture or PDF from the web, fetched; anything else there, its
/// address as text.
Future<Dropped> _fromWeb(
  AantekeningStore store,
  Uri address,
  http.Client client,
) async {
  final response = await client
      .get(address)
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw HttpException('the web answered ${response.statusCode}');
  }
  final bytes = response.bodyBytes;
  final name = address.pathSegments.isEmpty
      ? 'picture'
      : address.pathSegments.last;
  final mimeType = mimeTypeOf(bytes, name: name);
  if (mimeType != 'application/pdf' && !MediaImport.isPicture(mimeType)) {
    return DroppedText(<TextBlock>[TextBlock.plain(address.toString())]);
  }
  return DroppedMedia(
    await MediaImport.importBytes(store, bytes, name: name),
    printout: mimeType == 'application/pdf',
  );
}

/// [text] as lines of plain text, as pasted.
List<TextBlock> _plain(String text) => <TextBlock>[
  for (final line in text.replaceAll('\r\n', '\n').trimRight().split('\n'))
    TextBlock.plain(line),
];

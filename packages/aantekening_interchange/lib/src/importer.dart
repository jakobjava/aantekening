/// Reading notes kept by other programs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:path/path.dart' as p;

/// What an import reads: one file, several, or a folder.
enum ImportSource { file, files, folder }

/// Where notes read from another program go.
enum ImportTarget {
  /// A notebook, or several, of their own.
  newNotebook,

  /// Sections in the notebook open.
  notebook,

  /// Pages in the section open.
  section,
}

/// One program's notes, and how to read them.
///
/// Importers are pure: they read files and return what they found as
/// drafts, leaving storing them to the caller, so they can run away from
/// the window — in an isolate — and be tested without a store.
abstract interface class NotesImporter {
  /// The program's name, as the person knows it.
  String get name;

  /// What of it is read, in a sentence.
  String get description;

  /// The file extensions read, without their dot.
  List<String> get extensions;

  /// Whether one file is chosen, several, or a folder.
  ImportSource get source;

  /// Where what is read goes.
  ImportTarget get target;

  /// Reads [paths], writing the pictures and files the notes hold into
  /// [work] and reporting how far it has got through [progress].
  NotesDraft read(List<String> paths, ImportWork work);
}

/// A folder to put pictures and files in while an import reads them, and
/// somewhere to say how far it has got.
final class ImportWork {
  ImportWork(this.directory, {this.onProgress});

  final Directory directory;
  final void Function(String stage, double? fraction)? onProgress;

  int _next = 0;

  void progress(String stage, [double? fraction]) =>
      onProgress?.call(stage, fraction);

  /// Keeps [bytes] in a file of their own, returning the key a page names
  /// them by and the draft that says where they are.
  (String, AssetDraft) keep(Uint8List bytes, {String? name, String? mime}) {
    final key = 'import-asset-${_next++}';
    final file = File(p.join(directory.path, key));
    file.writeAsBytesSync(bytes, flush: true);
    return (
      key,
      AssetDraft(
        path: file.path,
        mimeType: mime ?? mimeTypeOf(bytes, name: name),
        name: name,
      ),
    );
  }
}

/// The media type of [bytes], from the signature they begin with, or from
/// [name]'s extension when they have none this knows.
String mimeTypeOf(Uint8List bytes, {String? name}) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith(const [0x42, 0x4D])) return 'image/bmp';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  if (startsWith(const [0x49, 0x49, 0x2A, 0x00]) ||
      startsWith(const [0x4D, 0x4D, 0x00, 0x2A])) {
    return 'image/tiff';
  }
  if (startsWith(const [0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
  if (startsWith(const [0x20, 0x45, 0x4D, 0x46], 40)) return 'image/emf';
  if (startsWith(const [0xD7, 0xCD, 0xC6, 0x9A])) return 'image/wmf';
  return switch (p.extension(name ?? '').toLowerCase()) {
    '.svg' => 'image/svg+xml',
    '.txt' => 'text/plain',
    '.pdf' => 'application/pdf',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}

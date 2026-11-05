/// What kind of file bytes are, as the pictures and files of the notes are
/// kept by: one answer whichever way a file came in.
library;

import 'dart:typed_data';

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
  return mimeTypeOfName(name ?? '');
}

/// The media type a file named [name] — or at the path [name] — has by
/// its extension alone; bytes of no type this knows, if none.
String mimeTypeOfName(String name) => switch (_extension(name)) {
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.gif' => 'image/gif',
  '.webp' => 'image/webp',
  '.bmp' => 'image/bmp',
  '.svg' => 'image/svg+xml',
  '.pdf' => 'application/pdf',
  '.txt' => 'text/plain',
  _ => 'application/octet-stream',
};

/// Whether [bytes] begin as gzip's do.
bool isGzipped(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;

/// The extension of the last part of [path], its dot with it, in lower
/// case: none for a name that only begins with a dot.
String _extension(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final name = path.substring((slash > backslash ? slash : backslash) + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}

/// What the system clipboard holds beyond text — files copied in a file
/// manager, a picture such as a screenshot — which Flutter's own clipboard
/// does not read.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Files or a picture on the system clipboard.
sealed class SystemClip {
  const SystemClip({required this.withText});

  /// Whether the clipboard holds text beside them.
  final bool withText;
}

/// Files copied in a file manager: their paths, or a web address for one
/// on the web.
final class CopiedFiles extends SystemClip {
  const CopiedFiles(this.paths, {super.withText = false});

  final List<String> paths;
}

/// A picture copied: a screenshot, or one copied in a browser.
final class CopiedPicture extends SystemClip {
  const CopiedPicture(this.bytes, this.mimeType, {super.withText = false});

  final Uint8List bytes;
  final String mimeType;

  /// A name for it, as a file of its kind.
  String get name =>
      'Pasted picture.${switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/bmp' => 'bmp',
        _ => 'png',
      }}';
}

/// The system clipboard, as the runner of each platform reads it
/// (`linux/runner/clipboard_reader.cc`, `windows/runner/clipboard_reader.cpp`).
abstract final class SystemClipboard {
  static const MethodChannel _channel = MethodChannel('aantekening/clipboard');

  /// Stands in for the runner, in tests.
  @visibleForTesting
  static Future<SystemClip?> Function()? debugRead;

  /// The files or picture the system clipboard holds, or null for none —
  /// or where the platform does not say.
  static Future<SystemClip?> read() async {
    if (debugRead case final read?) return read();
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('read');
      if (reply == null) return null;
      final withText = reply['text'] == true;
      if (reply['files'] case final List<Object?> files) {
        final paths = <String>[for (final path in files) ?path as String?];
        return paths.isEmpty ? null : CopiedFiles(paths, withText: withText);
      }
      if (reply['picture'] case final Uint8List bytes when bytes.isNotEmpty) {
        return CopiedPicture(
          bytes,
          reply['type'] as String? ?? 'image/png',
          withText: withText,
        );
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('The clipboard could not be read: $error');
      return null;
    }
  }
}

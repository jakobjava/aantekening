/// Opening and saving the files attached to pages.
library;

import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// The name [file] is known by.
Future<String> _nameOf(AantekeningStore store, BlockEmbed file) async =>
    file.name ??
    (await store.assets.find(file.assetId))?.originalName ??
    'Attached file';

/// What came of opening an attached file.
enum OpenedFile {
  opened,

  /// Not opened: it is a program, or would run one, which a note shared
  /// with its writer must never start by a click. It can be saved instead.
  runsCode,

  failed,
}

/// Opens [file] with whatever this computer opens its kind of file with:
/// a copy of it, under its own name, so that changing it there changes
/// nothing on the page. A program, or anything else that would run as one,
/// is not opened.
Future<OpenedFile> openAttachedFile(
  AantekeningStore store,
  BlockEmbed file,
) async {
  final asset = await store.assets.find(file.assetId);
  if (asset == null) return OpenedFile.failed;
  final name = safeFileName(await _nameOf(store, file));
  if (runsCode(name)) return OpenedFile.runsCode;
  final source = store.assets.fileFor(asset);
  if (!source.existsSync()) return OpenedFile.failed;
  final folder = Directory(
    p.join(
      Directory.systemTemp.path,
      'aantekening files',
      asset.sha256.substring(0, 16),
    ),
  );
  await folder.create(recursive: true);
  final copy = File(p.join(folder.path, name));
  if (!copy.existsSync()) await source.copy(copy.path);
  return await launchUrl(Uri.file(copy.path))
      ? OpenedFile.opened
      : OpenedFile.failed;
}

/// [name], as written in a note — by anyone it is shared with — made the
/// name of one file: no folders, nothing leading out of where it is put,
/// nothing the system would not take as a name.
@visibleForTesting
String safeFileName(String name) {
  final last = name.split(RegExp(r'[/\\]')).last;
  final cleaned = last
      .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
      .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  return cleaned.isEmpty ? 'Attached file' : cleaned;
}

/// Whether a file named [name] would run as a program when opened, on any
/// of the systems the notes are shared between.
@visibleForTesting
bool runsCode(String name) =>
    _runnable.contains(p.extension(name).toLowerCase());

const Set<String> _runnable = <String>{
  // Windows
  '.exe', '.com', '.bat', '.cmd', '.scr', '.pif', '.msi', '.msp', '.msc',
  '.cpl', '.hta', '.jar', '.js', '.jse', '.vbs', '.vbe', '.wsf', '.wsh',
  '.ps1', '.psm1', '.lnk', '.reg', '.inf', '.application', '.appref-ms',
  '.gadget', '.url', '.scf', '.library-ms', '.settingcontent-ms',
  // Linux and elsewhere
  '.sh', '.bash', '.zsh', '.csh', '.desktop', '.appimage', '.run', '.bin',
  '.py', '.pl', '.rb', '.elf', '.deb', '.rpm', '.apk', '.command', '.app',
};

/// Asks where to save a copy of [file], and saves one there.
Future<void> saveAttachedFile(AantekeningStore store, BlockEmbed file) async {
  final asset = await store.assets.find(file.assetId);
  if (asset == null) return;
  final location = await getSaveLocation(
    suggestedName: safeFileName(await _nameOf(store, file)),
  );
  if (location == null) return;
  await store.assets.fileFor(asset).copy(location.path);
}

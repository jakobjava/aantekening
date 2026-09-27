/// Opening and saving the files attached to pages.
library;

import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// The name [file] is known by.
Future<String> _nameOf(AantekeningStore store, BlockEmbed file) async =>
    file.name ??
    (await store.assets.find(file.assetId))?.originalName ??
    'Attached file';

/// Opens [file] with whatever this computer opens its kind of file with:
/// a copy of it, under its own name, so that changing it there changes
/// nothing on the page.
Future<bool> openAttachedFile(AantekeningStore store, BlockEmbed file) async {
  final asset = await store.assets.find(file.assetId);
  if (asset == null) return false;
  final source = store.assets.fileFor(asset);
  if (!source.existsSync()) return false;
  final folder = Directory(
    p.join(
      Directory.systemTemp.path,
      'aantekening files',
      asset.sha256.substring(0, 16),
    ),
  );
  await folder.create(recursive: true);
  final copy = File(p.join(folder.path, await _nameOf(store, file)));
  if (!copy.existsSync()) await source.copy(copy.path);
  return launchUrl(Uri.file(copy.path));
}

/// Asks where to save a copy of [file], and saves one there.
Future<void> saveAttachedFile(AantekeningStore store, BlockEmbed file) async {
  final asset = await store.assets.find(file.assetId);
  if (asset == null) return;
  final location = await getSaveLocation(
    suggestedName: await _nameOf(store, file),
  );
  if (location == null) return;
  await store.assets.fileFor(asset).copy(location.path);
}

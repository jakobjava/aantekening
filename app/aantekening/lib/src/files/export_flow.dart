/// Writing notebooks, sections and pages out, to keep or to bring into
/// this app on another computer as they were.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/motion.dart';
import '../providers.dart';
import '../reported.dart';
import '../shell/library_menu.dart';
import 'notes_keeper.dart';

/// The extension an export of this app's is saved with.
const String exportExtension = 'aantekening';

/// Asks where to save [node] — a notebook, section or page, with all that
/// is in it — and saves it there.
Future<void> exportNotes(
  BuildContext context,
  WidgetRef ref,
  TreeNode node,
) async {
  final location = await getSaveLocation(
    suggestedName: '${fileName(displayTitle(node))}.$exportExtension',
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(label: 'aantekening', extensions: <String>[exportExtension]),
    ],
  );
  if (location == null) return;
  final path = location.path.endsWith('.$exportExtension')
      ? location.path
      : '${location.path}.$exportExtension';
  final store = await ref.read(storeProvider.future);
  if (!context.mounted) return;
  // A disk full, a folder that may not be written to: said, not lost.
  final messenger = ScaffoldMessenger.maybeOf(context);
  await runReported(context, 'The export could not be saved', () async {
    // What is still being typed goes too: the export is made from the
    // index, which has a page once it is saved.
    await ref.read(openSavesProvider).saveAll();
    await store.exports.write(
      path,
      notebooks: <String>[if (node is Notebook) node.id],
      sections: <String>[if (node is Section) node.id],
      pages: <String>[if (node is PageRef) node.id],
    );
    if (messenger != null && messenger.mounted) {
      messenger.showMessage('Saved to $path');
    }
  });
}

/// [title] with what a file name may not hold replaced.
String fileName(String title) {
  final safe = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  return safe.isEmpty ? 'Notes' : safe;
}

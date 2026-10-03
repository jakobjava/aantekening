/// Bringing notes over from other programs: choosing what, reading it away
/// from the window while saying how far it has got, storing it whole, and
/// opening what came.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/controls.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../providers.dart';
import '../shell/library_actions.dart';
import '../shell/tabs.dart';

/// Every program notes can be brought over from, in the order offered.
const List<NotesImporter> importers = <NotesImporter>[
  OneNoteImporter(),
  XournalImporter(),
  XournalImporter(folders: true),
  LatexImporter(),
  AantekeningImporter(),
];

/// Asks for what [importer] reads, reads it, and stores it where it goes:
/// notebooks by themselves, sections in the notebook open, pages in the
/// section open.
///
/// What it shows and what it refreshes go through the window's own
/// navigator and providers, not [context]'s: the settings it is started
/// from may be closed or rebuilt while an import runs.
Future<void> importNotes(BuildContext context, NotesImporter importer) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final window = Navigator.of(context, rootNavigator: true).context;
  final paths = await _choose(importer);
  if (paths.isEmpty || !window.mounted) return;
  final tab = container.read(tabsProvider).current;
  if (importer.target == ImportTarget.section && tab.sectionId == null) {
    _say(window, 'Open the section the pages should go into first.');
    return;
  }

  final work = await Directory.systemTemp.createTemp('aantekening-import-');
  try {
    if (!window.mounted) return;
    final draft = await showPlainDialog<NotesDraft>(
      context: window,
      barrierDismissible: false,
      builder: (_) =>
          _ImportProgress(importer: importer, paths: paths, work: work),
    );
    if (draft == null || !window.mounted) return;
    if (draft.isEmpty) {
      await _report(window, 'Nothing could be read.', draft.warnings);
      return;
    }
    if (draft.sections.isNotEmpty && tab.notebookId == null ||
        draft.pages.isNotEmpty && tab.sectionId == null) {
      _say(window, 'Open the notebook or section they should go into first.');
      return;
    }
    final store = await container.read(storeProvider.future);
    final stored = await store.drafts.store(
      draft,
      notebookId: tab.notebookId,
      sectionId: tab.sectionId,
    );
    container.read(libraryRevisionProvider.notifier).bump();
    if (stored.firstPage case final first?) {
      container
          .read(libraryActionsProvider)
          .openPage(
            notebookId: first.notebookId,
            sectionId: first.sectionId,
            pageId: first.pageId,
          );
    }
    if (!window.mounted) return;
    final pages = draft.pageCount;
    await _report(
      window,
      '${pages == 1 ? 'One page was' : '$pages pages were'} brought over '
      'from ${importer.name}.',
      draft.warnings,
    );
  } on Object catch (error) {
    if (window.mounted) {
      await _report(window, 'The import failed.', <String>['$error']);
    }
  } finally {
    unawaited(
      work.delete(recursive: true).then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

/// What [importer] is to read: files, or a folder.
Future<List<String>> _choose(NotesImporter importer) async {
  final types = <XTypeGroup>[
    XTypeGroup(label: importer.name, extensions: importer.extensions),
  ];
  return switch (importer.source) {
    ImportSource.folder => <String>[?await getDirectoryPath()],
    ImportSource.files => <String>[
      for (final file in await openFiles(acceptedTypeGroups: types)) file.path,
    ],
    ImportSource.file => <String>[
      ?(await openFile(acceptedTypeGroups: types))?.path,
    ],
  };
}

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showPlainSnackBar(SnackBar(content: Text(message)));

/// Says how an import went, listing what could not be brought over.
Future<void> _report(
  BuildContext context,
  String outcome,
  List<String> warnings,
) {
  if (warnings.isEmpty) {
    _say(context, outcome);
    return Future<void>.value();
  }
  return showPlainDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(outcome),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: SelectableText(
            'Not everything could be brought over:\n\n'
            '${warnings.map((warning) => '·  $warning').join('\n')}',
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// How far an import has got: a stage, and how much of it is done.
typedef _Progress = (String stage, double? fraction);

/// Reads [paths] with [importer] in an isolate, sending how far it has got
/// to [port] and then the draft, or what went wrong.
void _read((NotesImporter, List<String>, String, SendPort) job) {
  final (importer, paths, work, port) = job;
  try {
    final draft = importer.read(
      paths,
      ImportWork(
        Directory(work),
        onProgress: (stage, fraction) => port.send((stage, fraction)),
      ),
    );
    Isolate.exit(port, draft);
  } on Object catch (error) {
    Isolate.exit(port, ImportFailure('$error'));
  }
}

/// An import that could not read what it was given.
class ImportFailure {
  const ImportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The import going on, as a dialog that closes with what was read — or
/// with nothing, if it is stopped.
class _ImportProgress extends StatefulWidget {
  const _ImportProgress({
    required this.importer,
    required this.paths,
    required this.work,
  });

  final NotesImporter importer;
  final List<String> paths;
  final Directory work;

  @override
  State<_ImportProgress> createState() => _ImportProgressState();
}

class _ImportProgressState extends State<_ImportProgress> {
  final ReceivePort _port = ReceivePort();
  Isolate? _isolate;
  _Progress _progress = ('Starting', null);
  String? _failure;

  @override
  void initState() {
    super.initState();
    _port.listen(_onMessage);
    unawaited(_start());
  }

  Future<void> _start() async {
    final isolate = await Isolate.spawn(_read, (
      widget.importer,
      widget.paths,
      widget.work.path,
      _port.sendPort,
    ), onExit: _port.sendPort);
    // Stopped while it was starting.
    if (!mounted) return isolate.kill(priority: Isolate.immediate);
    _isolate = isolate;
  }

  void _onMessage(Object? message) {
    if (!mounted) return;
    switch (message) {
      case final _Progress progress:
        setState(() => _progress = progress);
      case final NotesDraft draft:
        Navigator.of(context).pop(draft);
      case ImportFailure(:final message):
        setState(() => _failure = message);
      // It ended without a word, as when it ran out of memory: what it sends
      // as it ends always comes before this.
      case null when _failure == null:
        setState(() => _failure = 'The import stopped before it was done.');
    }
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _port.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final failure = _failure;
    return AlertDialog(
      title: Text('Importing from ${widget.importer.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (failure != null)
              SelectableText(failure)
            else ...<Widget>[
              Text(
                _progress.$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: tones.muted),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) =>
                    Busy(width: constraints.maxWidth, value: _progress.$2),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(failure == null ? 'Stop' : 'Close'),
        ),
      ],
    );
  }
}

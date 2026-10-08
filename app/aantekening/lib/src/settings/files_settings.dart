/// Files: where the notes are kept, their backups, the bin, and bringing
/// notes in from other programs and out again.
library;

import 'dart:async';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../files/backup_settings.dart';
import '../files/bin_view.dart';
import '../files/export_flow.dart';
import '../files/import_flow.dart';
import '../files/notes_keeper.dart';
import '../files/notes_location.dart';
import '../look/controls.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../providers.dart';
import '../shell/tabs.dart';
import 'settings_view.dart';

/// The files page of the settings.
class FilesSettings extends ConsumerWidget {
  const FilesSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _NotesFolderSection(),
      _BackupsSection(),
      _BinSection(),
      _ImportSection(),
      _ExportSection(),
    ],
  );
}

/// Whether folders can be chosen here: not on phones, whose apps keep
/// their files to themselves.
bool get _canChooseFolders =>
    !Platform.isAndroid &&
    !Platform.isIOS &&
    (Platform.environment['AANTEKENING_HOME'] ?? '').isEmpty;

TextStyle _note(BuildContext context) =>
    TextStyle(fontSize: 12.5, height: 1.45, color: context.tones.muted);

/// Something done that takes a moment, with what went wrong said beneath.
Future<void> _attempt(
  BuildContext context,
  Future<void> Function() work,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await work();
  } on Object catch (error) {
    messenger?.showAppSnackBar(SnackBar(content: Text('$error')));
  }
}

/// A path, selectable, with a button copying it.
class _Path extends StatelessWidget {
  const _Path(this.path);

  final String path;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: SelectableText(path, style: const TextStyle(fontSize: 13)),
      ),
      SmallButton(
        'Copy',
        tooltip: 'Copy where the folder is',
        onPressed: () => Clipboard.setData(ClipboardData(text: path)),
      ),
      SmallButton(
        'Show',
        tooltip: 'Open the folder in the file manager',
        onPressed: () => unawaited(launchUrl(Uri.directory(path))),
      ),
    ],
  );
}

class _NotesFolderSection extends ConsumerStatefulWidget {
  const _NotesFolderSection();

  @override
  ConsumerState<_NotesFolderSection> createState() =>
      _NotesFolderSectionState();
}

class _NotesFolderSectionState extends ConsumerState<_NotesFolderSection> {
  bool _moving = false;

  Future<void> _choose() async {
    final chosen = await getDirectoryPath(
      confirmButtonText: 'Keep notes here',
      canCreateDirectories: true,
    );
    if (chosen == null || !mounted) return;
    final current = ref.read(notesFolderProvider).value;
    if (chosen == current) return;
    final location = ref.read(notesLocationProvider);
    final holdsNotes = contentsOf(chosen) == FolderContents.notes;
    final target = holdsNotes ? chosen : notesFolderIn(chosen);
    final agreed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          holdsNotes ? 'Open the notes in this folder?' : 'Move your notes?',
        ),
        content: SizedBox(
          width: 460,
          child: Text(
            holdsNotes
                ? 'The folder holds notes already, as another computer '
                      'keeping its notes there would have put them. They '
                      'are opened, and kept in step with that computer; the '
                      'notes you have open now stay where they are.'
                : 'Your notes are copied to\n$target\nand each file checked '
                      'as it arrives. The folder they are in now is left as '
                      'it is; delete it once you are sure.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(holdsNotes ? 'Open them' : 'Move them'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() => _moving = true);
    await _attempt(context, () async {
      await keepEverything(ref);
      if (holdsNotes) {
        await location.openAt(target);
      } else {
        await location.moveTo(target);
      }
    });
    if (mounted) setState(() => _moving = false);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final folder = ref.watch(notesFolderProvider).value;
    final status = ref.watch(folderStatusProvider).value;
    final problem = status?.problem;
    final state =
        problem ??
        (status == null || status.pending == 0
            ? 'Everything is saved in it.'
            : 'Saving ${status.pending} changes…');
    return SettingsSection(
      title: 'Where your notes are',
      description:
          'Each notebook, section and page is a file of its own in this '
          'folder, with its pictures and files beside it. Put it in a folder '
          'OneDrive, Dropbox or Nextcloud keeps in step, and open that folder '
          'on each of your computers: what you change on one arrives on the '
          'others. The index that makes searching instant stays on this '
          'computer.',
      children: <Widget>[
        if (folder != null) _Path(folder),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            state,
            style: TextStyle(
              fontSize: 12.5,
              color: problem == null ? tones.muted : tones.text,
              fontWeight: problem == null ? null : FontWeight.w600,
            ),
          ),
        ),
        if (_canChooseFolders)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton(
                onPressed: _moving ? null : _choose,
                child: const Text('Keep notes in another folder…'),
              ),
              if (_moving) const Busy(width: 48),
            ],
          ),
      ],
    );
  }
}

class _BackupsSection extends ConsumerWidget {
  const _BackupsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final settings = ref.watch(backupsProvider);
    final backups = ref.read(backupsProvider.notifier);
    final folder =
        settings.folder ?? ref.watch(defaultBackupFolderProvider).value;
    final last = settings.last;

    Future<void> chooseFolder() async {
      final chosen = await getDirectoryPath(
        confirmButtonText: 'Back up here',
        canCreateDirectories: true,
      );
      if (chosen != null) backups.setFolder(chosen);
    }

    Future<void> backUp() async {
      final path = await backups.backUpNow();
      if (path == null || !context.mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showAppSnackBar(SnackBar(content: Text('Backed up to $path')));
    }

    return SettingsSection(
      title: 'Backups',
      description:
          'A backup is every note, picture and file in one zip, kept apart '
          'from the notes — on another drive, ideally. The oldest go once '
          'there are more than you keep.',
      children: <Widget>[
        SettingRow(
          label: 'Back up',
          child: ChoiceRow<BackupInterval>(
            choices: BackupInterval.values,
            selected: settings.interval,
            labelOf: (interval) => interval.label,
            onSelected: backups.setInterval,
          ),
        ),
        SettingRow(
          label: 'Keep',
          child: ChoiceRow<int>(
            choices: BackupSettings.keeps,
            selected: settings.keep,
            labelOf: (keep) => '$keep',
            onSelected: backups.setKeep,
          ),
        ),
        const SizedBox(height: 6),
        if (folder != null) _Path(folder),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            settings.problem ??
                (last == null
                    ? 'No backup made yet.'
                    : 'Last backed up ${timeSaid(last.millisecondsSinceEpoch)}.'),
            style: TextStyle(
              fontSize: 12.5,
              color: settings.problem == null ? tones.muted : tones.text,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            OutlinedButton(
              onPressed: settings.running ? null : () => unawaited(backUp()),
              child: const Text('Back up now'),
            ),
            if (_canChooseFolders)
              OutlinedButton(
                onPressed: () => unawaited(chooseFolder()),
                child: const Text('Back up to another folder…'),
              ),
            if (settings.folder != null)
              SmallButton(
                'Use the app’s own',
                tooltip: 'Back up beside the app again',
                onPressed: () => backups.setFolder(null),
              ),
            if (_canChooseFolders)
              OutlinedButton(
                onPressed: () => unawaited(_restore(context, ref)),
                child: const Text('Restore a backup…'),
              ),
            if (settings.running) const Busy(width: 48),
          ],
        ),
      ],
    );
  }

  /// Restores a backup into a folder of its own, and opens it there: the
  /// notes open now are left as they are.
  static Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final backup = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Backups', extensions: <String>['zip']),
      ],
    );
    if (backup == null || !context.mounted) return;
    final into = await getDirectoryPath(
      confirmButtonText: 'Restore here',
      canCreateDirectories: true,
    );
    if (into == null || !context.mounted) return;
    await _attempt(context, () async {
      final target = notesFolderIn(into);
      await Backups.restore(backup.path, target);
      await keepEverything(ref);
      await ref.read(notesLocationProvider).openAt(target);
    });
  }
}

class _BinSection extends ConsumerWidget {
  const _BinSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(binProvider).value ?? const <BinEntry>[];
    final pages = entries.fold<int>(0, (sum, entry) => sum + entry.pages);
    return SettingsSection(
      title: 'Bin',
      description:
          'What you delete goes to the bin, with everything in it, until you '
          'restore it or delete it for good.',
      children: <Widget>[
        Text(
          entries.isEmpty
              ? 'The bin is empty.'
              : '${entries.length} deleted, $pages '
                    '${pages == 1 ? 'page' : 'pages'} in all.',
          style: _note(context),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton(
              onPressed: () => unawaited(showBin(context)),
              child: const Text('Open the bin'),
            ),
            OutlinedButton(
              onPressed: entries.isEmpty
                  ? null
                  : () => unawaited(emptyBin(context, ref)),
              child: const Text('Empty the bin'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImportSection extends ConsumerWidget {
  const _ImportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSection(
    title: 'Import',
    description:
        'Bring notes over from other programs, as they were: a notebook '
        'becomes a notebook here; documents become pages of the section '
        'open.',
    children: <Widget>[
      for (final importer in importers)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(importer.name, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(importer.description, style: _note(context)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => unawaited(importNotes(context, importer)),
                child: const Text('Import…'),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ExportSection extends ConsumerWidget {
  const _ExportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabsProvider.select((tabs) => tabs.current));
    final notebook = tab.notebookId == null
        ? null
        : ref
              .watch(notebooksProvider)
              .value
              ?.where((each) => each.id == tab.notebookId)
              .firstOrNull;
    final section = tab.sectionId == null
        ? null
        : ref.watch(sectionProvider(tab.sectionId!)).value;
    final page = tab.pageId == null
        ? null
        : ref.watch(pageProvider(tab.pageId!)).value;
    return SettingsSection(
      title: 'Export',
      description:
          'Save a notebook, section or page with everything in it as a '
          '.$exportExtension file: to keep, or to import on another computer '
          'exactly as it is. A notebook, section or page’s own menu has '
          'Export… too.',
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final (label, node) in <(String, TreeNode?)>[
              ('Export this notebook…', notebook),
              ('Export this section…', section),
              ('Export this page…', page),
            ])
              OutlinedButton(
                onPressed: node == null
                    ? null
                    : () => unawaited(exportNotes(context, ref, node)),
                child: Text(label),
              ),
          ],
        ),
      ],
    );
  }
}

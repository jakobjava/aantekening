/// Keeping the notes whole on disk while the app runs: saving what is open
/// before the app stops or goes to the background, reading in what other
/// computers changed, and backing up when a backup is due.
library;

import 'dart:async';
import 'dart:ui';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/motion.dart';
import '../providers.dart';
import 'backup_settings.dart';
import 'notes_location.dart';

/// Whatever holds changes not yet saved — a page being edited — saving
/// them when asked, so that nothing is lost when the app stops.
class OpenSaves {
  final Set<Future<void> Function()> _savers = <Future<void> Function()>{};

  /// Adds [save], which saves what its owner holds; returns what removes
  /// it again.
  VoidCallback register(Future<void> Function() save) {
    _savers.add(save);
    return () => _savers.remove(save);
  }

  /// Saves everything open.
  Future<void> saveAll() =>
      Future.wait(<Future<void>>[for (final save in List.of(_savers)) save()]);
}

final openSavesProvider = Provider<OpenSaves>((ref) => OpenSaves());

/// Saves everything open, then writes everything waiting to the notes
/// folder.
Future<void> keepEverything(WidgetRef ref) async {
  await ref.read(openSavesProvider).saveAll();
  final store = ref.read(storeProvider).value;
  await store?.mirror?.flush();
}

/// Keeps the notes whole on disk for as long as [child] is shown.
class NotesKeeper extends ConsumerStatefulWidget {
  const NotesKeeper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotesKeeper> createState() => _NotesKeeperState();
}

class _NotesKeeperState extends ConsumerState<NotesKeeper> {
  late final AppLifecycleListener _lifecycle;
  Timer? _backups;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: _beforeExit,
      onHide: _keep,
      onPause: _keep,
    );
    // Backed up once the notes are open, and then whenever one is due.
    unawaited(_backUpWhenOpen());
    _backups = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(ref.read(backupsProvider.notifier).backUpIfDue()),
    );
  }

  Future<void> _backUpWhenOpen() async {
    final AantekeningStore store;
    try {
      store = await ref.read(storeProvider.future);
    } on Object {
      // The window says why the notes could not be opened.
      return;
    }
    if (!mounted) return;
    _sayRescued(store.rescued);
    await ref.read(backupsProvider.notifier).backUpIfDue();
  }

  /// Says which pages were put back that could not be saved last time.
  void _sayRescued(List<PageRef> rescued) {
    if (rescued.isEmpty) return;
    final names = <String>[
      for (final page in rescued)
        '“${page.title.isEmpty ? 'Untitled' : page.title}”',
    ].join(', ');
    ScaffoldMessenger.maybeOf(context)?.showMessage(
      rescued.length == 1
          ? 'A page could not be saved last time, and is put back: $names.'
          : '${rescued.length} pages could not be saved last time, and are '
                'put back: $names.',
    );
    ref.read(libraryRevisionProvider.notifier).bump();
  }

  @override
  void dispose() {
    _backups?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _keep() => unawaited(keepEverything(ref));

  /// Whether closing was stopped once already because something could not
  /// be saved: asked again, the app closes.
  bool _exitRefused = false;

  /// Lets the app stop only once everything is on disk — or, if something
  /// could be neither saved nor rescued, once asked again after being told.
  Future<AppExitResponse> _beforeExit() async {
    final store = ref.read(storeProvider).value;
    try {
      await keepEverything(ref);
    } on Object catch (error) {
      if (!_exitRefused && mounted) {
        _exitRefused = true;
        ScaffoldMessenger.maybeOf(context)?.showMessage(
          'Some changes could not be saved ($error). Close again to quit '
          'without them.',
        );
        return AppExitResponse.cancel;
      }
    }
    // Closed whatever else failed, so the database is left whole.
    await store?.close();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    // What other computers changed shows at once.
    ref.listen<AsyncValue<Object?>>(folderChangesProvider, (_, next) {
      if (next.hasValue) ref.read(libraryRevisionProvider.notifier).bump();
    });
    return widget.child;
  }
}

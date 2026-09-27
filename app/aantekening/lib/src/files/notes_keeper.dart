/// Keeping the notes whole on disk while the app runs: saving what is open
/// before the app stops or goes to the background, reading in what other
/// computers changed, and backing up when a backup is due.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await ref.read(storeProvider.future);
    if (mounted) await ref.read(backupsProvider.notifier).backUpIfDue();
  }

  @override
  void dispose() {
    _backups?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _keep() => unawaited(keepEverything(ref));

  /// Lets the app stop only once everything is on disk.
  Future<AppExitResponse> _beforeExit() async {
    await keepEverything(ref);
    final store = ref.read(storeProvider).value;
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

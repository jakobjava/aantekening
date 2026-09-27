/// Backing the notes up: where, how often, how many are kept, and making
/// one now.
library;

import 'dart:isolate';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../preferences.dart';
import '../providers.dart';
import 'notes_keeper.dart';
import 'notes_location.dart';

/// How often the notes are backed up by themselves.
enum BackupInterval {
  never('Never', null),
  daily('Every day', Duration(days: 1)),
  weekly('Every week', Duration(days: 7));

  const BackupInterval(this.label, this.every);

  final String label;
  final Duration? every;
}

/// Where and how the notes are backed up, and how the last backup went.
@immutable
class BackupSettings {
  const BackupSettings({
    this.folder,
    this.interval = BackupInterval.daily,
    this.keep = 10,
    this.last,
    this.running = false,
    this.problem,
  });

  /// The folder backups go to, or null for the app's own.
  final String? folder;
  final BackupInterval interval;

  /// How many backups are kept; older ones are deleted.
  final int keep;

  /// When the last backup was made.
  final DateTime? last;

  /// Whether a backup is being made now.
  final bool running;

  /// What went wrong with the last backup, if anything did.
  final String? problem;

  static const List<int> keeps = <int>[3, 10, 30, 100];

  BackupSettings copyWith({
    String? Function()? folder,
    BackupInterval? interval,
    int? keep,
    DateTime? last,
    bool? running,
    String? Function()? problem,
  }) => BackupSettings(
    folder: folder == null ? this.folder : folder(),
    interval: interval ?? this.interval,
    keep: keep ?? this.keep,
    last: last ?? this.last,
    running: running ?? this.running,
    problem: problem == null ? this.problem : problem(),
  );

  /// Whether a backup is due by [now].
  bool dueAt(DateTime now) {
    final every = interval.every;
    if (every == null) return false;
    final last = this.last;
    return last == null || now.difference(last) >= every;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (folder != null) 'folder': folder,
    'interval': interval.name,
    'keep': keep,
    if (last != null) 'last': last!.millisecondsSinceEpoch,
  };

  static BackupSettings fromJson(Object? json) {
    if (json is! Map) return const BackupSettings();
    final interval = BackupInterval.values
        .where((each) => each.name == json['interval'])
        .firstOrNull;
    final keep = json['keep'];
    final last = json['last'];
    final folder = json['folder'];
    return BackupSettings(
      folder: folder is String && folder.isNotEmpty ? folder : null,
      interval: interval ?? BackupInterval.daily,
      keep: keep is int && keep > 0 ? keep : 10,
      last: last is int ? DateTime.fromMillisecondsSinceEpoch(last) : null,
    );
  }
}

/// The folder backups go to when none is chosen: the app's own, beside
/// the notes rather than among them.
final defaultBackupFolderProvider = FutureProvider<String>(
  (ref) async =>
      p.join(await ref.watch(supportFolderProvider.future), 'backups'),
);

class BackupsController extends Notifier<BackupSettings> {
  static const String _key = 'backups';

  @override
  BackupSettings build() => BackupSettings.fromJson(ref.preference(_key));

  void _save(BackupSettings settings) {
    state = settings;
    ref.savePreference(_key, settings.toJson());
  }

  void setFolder(String? folder) => _save(state.copyWith(folder: () => folder));

  void setInterval(BackupInterval interval) =>
      _save(state.copyWith(interval: interval));

  void setKeep(int keep) {
    _save(state.copyWith(keep: keep));
  }

  /// The folder backups go to.
  Future<String> folder() async =>
      state.folder ?? await ref.read(defaultBackupFolderProvider.future);

  /// Backs the notes up now, returning the backup's path; the oldest
  /// backups beyond those kept go.
  ///
  /// Whatever is waiting is written to the notes folder first, so the
  /// backup has everything; the folder is then zipped away from the
  /// window, which a large folder would otherwise hold up.
  Future<String?> backUpNow() async {
    if (state.running) return null;
    state = state.copyWith(running: true, problem: () => null);
    try {
      await ref.read(openSavesProvider).saveAll();
      final store = await ref.read(storeProvider.future);
      await store.mirror?.flush();
      final notes = store.directory;
      final into = await folder();
      final keep = state.keep;
      final path = await Isolate.run(() {
        final made = Backups.create(notes, into);
        Backups.prune(into, keep: keep);
        return made;
      });
      // The app may have closed while the backup was made, leaving no
      // settings to note it in.
      if (ref.mounted) {
        _save(state.copyWith(running: false, last: DateTime.now()));
      }
      return path;
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(running: false, problem: () => '$error');
      }
      return null;
    }
  }

  /// Backs the notes up if a backup is due.
  Future<void> backUpIfDue() async {
    if (state.dueAt(DateTime.now())) await backUpNow();
  }
}

final backupsProvider = NotifierProvider<BackupsController, BackupSettings>(
  BackupsController.new,
);

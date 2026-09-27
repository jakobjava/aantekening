/// The bin: what was deleted, to be restored or deleted for good.
library;

import 'dart:async';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import '../providers.dart';

/// Everything in the bin, what was deleted last first.
final binProvider = FutureProvider<List<BinEntry>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.bin.list();
});

/// Opens the bin, over the window.
Future<void> showBin(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const BinView());

/// When [time] was, as a person says it: today at a time, yesterday, a
/// few days ago, or the date.
String timeSaid(int time, {DateTime? now}) {
  final at = DateTime.fromMillisecondsSinceEpoch(time);
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  return switch (days) {
    0 => 'today at ${two(at.hour)}:${two(at.minute)}',
    1 => 'yesterday',
    < 7 => '$days days ago',
    _ => '${at.day}.${at.month}.${at.year}',
  };
}

/// Asks before deleting for good: the one thing done here that cannot be
/// undone.
Future<bool> confirmPurge(BuildContext context, String what) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $what for good?'),
        content: const Text(
          'It cannot be restored afterwards, here or on any computer that '
          'shares these notes.',
        ),
        actions: <Widget>[
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete for good'),
          ),
        ],
      ),
    ) ??
    false;

/// Empties the bin, once asked, and collects the pictures and files no
/// page shows any more; says how many pages went.
Future<void> emptyBin(BuildContext context, WidgetRef ref) async {
  if (!await confirmPurge(context, 'everything in the bin')) return;
  final store = await ref.read(storeProvider.future);
  final pages = await store.bin.empty();
  await store.assets.collectGarbage();
  ref.read(libraryRevisionProvider.notifier).bump();
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        pages == 1
            ? 'One page deleted for good.'
            : '$pages pages deleted for good.',
      ),
    ),
  );
}

class BinView extends ConsumerWidget {
  const BinView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final bin = ref.watch(binProvider);
    final entries = bin.value ?? const <BinEntry>[];

    Future<void> restore(BinEntry entry) async {
      final store = await ref.read(storeProvider.future);
      await store.bin.restore(entry);
      ref.read(libraryRevisionProvider.notifier).bump();
    }

    Future<void> purge(BinEntry entry) async {
      if (!await confirmPurge(context, '“${entry.title}”')) return;
      final store = await ref.read(storeProvider.future);
      await store.bin.purge(entry);
      await store.assets.collectGarbage();
      ref.read(libraryRevisionProvider.notifier).bump();
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                child: Row(
                  children: <Widget>[
                    Text('Bin', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    SmallButton(
                      'Empty the bin',
                      tooltip: 'Delete everything in it for good',
                      onPressed: entries.isEmpty
                          ? null
                          : () => unawaited(emptyBin(context, ref)),
                    ),
                    const SizedBox(width: 8),
                    MarkButton(
                      MarkShape.close,
                      tooltip: 'Close  (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Text(
                  'What you delete stays here, with everything in it, until '
                  'you restore it or delete it for good.',
                  style: TextStyle(fontSize: 12.5, color: tones.muted),
                ),
              ),
              Flexible(
                child: bin.isLoading && entries.isEmpty
                    ? const SizedBox(height: 120, child: Loading())
                    : entries.isEmpty
                    ? const SizedBox(
                        height: 120,
                        child: EmptyMessage('The bin is empty.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        children: <Widget>[
                          for (final entry in entries)
                            RowTile(
                              title: Text(
                                entry.title.isEmpty ? 'Untitled' : entry.title,
                              ),
                              subtitle: Text(_describe(entry)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  SmallButton(
                                    'Restore',
                                    tooltip: 'Put it back where it was',
                                    onPressed: () => unawaited(restore(entry)),
                                  ),
                                  SmallButton(
                                    'Delete',
                                    tooltip: 'Delete it for good',
                                    onPressed: () => unawaited(purge(entry)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(BinEntry entry) {
    final kind = switch (entry.kind) {
      BinKind.notebook => 'Notebook',
      BinKind.section => 'Section',
      BinKind.page => 'Page',
    };
    final pages = switch (entry.kind) {
      BinKind.page when entry.pages <= 1 => '',
      _ when entry.pages == 1 => '  ·  one page',
      _ => '  ·  ${entry.pages} pages',
    };
    final place = entry.place.isEmpty ? '' : ' in ${entry.place.join(' › ')}';
    return '$kind$place  ·  deleted ${timeSaid(entry.deletedAt)}$pages';
  }
}

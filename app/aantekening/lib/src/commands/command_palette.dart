/// Go to and Commands: a line to type a few letters of a page's or a
/// command's name into, and what they match, to open or run from the
/// keyboard.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../graph/note_graph.dart';
import '../look/chooser.dart';
import '../shell/library_actions.dart';
import '../shell/recent_pages.dart';
import 'app_command.dart';
import 'fuzzy.dart';
import 'shortcuts.dart';

/// What turns Go to into Commands, typed first.
const String commandPrefix = '>';

/// How many choices are offered at most.
const int _shown = 60;

/// Opens Go to, over the notebooks, sections and pages, or with [commands]
/// the commands — typed as the [commandPrefix] Go to switches to them with.
Future<void> showCommandPalette(
  BuildContext context, {
  bool commands = false,
}) => showChooser(
  context,
  initial: commands ? commandPrefix : '',
  choicesFor: (ref, typed) => _isCommands(typed)
      ? _commandChoices(ref, _stripped(typed))
      : _placeChoices(ref, typed.trim()),
  hintFor: (typed) => _isCommands(typed)
      ? 'Type a command'
      : 'Type a page, section or notebook — or > for commands',
  keysFor: (typed) => <String>[
    'Up Down  choose',
    if (_isCommands(typed)) 'Enter  run' else 'Enter  open',
    if (!_isCommands(typed)) 'Ctrl+Enter  open in a new tab',
    'Esc  close',
  ],
);

bool _isCommands(String typed) => typed.startsWith(commandPrefix);

String _stripped(String typed) => typed.substring(commandPrefix.length).trim();

List<Choice> _commandChoices(WidgetRef ref, String typed) {
  final handlers = ref.read(commandHandlersProvider);
  final bindings = ref.watch(shortcutsProvider);
  final choices = <(int, Choice)>[];
  for (final command in AppCommand.values) {
    final action = handlers[command];
    if (action == null || command == AppCommand.commands) continue;
    final score = typed.isEmpty
        ? -choices.length
        : fuzzyScore(typed, command.label) ??
              fuzzyScore(typed, '${command.group.label} ${command.label}');
    if (score == null) continue;
    final chords = bindings.of(command);
    choices.add((
      score,
      Choice(
        title: command.label,
        detail: command.group.label,
        hint: chords.isEmpty ? null : chords.first.label,
        enabled: action.isEnabled,
        run: action.run,
      ),
    ));
  }
  return _best(choices);
}

List<Choice> _placeChoices(WidgetRef ref, String typed) {
  final graph = ref.watch(noteGraphProvider).value;
  if (graph == null) return const <Choice>[];
  final recent = ref.watch(recentPagesProvider);
  final actions = ref.read(libraryActionsProvider);

  String where(GraphNode node) => <String>[
    if (node.kind != GraphNodeKind.notebook)
      graph.node(node.notebookId)?.label ?? '',
    if (node.kind == GraphNodeKind.page)
      graph.node(node.sectionId!)?.label ?? '',
  ].where((part) => part.isNotEmpty).join('  ›  ');

  Choice choice(GraphNode node) => Choice(
    title: node.label,
    detail: switch (where(node)) {
      '' => null,
      final where => where,
    },
    hint: switch (node.kind) {
      GraphNodeKind.notebook => 'Notebook',
      GraphNodeKind.section => 'Section',
      GraphNodeKind.page => null,
    },
    run: () => _open(actions, node),
    runAside: node.kind == GraphNodeKind.page
        ? () => unawaited(actions.openIdInNewTab(node.id))
        : null,
  );

  if (typed.isEmpty) {
    // Nothing typed yet: the pages opened lately, where to go back to.
    final lately = <GraphNode>[for (final id in recent) ?graph.node(id)];
    return <Choice>[
      for (final node
          in lately.isEmpty
              ? graph.nodes.where((node) => node.kind == GraphNodeKind.page)
              : lately)
        choice(node),
    ].take(_shown).toList();
  }
  final rank = <String, int>{
    for (final (index, id) in recent.indexed) id: recent.length - index,
  };
  return _best(<(int, Choice)>[
    for (final node in graph.nodes)
      if (fuzzyScore(typed, node.label) case final score?)
        // Of names that match alike, one opened lately comes first.
        (score + (rank[node.id] ?? 0) * 20, choice(node)),
  ]);
}

List<Choice> _best(List<(int, Choice)> scored) {
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return <Choice>[for (final (_, choice) in scored.take(_shown)) choice];
}

void _open(LibraryActions actions, GraphNode node) => switch (node.kind) {
  GraphNodeKind.notebook => actions.openNotebook(node.id),
  GraphNodeKind.section => actions.openSection(node.notebookId, node.id),
  GraphNodeKind.page => actions.openPage(
    notebookId: node.notebookId,
    sectionId: node.sectionId!,
    pageId: node.id,
  ),
};

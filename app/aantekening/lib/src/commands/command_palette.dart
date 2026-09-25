/// Go to and Commands: a line to type a few letters of a page's or a
/// command's name into, and what they match, to open or run from the
/// keyboard.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../graph/note_graph.dart';
import '../look/controls.dart';
import '../look/tones.dart';
import '../shell/library_actions.dart';
import '../shell/recent_pages.dart';
import 'app_command.dart';
import 'fuzzy.dart';
import 'shortcuts.dart';

/// Opens the palette: Go to, over the notebooks, sections and pages, or with
/// [commands] the commands — typed as the ">" Go to switches to them with.
Future<void> showCommandPalette(
  BuildContext context, {
  bool commands = false,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: context.tones.text.withValues(alpha: 0.08),
  transitionDuration: const Duration(milliseconds: 90),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => CommandPalette(commands: commands),
);

/// What the palette offers: a page, section or notebook to open, or a
/// command to run.
@immutable
class _Entry {
  const _Entry({
    required this.title,
    required this.run,
    this.detail,
    this.hint,
    this.enabled = true,
    this.runAside,
  });

  final String title;

  /// Where it is, or what it does.
  final String? detail;

  /// Beside it: its kind, or its shortcut.
  final String? hint;
  final bool enabled;
  final VoidCallback run;

  /// Opens it in a tab of its own, with Ctrl+Enter.
  final VoidCallback? runAside;
}

/// The palette itself: a field over the entries it matches, the first
/// highlighted, stepped through with the arrow keys and taken with Enter.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({this.commands = false, super.key});

  final bool commands;

  /// What turns Go to into Commands, typed first.
  static const String commandPrefix = '>';

  /// How many entries are listed at most.
  static const int _shown = 60;

  static const double _rowHeight = 40;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  late final TextEditingController _query = TextEditingController(
    text: widget.commands ? CommandPalette.commandPrefix : '',
  );
  final ScrollController _scroll = ScrollController();
  int _highlight = 0;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _commands => _query.text.startsWith(CommandPalette.commandPrefix);

  String get _typed => _commands
      ? _query.text.substring(CommandPalette.commandPrefix.length).trim()
      : _query.text.trim();

  /// Closes the palette, then does [action] — so a dialog it opens opens
  /// over the window, not over the palette.
  void _close(VoidCallback action) {
    Navigator.of(context).pop();
    scheduleMicrotask(action);
  }

  List<_Entry> _entries() => _commands ? _commandEntries() : _placeEntries();

  List<_Entry> _commandEntries() {
    final handlers = ref.read(commandHandlersProvider);
    final bindings = ref.watch(shortcutsProvider);
    final entries = <(int, _Entry)>[];
    for (final command in AppCommand.values) {
      final action = handlers[command];
      if (action == null || command == AppCommand.commands) continue;
      final score = _typed.isEmpty
          ? -entries.length
          : fuzzyScore(_typed, command.label) ??
                fuzzyScore(_typed, '${command.group.label} ${command.label}');
      if (score == null) continue;
      final chords = bindings.of(command);
      entries.add((
        score,
        _Entry(
          title: command.label,
          detail: command.group.label,
          hint: chords.isEmpty ? null : chords.first.label,
          enabled: action.isEnabled,
          run: () => _close(action.run),
        ),
      ));
    }
    return _best(entries);
  }

  List<_Entry> _placeEntries() {
    final graph = ref.watch(noteGraphProvider).value;
    if (graph == null) return const <_Entry>[];
    final recent = ref.watch(recentPagesProvider);
    final actions = ref.read(libraryActionsProvider);

    String where(GraphNode node) => <String>[
      if (node.kind != GraphNodeKind.notebook)
        graph.node(node.notebookId)?.label ?? '',
      if (node.kind == GraphNodeKind.page)
        graph.node(node.sectionId!)?.label ?? '',
    ].where((part) => part.isNotEmpty).join('  ›  ');

    _Entry entry(GraphNode node) => _Entry(
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
      run: () => _close(() => _open(actions, node)),
      runAside: node.kind == GraphNodeKind.page
          ? () => _close(() => unawaited(actions.openIdInNewTab(node.id)))
          : null,
    );

    if (_typed.isEmpty) {
      // Nothing typed yet: the pages opened lately, where to go back to.
      final lately = <GraphNode>[for (final id in recent) ?graph.node(id)];
      return <_Entry>[
        for (final node
            in lately.isEmpty
                ? graph.nodes.where((node) => node.kind == GraphNodeKind.page)
                : lately)
          entry(node),
      ].take(CommandPalette._shown).toList();
    }
    final rank = <String, int>{
      for (final (index, id) in recent.indexed) id: recent.length - index,
    };
    return _best(<(int, _Entry)>[
      for (final node in graph.nodes)
        if (fuzzyScore(_typed, node.label) case final score?)
          // Of names that match alike, one opened lately comes first.
          (score + (rank[node.id] ?? 0) * 20, entry(node)),
    ]);
  }

  static List<_Entry> _best(List<(int, _Entry)> scored) {
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return <_Entry>[
      for (final (_, entry) in scored.take(CommandPalette._shown)) entry,
    ];
  }

  static void _open(LibraryActions actions, GraphNode node) =>
      switch (node.kind) {
        GraphNodeKind.notebook => actions.openNotebook(node.id),
        GraphNodeKind.section => actions.openSection(node.notebookId, node.id),
        GraphNodeKind.page => actions.openPage(
          notebookId: node.notebookId,
          sectionId: node.sectionId!,
          pageId: node.id,
        ),
      };

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _highlight = (_highlight + by).clamp(0, count - 1));
    final top = _highlight * CommandPalette._rowHeight;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + CommandPalette._rowHeight >
        position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        top + CommandPalette._rowHeight - position.viewportDimension,
      );
    }
  }

  KeyEventResult _onKey(KeyEvent event, List<_Entry> entries) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, entries.length);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, entries.length);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _move(8, entries.length);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _move(-8, entries.length);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_highlight < entries.length) {
        final entry = entries[_highlight];
        final aside = entry.runAside;
        if (keyboard.isControlPressed && aside != null) {
          aside();
        } else if (entry.enabled) {
          entry.run();
        }
      }
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final entries = _entries();
    if (_highlight >= entries.length) _highlight = 0;
    final placeholder = _commands
        ? 'Type a command'
        : 'Type a page, section or notebook — or > for commands';

    return Align(
      alignment: const Alignment(0, -0.6),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 460),
          child: Material(
            color: tones.base,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: tones.strongLine),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Focus(
                  onKeyEvent: (_, event) => _onKey(event, entries),
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: placeholder,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                    onChanged: (_) => setState(() => _highlight = 0),
                  ),
                ),
                const Divider(),
                Flexible(
                  child: entries.isEmpty
                      ? SizedBox(
                          height: 64,
                          child: EmptyMessage(
                            _typed.isEmpty ? 'Nothing here yet' : 'No match',
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemExtent: CommandPalette._rowHeight,
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return _EntryRow(
                              entry: entry,
                              highlighted: index == _highlight,
                              onTap: entry.enabled ? entry.run : null,
                            );
                          },
                        ),
                ),
                _Footer(commands: _commands),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.highlighted,
    required this.onTap,
  });

  final _Entry entry;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final hint = entry.hint;
    return RowTile(
      selected: highlighted,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      titleStyle: TextStyle(
        color: entry.enabled ? tones.text : tones.faint,
        fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
      ),
      title: Text(entry.title),
      subtitle: entry.detail == null ? null : Text(entry.detail!),
      trailing: hint == null ? null : KeyHint(hint),
    );
  }
}

/// The keys the palette answers to, along its foot.
class _Footer extends StatelessWidget {
  const _Footer({required this.commands});

  final bool commands;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tones.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Wrap(
          spacing: 16,
          children: <Widget>[
            const KeyHint('Up Down  choose'),
            KeyHint(commands ? 'Enter  run' : 'Enter  open'),
            if (!commands) const KeyHint('Ctrl+Enter  open in a new tab'),
            const KeyHint('Esc  close'),
          ],
        ),
      ),
    );
  }
}

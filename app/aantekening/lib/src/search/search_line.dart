/// The search line: vim's `/`, a bar of glass by the status line to type
/// what to find into, the page marking it as it is typed and the pages
/// that have it listed beneath.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/controls.dart';
import '../look/glass.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../modes/key_catch.dart';
import '../providers.dart';
import '../shell/library_menu.dart' show pageTitleOrPlaceholder;
import 'search_session.dart';

/// Whether the search line is open — and what is typed while it opens,
/// ahead of its field.
class SearchLineOpen extends Notifier<bool> {
  TypeAhead? _ahead;

  @override
  bool build() => false;

  void open() {
    _ahead?.take();
    _ahead = TypeAhead();
    state = true;
  }

  /// What was typed while the line was opening.
  String _typedAhead() {
    final typed = _ahead?.take() ?? '';
    _ahead = null;
    return typed;
  }

  void close() {
    _ahead?.take();
    _ahead = null;
    state = false;
  }
}

final searchLineProvider = NotifierProvider<SearchLineOpen, bool>(
  SearchLineOpen.new,
);

/// A field for what to find, the best match opening as it is typed, the
/// words marked on the page and the pages that have them listed beneath,
/// the one showing marked. The arrows or Tab step through them, Enter
/// keeps what is found marked, for n and N to step through, and Esc
/// forgets it.
class SearchLine extends ConsumerStatefulWidget {
  const SearchLine({super.key});

  /// How long typing pauses before the search runs.
  static const Duration typingPause = Duration(milliseconds: 250);

  /// How many pages found show before the list scrolls, unless it is sized
  /// by hand.
  static const int _listed = 6;

  static const double _width = 520;

  /// What it is laid out in, in an [area] so large, unless it is sized by
  /// hand.
  static BoxConstraints natural(Size area) {
    final width = area.width < _width ? area.width : _width;
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: height + 1 + _listed * _HitRow.height + 10,
    );
  }

  /// How tall the line typed in is: the least the search line is.
  static const double height = 40;

  @override
  ConsumerState<SearchLine> createState() => _SearchLineState();
}

class _SearchLineState extends ConsumerState<SearchLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: Motion.settle,
  );

  late final TextEditingController _query =
      TextEditingController(text: ref.read(searchQueryProvider))
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: ref.read(searchQueryProvider).length,
        );
  final FocusNode _field = FocusNode(debugLabel: 'Search line');
  final FocusNode? _before = FocusManager.instance.primaryFocus;
  Timer? _typing;

  SearchSession get _session => ref.read(searchSessionProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Taken from the page, which has it in the same scope.
    _field.requestFocus();
    // What was typed as the line opened is what is looked for; Enter typed
    // with it has looked already.
    final typed = ref.read(searchLineProvider.notifier)._typedAhead();
    if (typed.isEmpty) return;
    final lines = typed.split('\n');
    _query.value = TextEditingValue(
      text: lines.first,
      selection: TextSelection.collapsed(offset: lines.first.length),
    );
    if (lines.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(keep: true));
    } else {
      _changed(lines.first);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown.duration = context.motion.of(Motion.settle);
    if (!_shown.isAnimating && _shown.value == 0) unawaited(_shown.forward());
  }

  @override
  void dispose() {
    _shown.dispose();
    _typing?.cancel();
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _typing?.cancel();
    _typing = Timer(
      SearchLine.typingPause,
      () => unawaited(_session.search(text)),
    );
  }

  /// Closes the line, giving the keyboard back to whatever had it.
  void _close({required bool keep}) {
    if (!mounted) return;
    _typing?.cancel();
    if (keep) {
      // What is typed is searched for at once, not after the pause.
      if (_query.text != ref.read(searchQueryProvider)) {
        unawaited(_session.search(_query.text));
      }
    } else {
      _session.clear();
    }
    ref.read(searchLineProvider.notifier).close();
    final before = _before;
    if (before != null && before.context != null) before.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final results = ref.watch(searchResultsProvider).value;
    final showing = ref.watch(searchSessionProvider);
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    final hits = searching
        ? results ?? const <SearchHit>[]
        : const <SearchHit>[];
    final count = !searching || results == null
        ? ''
        : switch (results.length) {
            0 => 'No matches',
            1 => '1 page',
            final pages => '${showing + 1} of $pages',
          };
    return FloatingIn(
      animation: _shown,
      glass: true,
      alignment: Alignment.topCenter,
      child: Glass(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: SearchLine.height,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  Text(
                    '/',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tones.emphasis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.enter): () =>
                            _close(keep: true),
                        const SingleActivator(LogicalKeyboardKey.escape): () =>
                            _close(keep: false),
                        const SingleActivator(
                          LogicalKeyboardKey.arrowDown,
                        ): () =>
                            _session.step(1),
                        const SingleActivator(LogicalKeyboardKey.tab): () =>
                            _session.step(1),
                        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                            _session.step(-1),
                        const SingleActivator(
                          LogicalKeyboardKey.tab,
                          shift: true,
                        ): () =>
                            _session.step(-1),
                      },
                      child: TextField(
                        controller: _query,
                        focusNode: _field,
                        style: const TextStyle(fontSize: 14.5),
                        decoration: const InputDecoration(
                          hintText: 'Search all notes',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: _changed,
                      ),
                    ),
                  ),
                  KeyHint(count),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            if (hits.isNotEmpty) ...<Widget>[
              Divider(height: 1, color: tones.glassRim),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(5),
                  itemCount: hits.length,
                  itemExtent: _HitRow.height,
                  itemBuilder: (context, index) => _HitRow(
                    hit: hits[index],
                    current: index == showing,
                    onTap: () => _session.show(index),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A page found: its title, and where the words are in it, marked.
class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.current,
    required this.onTap,
  });

  final SearchHit hit;

  /// Whether it is the page showing.
  final bool current;
  final VoidCallback onTap;

  static const double height = 44;

  @override
  Widget build(BuildContext context) => RowTile(
    selected: current,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    title: Text(pageTitleOrPlaceholder(hit.title)),
    subtitle: Text.rich(highlightedSnippet(hit.snippet, context.tones)),
  );
}

/// Converts a snippet's marker characters into spans, the words found in
/// the accent.
///
/// SQLite marks the matched terms with two control characters chosen because
/// they cannot occur in a note, so a page containing markup cannot fake a
/// highlight.
TextSpan highlightedSnippet(String snippet, Tones tones) {
  final children = <InlineSpan>[];
  var index = 0;

  while (index < snippet.length) {
    final start = snippet.indexOf(SnippetMarkers.start, index);
    if (start < 0) {
      children.add(TextSpan(text: snippet.substring(index)));
      break;
    }
    if (start > index) {
      children.add(TextSpan(text: snippet.substring(index, start)));
    }

    final end = snippet.indexOf(SnippetMarkers.end, start + 1);
    if (end < 0) {
      children.add(TextSpan(text: snippet.substring(start + 1)));
      break;
    }
    children.add(
      TextSpan(
        text: snippet.substring(start + 1, end),
        style: TextStyle(color: tones.emphasis, fontWeight: FontWeight.w700),
      ),
    );
    index = end + 1;
  }

  return TextSpan(
    style: TextStyle(fontSize: 11.5, color: tones.muted),
    children: children,
  );
}

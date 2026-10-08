/// A chooser: a line to type a few letters into, over what they match, to
/// take from the keyboard — a page to open, a command to run, a typeface.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modes/key_catch.dart';
import 'controls.dart';
import 'floating_pane.dart';
import 'glass.dart';
import 'motion.dart';
import 'tones.dart';

/// Something a chooser offers.
@immutable
class Choice {
  const Choice({
    required this.title,
    required this.run,
    this.detail,
    this.hint,
    this.enabled = true,
    this.runAside,
    this.titleStyle,
  });

  final String title;

  /// Where it is, or what it does.
  final String? detail;

  /// Beside it: its kind, or its shortcut.
  final String? hint;
  final bool enabled;

  /// Takes it, once the chooser has closed.
  final VoidCallback run;

  /// Takes it aside — in a tab of its own, say — with Ctrl+Enter.
  final VoidCallback? runAside;

  /// How its title is set, where it shows what it is: a typeface's name in
  /// that typeface.
  final TextStyle? titleStyle;
}

/// What a chooser offers for what is typed, read through [ref] so it is
/// offered again as what it reads changes.
typedef ChoicesFor = List<Choice> Function(WidgetRef ref, String typed);

/// Opens a chooser over the window, with [initial] typed: [choicesFor]
/// gives what it offers, [hintFor] what the empty line says, and
/// [keysFor] the keys it answers to, along its foot.
Future<void> showChooser(
  BuildContext context, {
  required ChoicesFor choicesFor,
  required String Function(String typed) hintFor,
  List<String> Function(String typed)? keysFor,
  String initial = '',
}) {
  // What is typed as it opens is typed into it, Enter taking the first.
  final ahead = TypeAhead();
  return showAppDialog<void>(
    context: context,
    overGlass: true,
    builder: (context) => Chooser(
      choicesFor: choicesFor,
      hintFor: hintFor,
      keysFor: keysFor,
      initial: initial,
      ahead: ahead,
    ),
  ).whenComplete(ahead.take);
}

/// The chooser itself: a field over the choices it matches, the first
/// highlighted, stepped through with the arrow keys and taken with Enter.
class Chooser extends ConsumerStatefulWidget {
  const Chooser({
    required this.choicesFor,
    required this.hintFor,
    this.keysFor,
    this.initial = '',
    this.ahead,
    super.key,
  });

  final ChoicesFor choicesFor;
  final String Function(String typed) hintFor;
  final List<String> Function(String typed)? keysFor;
  final String initial;

  /// What was typed as it opened, to type into it.
  final TypeAhead? ahead;

  /// The keys every chooser answers to.
  static const List<String> keys = <String>[
    'Up Down  choose',
    'Enter  take',
    'Esc  close',
  ];

  static const double _rowHeight = 40;

  @override
  ConsumerState<Chooser> createState() => _ChooserState();
}

class _ChooserState extends ConsumerState<Chooser> {
  late final TextEditingController _query;
  final ScrollController _scroll = ScrollController();
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    final lines = (widget.ahead?.take() ?? '').split('\n');
    _query = TextEditingController(text: '${widget.initial}${lines.first}');
    if (lines.length > 1) {
      // Enter typed ahead takes the first of what was typed for.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final choices = widget.choicesFor(ref, _query.text);
        if (choices.firstOrNull case final first? when first.enabled) {
          _close(first.run);
        }
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Closes the chooser, then does [action] — so a dialog it opens opens
  /// over the window, not over the chooser.
  void _close(VoidCallback action) {
    Navigator.of(context).pop();
    scheduleMicrotask(action);
  }

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _highlight = (_highlight + by).clamp(0, count - 1));
    final top = _highlight * Chooser._rowHeight;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + Chooser._rowHeight >
        position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + Chooser._rowHeight - position.viewportDimension);
    }
  }

  KeyEventResult _onKey(KeyEvent event, List<Choice> choices) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, choices.length);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, choices.length);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _move(8, choices.length);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _move(-8, choices.length);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_highlight < choices.length) {
        final choice = choices[_highlight];
        final aside = choice.runAside;
        if (HardwareKeyboard.instance.isControlPressed && aside != null) {
          _close(aside);
        } else if (choice.enabled) {
          _close(choice.run);
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
    final typed = _query.text;
    final choices = widget.choicesFor(ref, typed);
    if (_highlight >= choices.length) _highlight = 0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: FloatingPane(
        pane: Pane.chooser,
        natural: (area) => BoxConstraints(
          maxWidth: math.min(area.width, 600),
          maxHeight: math.min(area.height, 460),
        ),
        // Its top always in the same place, however many it offers.
        position: (area, size) =>
            Offset((area.width - size.width) / 2, area.height * 0.12),
        minSize: const Size(300, 140),
        child: Glass(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Focus(
                onKeyEvent: (_, event) => _onKey(event, choices),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: widget.hintFor(typed),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (_) => setState(() => _highlight = 0),
                ),
              ),
              Divider(color: context.tones.glassRim),
              Flexible(
                child: choices.isEmpty
                    ? SizedBox(
                        height: 64,
                        child: EmptyMessage(
                          typed.isEmpty ? 'Nothing here yet' : 'No match',
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(4),
                        itemExtent: Chooser._rowHeight,
                        itemCount: choices.length,
                        itemBuilder: (context, index) {
                          final choice = choices[index];
                          return _ChoiceRow(
                            choice: choice,
                            highlighted: index == _highlight,
                            onTap: choice.enabled
                                ? () => _close(choice.run)
                                : null,
                          );
                        },
                      ),
              ),
              PaneDragArea(
                child: _Footer(
                  keys: widget.keysFor?.call(typed) ?? Chooser.keys,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.highlighted,
    required this.onTap,
  });

  final Choice choice;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final hint = choice.hint;
    final style = TextStyle(
      color: choice.enabled ? tones.text : tones.faint,
      fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
    );
    return RowTile(
      selected: highlighted,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      titleStyle: choice.titleStyle?.merge(style) ?? style,
      title: Text(choice.title),
      subtitle: choice.detail == null ? null : Text(choice.detail!),
      trailing: hint == null ? null : KeyHint(hint),
    );
  }
}

/// The keys a chooser answers to, along its foot.
class _Footer extends StatelessWidget {
  const _Footer({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.tones.glassRim)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Wrap(
        spacing: 16,
        children: <Widget>[for (final key in keys) KeyHint(key)],
      ),
    ),
  );
}

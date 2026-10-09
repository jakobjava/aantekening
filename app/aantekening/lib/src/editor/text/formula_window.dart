/// The source of a long formula, typed in a window of its own rather than
/// beneath its line, where it would wind down the box as a long, thin strip.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../look/appearance.dart';
import '../../look/glass.dart';
import '../../look/motion.dart';
import '../../look/tones.dart';
import '../../preferences.dart';
import 'math_syntax.dart';

/// The source of the formula being edited as its window shows it.
@immutable
class FormulaWindowSource {
  const FormulaWindowSource({
    required this.value,
    this.marks = const <({TextRange range, Color color})>[],
    this.problem,
    this.latexOnly = false,
  });

  /// The source, and the selection in it.
  final TextEditingValue value;

  /// What the highlights in the source mark, each drawn on its colour.
  final List<({TextRange range, Color color})> marks;

  /// What keeps the source from being typeset as it stands.
  final String? problem;

  /// Whether the formula can only be typed as LaTeX.
  final bool latexOnly;

  @override
  bool operator ==(Object other) =>
      other is FormulaWindowSource &&
      other.value == value &&
      listEquals(other.marks, marks) &&
      other.problem == problem &&
      other.latexOnly == latexOnly;

  @override
  int get hashCode =>
      Object.hash(value, Object.hashAll(marks), problem, latexOnly);
}

/// Where the source of the formula being edited is typed: beneath its line,
/// or in a window of its own once it grows long, and back beneath the line
/// only once it is a good deal shorter again, so it does not go back and
/// forth while what is typed is about as long as the limit. A source on
/// more than one line, as LaTeX brought in keeps its pictures and
/// environments, is typed in a window however long it is: beneath the line
/// Enter finishes the formula, so its lines could not be kept.
@immutable
class FormulaWindow {
  const FormulaWindow({this.opensPast = usual});

  /// The limit unless another is set.
  static const int usual = 80;

  /// The limits that can be set, from shortest to longest.
  static const int least = 30;
  static const int most = 300;

  /// How much shorter than [opensPast] a source goes back beneath its line.
  static const int margin = 20;

  /// The longest source typed beneath its line; a longer one is typed in a
  /// window.
  final int opensPast;

  /// The shortest source typed in a window; a shorter one goes back beneath
  /// its line.
  int get closesBelow => opensPast - margin;

  /// Whether [source] is typed in a window, given whether it is [already].
  bool holds(String source, {required bool already}) {
    if (source.contains('\n')) return true;
    return already ? source.length >= closesBelow : source.length > opensPast;
  }

  @override
  bool operator ==(Object other) =>
      other is FormulaWindow && other.opensPast == opensPast;

  @override
  int get hashCode => opensPast.hashCode;
}

/// How long a formula's source grows before it is typed in a window,
/// remembered between sessions.
class FormulaWindowController extends Notifier<FormulaWindow> {
  static const String _key = 'math.windowPast';

  @override
  FormulaWindow build() => switch (ref.preference(_key)) {
    final int past => FormulaWindow(
      opensPast: past.clamp(FormulaWindow.least, FormulaWindow.most),
    ),
    _ => const FormulaWindow(),
  };

  /// Sends sources longer than [opensPast] to a window.
  void set(int opensPast) {
    final past = opensPast.clamp(FormulaWindow.least, FormulaWindow.most);
    if (past == state.opensPast) return;
    state = FormulaWindow(opensPast: past);
    ref.savePreference(_key, past == FormulaWindow.usual ? null : past);
  }
}

final formulaWindowProvider =
    NotifierProvider<FormulaWindowController, FormulaWindow>(
      FormulaWindowController.new,
    );

/// Shows the source of the formula being edited in a window of its own,
/// as long as [source] holds one, telling [onChanged] of every change made
/// in it. The window goes when [source] becomes null, the source handed
/// back to the line, or when it is closed, the formula finished; the
/// future says which: true for the second.
///
/// The source of a TikZ picture in the text is typed in the same window
/// ([picture]): there, as in Insert LaTeX, Enter starts a new line and
/// Ctrl+Enter finishes, and there is no syntax to choose.
Future<bool> showFormulaWindow(
  BuildContext context, {
  required ValueListenable<FormulaWindowSource?> source,
  required ValueChanged<TextEditingValue> onChanged,
  bool picture = false,
}) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => _FormulaWindow(
        source: source,
        onChanged: onChanged,
        picture: picture,
      ),
    ) ??
    true;

/// Opens [source], a TikZ picture's, in the window formulas are typed in,
/// telling [onChanged] of each change, for the picture to be drawn again
/// as it is typed, with what keeps it from being drawn shown beneath.
Future<void> editTikzSource(
  BuildContext context, {
  required String source,
  required ValueChanged<String> onChanged,
}) async {
  FormulaWindowSource shown(TextEditingValue value) => FormulaWindowSource(
    value: value,
    problem: value.text.trim().isEmpty
        ? null
        : MathView.problemIn(value.text, preamble: MathPreamble.read(context)),
    latexOnly: true,
  );
  // The caret at the start, the source read from its top.
  final window = ValueNotifier<FormulaWindowSource?>(
    shown(
      TextEditingValue(
        text: source,
        selection: const TextSelection.collapsed(offset: 0),
      ),
    ),
  );
  await showFormulaWindow(
    context,
    source: window,
    picture: true,
    onChanged: (value) {
      if (value.text != window.value?.value.text) onChanged(value.text);
      window.value = shown(value);
    },
  );
}

class _FormulaWindow extends ConsumerStatefulWidget {
  const _FormulaWindow({
    required this.source,
    required this.onChanged,
    required this.picture,
  });

  final ValueListenable<FormulaWindowSource?> source;
  final ValueChanged<TextEditingValue> onChanged;
  final bool picture;

  @override
  ConsumerState<_FormulaWindow> createState() => _FormulaWindowState();
}

class _FormulaWindowState extends ConsumerState<_FormulaWindow> {
  late FormulaWindowSource _shown = widget.source.value!;
  late final _SourceController _controller = _SourceController(_shown);

  /// How long a pause in typing ends one undo step and begins another.
  static const Duration _pause = Duration(milliseconds: 600);

  /// The source as it was before each step typed here, the last first, and
  /// the steps undone, to be redone: each with the caret as it was then, so
  /// undoing goes back to where the change was made, not where the window
  /// opened.
  final List<TextEditingValue> _past = <TextEditingValue>[];
  final List<TextEditingValue> _future = <TextEditingValue>[];

  /// What the field last held, and when its text last changed.
  late TextEditingValue _last = _controller.value;
  DateTime _lastChange = DateTime(0);

  /// Whether the field is being set, not typed in.
  bool _setting = false;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onSource);
    _controller.addListener(_onEdited);
  }

  @override
  void dispose() {
    widget.source.removeListener(_onSource);
    _controller.dispose();
    super.dispose();
  }

  /// The formula has changed outside the window — the syntax switched, or
  /// what was typed here came back — or its source is to go back to its
  /// line.
  void _onSource() {
    final source = widget.source.value;
    if (source == null) {
      Navigator.of(context).pop(false);
      return;
    }
    if (source == _shown) return;
    setState(() => _shown = source);
    _controller.marks = source.marks;
    // What the input method is composing stays, unless the source changed —
    // its syntax switched — when what was typed before cannot be undone
    // here.
    if (!_showsHere(source.value)) {
      _set(source.value);
      _past.clear();
      _future.clear();
    }
  }

  /// Puts [value] in the field, not as a step typed.
  void _set(TextEditingValue value) {
    _setting = true;
    _controller.value = value;
    _setting = false;
    _lastChange = DateTime(0);
  }

  /// Undoes the last step typed, or redoes the last undone if not [back].
  void _step({required bool back}) {
    final from = back ? _past : _future;
    if (from.isEmpty) return;
    (back ? _future : _past).add(_controller.value);
    _set(from.removeLast());
  }

  /// Whether the field shows [value], whatever is being composed in it.
  bool _showsHere(TextEditingValue value) =>
      _controller.text == value.text &&
      _controller.selection == value.selection;

  void _onEdited() {
    final value = _controller.value;
    if (!_setting && value.text != _last.text) {
      // A run of typing is one step, as it is in the text.
      final now = DateTime.now();
      if (_past.isEmpty || now.difference(_lastChange) > _pause) {
        _past.add(_last);
      }
      _lastChange = now;
      _future.clear();
    }
    _last = value;
    if (_showsHere(_shown.value)) return;
    widget.onChanged(value);
  }

  void _done() => Navigator.of(context).pop(true);

  void _switchSyntax() {
    if (_shown.latexOnly) return;
    final syntax = ref.read(mathSyntaxProvider);
    ref
        .read(mathSyntaxProvider.notifier)
        .set(syntax == MathMode.latex ? MathMode.linear : MathMode.latex);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _shown.problem;
    final picture = widget.picture;
    return CallbackShortcuts(
      // As beneath the line: Enter finishes the formula, Ctrl+Shift+M
      // switches its syntax. Shift+Enter is a new line. A picture's source
      // is finished with Ctrl+Enter.
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(LogicalKeyboardKey.enter, control: picture): _done,
        SingleActivator(LogicalKeyboardKey.numpadEnter, control: picture):
            _done,
        if (!picture)
          const SingleActivator(
            LogicalKeyboardKey.keyM,
            control: true,
            shift: true,
          ): _switchSyntax,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _step(back: true),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () =>
            _step(back: false),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            _step(back: false),
      },
      child: GlassDialog(
        title: Text(picture ? 'TikZ picture' : 'Formula'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // As tall as the source, until the window fills the screen;
              // only then does it scroll.
              Flexible(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(
                    fontFamily: InterfaceFont.mono.family,
                    fontSize: 13,
                  ),
                ),
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    problem,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: context.tones.emphasis,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actionsAlignment: picture
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceBetween,
        actions: <Widget>[
          if (!picture) MathSyntaxToggle(latexOnly: _shown.latexOnly),
          FilledButton(
            onPressed: _done,
            child: Text(picture ? 'Done  (Ctrl+Enter)' : 'Done  (Enter)'),
          ),
        ],
      ),
    );
  }
}

/// The source, its highlights drawn on their colours.
class _SourceController extends TextEditingController {
  _SourceController(FormulaWindowSource source)
    : marks = source.marks,
      super.fromValue(source.value);

  List<({TextRange range, Color color})> marks;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    // What the input method is composing is underlined as usual.
    if (marks.isEmpty || (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(
        context: context,
        withComposing: withComposing,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    var at = 0;
    for (final mark in marks) {
      if (mark.range.start < at || mark.range.end > text.length) continue;
      spans
        ..add(TextSpan(text: text.substring(at, mark.range.start)))
        ..add(
          TextSpan(
            text: text.substring(mark.range.start, mark.range.end),
            style: TextStyle(backgroundColor: mark.color),
          ),
        );
      at = mark.range.end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

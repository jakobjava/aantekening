/// A quiz taken a question at a time: an option chosen, the right one
/// shown with why, and at the end the score and the questions missed, to
/// take again.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import 'math_text.dart';
import 'sources_view.dart';

class QuizView extends StatefulWidget {
  const QuizView({
    required this.quiz,
    required this.onOpen,
    this.scrolls = true,
    super.key,
  });

  /// Whether it scrolls itself, rather than lying in something that does.
  final bool scrolls;

  final QuizSet quiz;
  final void Function(Citation citation) onOpen;

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  final FocusNode _focus = FocusNode(debugLabel: 'quiz');

  /// The questions of this round, by index into the quiz.
  late List<int> _round = <int>[
    for (var i = 0; i < widget.quiz.questions.length; i++) i,
  ];
  int _at = 0;

  /// The option chosen for the question showing, once one is.
  int? _chosen;
  final List<int> _missed = <int>[];

  QuizQuestion get _question => widget.quiz.questions[_round[_at]];
  bool get _finished => _at >= _round.length;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _choose(int option) {
    if (_chosen != null || _finished) return;
    setState(() {
      _chosen = option;
      if (option != _question.answer) _missed.add(_round[_at]);
    });
  }

  void _next() {
    if (_chosen == null) return;
    setState(() {
      _at++;
      _chosen = null;
    });
    _focus.requestFocus();
  }

  void _restart({bool missedOnly = false}) => setState(() {
    _round = missedOnly
        ? List<int>.of(_missed)
        : <int>[for (var i = 0; i < widget.quiz.questions.length; i++) i];
    _missed.clear();
    _at = 0;
    _chosen = null;
  });

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _finished) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _next();
      return KeyEventResult.handled;
    }
    const keys = <List<LogicalKeyboardKey>>[
      <LogicalKeyboardKey>[LogicalKeyboardKey.digit1, LogicalKeyboardKey.keyA],
      <LogicalKeyboardKey>[LogicalKeyboardKey.digit2, LogicalKeyboardKey.keyB],
      <LogicalKeyboardKey>[LogicalKeyboardKey.digit3, LogicalKeyboardKey.keyC],
      <LogicalKeyboardKey>[LogicalKeyboardKey.digit4, LogicalKeyboardKey.keyD],
    ];
    for (final (i, pair) in keys.indexed) {
      if (pair.contains(key) && i < _question.options.length) {
        _choose(i);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_round.isEmpty) return const SizedBox.shrink();
    final quiz = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _finished ? _result(context) : _asking(context),
      ),
    );
    return Focus(
      focusNode: _focus,
      autofocus: widget.scrolls,
      onKeyEvent: _key,
      child: widget.scrolls
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: quiz,
            )
          : Padding(padding: const EdgeInsets.only(bottom: 12), child: quiz),
    );
  }

  Widget _asking(BuildContext context) {
    final tones = context.tones;
    final question = _question;
    final chosen = _chosen;
    final right = chosen == question.answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Question ${_at + 1} of ${_round.length}',
              style: TextStyle(fontSize: 12.5, color: tones.muted),
            ),
            const Spacer(),
            // One square a question: filled once got right, hollow once
            // missed, marked while asked.
            for (var i = 0; i < _round.length; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: i < _at
                      ? (_missed.contains(_round[i]) ? null : tones.text)
                      : i == _at
                      ? tones.emphasis
                      : tones.line,
                  border: i < _at && _missed.contains(_round[i])
                      ? Border.all(color: tones.text)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          decoration: BoxDecoration(
            color: tones.base,
            border: Border.all(color: tones.strongLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MathText(
                question.question,
                style: TextStyle(
                  fontSize: 19,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: tones.text,
                ),
              ),
              const SizedBox(height: 18),
              for (final (i, option) in question.options.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Option(
                    letter: String.fromCharCode(0x41 + i),
                    text: option,
                    state: chosen == null
                        ? _OptionState.open
                        : i == question.answer
                        ? _OptionState.right
                        : i == chosen
                        ? _OptionState.wrong
                        : _OptionState.other,
                    onTap: () => _choose(i),
                  ),
                ),
              if (chosen != null) ...<Widget>[
                const SizedBox(height: 8),
                _Explanation(
                  right: right,
                  answer: String.fromCharCode(0x41 + question.answer),
                  explanation: question.explanation,
                  sources: question.sources,
                  onOpen: widget.onOpen,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: 'Enter',
            child: FilledButton(
              onPressed: chosen == null ? null : _next,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _at + 1 < _round.length
                        ? 'Next question'
                        : 'See how it went',
                  ),
                  const SizedBox(width: 8),
                  const Mark(MarkShape.arrowRight),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final total = _round.length;
    final right = total - _missed.length;
    final share = total == 0 ? 0.0 : right / total;
    return Column(
      children: <Widget>[
        const SizedBox(height: 12),
        Text('$right / $total', style: theme.textTheme.displaySmall),
        const SizedBox(height: 10),
        SizedBox(width: 240, child: LinearProgressIndicator(value: share)),
        const SizedBox(height: 14),
        Text(
          share == 1
              ? 'All right — well done.'
              : share >= 0.7
              ? 'Good — a few to look at again.'
              : 'Worth another look.',
          style: theme.textTheme.titleMedium,
        ),
        if (_missed.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          const Align(
            alignment: Alignment.centerLeft,
            child: SmallCaps('Missed'),
          ),
          const SizedBox(height: 8),
          for (final i in _missed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: tones.base,
                border: Border.all(color: tones.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  MathText(
                    widget.quiz.questions[i].question,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  MathText(
                    'Answer: ${widget.quiz.questions[i].options[widget.quiz.questions[i].answer]}',
                    style: TextStyle(color: tones.emphasis),
                  ),
                  if (widget.quiz.questions[i].sources.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    SourceLine(
                      sources: widget.quiz.questions[i].sources,
                      onOpen: widget.onOpen,
                    ),
                  ],
                ],
              ),
            ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: <Widget>[
            if (_missed.isNotEmpty)
              FilledButton(
                onPressed: () => _restart(missedOnly: true),
                child: Text('Try the ${_missed.length} missed again'),
              ),
            OutlinedButton(
              onPressed: _restart,
              child: const Text('Start over'),
            ),
          ],
        ),
      ],
    );
  }
}

enum _OptionState { open, right, wrong, other }

class _Option extends StatelessWidget {
  const _Option({
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String letter;
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final marked = state == _OptionState.right || state == _OptionState.wrong;
    // The right answer marked in the accent, the wrong one chosen in the
    // text's colour: told apart by their marks, not by red and green.
    final edge = switch (state) {
      _OptionState.right => tones.emphasis,
      _OptionState.wrong => tones.text,
      _ => tones.line,
    };
    return Opacity(
      opacity: state == _OptionState.other ? 0.5 : 1,
      child: Material(
        color: state == _OptionState.right ? tones.selection : tones.base,
        child: InkWell(
          onTap: state == _OptionState.open ? onTap : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border.all(color: edge, width: marked ? 1.5 : 1),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: marked ? edge : tones.strongLine),
                  ),
                  child: switch (state) {
                    _OptionState.right => Mark(
                      MarkShape.check,
                      color: tones.emphasis,
                    ),
                    _OptionState.wrong => Mark(
                      MarkShape.close,
                      color: tones.text,
                    ),
                    _ => Text(
                      letter,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tones.muted,
                      ),
                    ),
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MathText(
                    text,
                    style: TextStyle(fontSize: 15, color: tones.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the option chosen was right, and why the right one is.
class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.right,
    required this.answer,
    required this.explanation,
    required this.sources,
    required this.onOpen,
  });

  final bool right;
  final String answer;
  final String explanation;
  final List<Citation> sources;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: tones.pane,
        border: Border(
          left: BorderSide(
            color: right ? tones.emphasis : tones.text,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            right ? 'Right.' : 'Not quite — it is $answer.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: right ? tones.emphasis : tones.text,
            ),
          ),
          if (explanation.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            MathText(
              explanation,
              style: TextStyle(fontSize: 14, height: 1.5, color: tones.muted),
            ),
          ],
          if (sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            SourceLine(sources: sources, onOpen: onOpen),
          ],
        ],
      ),
    );
  }
}

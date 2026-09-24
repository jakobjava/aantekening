/// A quiz taken a question at a time: an option chosen, the right one
/// shown with why, and at the end the score and the questions missed, to
/// take again.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'math_text.dart';
import 'sources_view.dart';
import 'study_style.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = StudyKind.quiz.accent(scheme);
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
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            for (var i = 0; i < _round.length; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _at
                      ? (_missed.contains(_round[i])
                            ? const Color(0xFFD64545)
                            : accent)
                      : i == _at
                      ? accent.withValues(alpha: 0.45)
                      : scheme.surfaceContainerHighest,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
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
                  color: scheme.onSurface,
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
          child: FilledButton.icon(
            icon: const Icon(Icons.arrow_forward_rounded),
            iconAlignment: IconAlignment.end,
            label: Text(
              _at + 1 < _round.length ? 'Next question' : 'See how it went',
            ),
            onPressed: chosen == null ? null : _next,
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = StudyKind.quiz.accent(scheme);
    final total = _round.length;
    final right = total - _missed.length;
    final share = total == 0 ? 0.0 : right / total;
    return Column(
      children: <Widget>[
        const SizedBox(height: 12),
        SizedBox.square(
          dimension: 120,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: share,
                  strokeWidth: 9,
                  color: accent,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              Text(
                '$right / $total',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: SmallCaps('Missed', color: scheme.error),
          ),
          const SizedBox(height: 8),
          for (final i in _missed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
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
                    '✓ ${widget.quiz.questions[i].options[widget.quiz.questions[i].answer]}',
                    style: const TextStyle(color: Color(0xFF2E9E5B)),
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
              FilledButton.icon(
                icon: const Icon(Icons.replay_rounded),
                label: Text('Try the ${_missed.length} missed again'),
                onPressed: () => _restart(missedOnly: true),
              ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Start over'),
              onPressed: _restart,
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
    final scheme = Theme.of(context).colorScheme;
    const right = Color(0xFF2E9E5B);
    const wrong = Color(0xFFD64545);
    final color = switch (state) {
      _OptionState.right => right,
      _OptionState.wrong => wrong,
      _ => scheme.outline,
    };
    final filled = state == _OptionState.right || state == _OptionState.wrong;
    return Opacity(
      opacity: state == _OptionState.other ? 0.55 : 1,
      child: Material(
        color: filled ? color.withValues(alpha: 0.09) : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: state == _OptionState.open ? onTap : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: filled ? color : scheme.outlineVariant,
                width: filled ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: filled ? color : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: switch (state) {
                    _OptionState.right => const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    _OptionState.wrong => const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    _ => Text(
                      letter,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MathText(
                    text,
                    style: TextStyle(fontSize: 15, color: scheme.onSurface),
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
    final scheme = Theme.of(context).colorScheme;
    final color = right ? const Color(0xFF2E9E5B) : const Color(0xFFD64545);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            right ? 'Right.' : 'Not quite — it is $answer.',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          if (explanation.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            MathText(
              explanation,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
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

/// How an answer is coming along, shown while it comes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';

import 'ai_session.dart';

/// The steps [pending] has taken, each with how long it took, and the one
/// it is on, counting up: what the model is reading and how much, what it
/// is thinking, how fast it writes. So a slow model is seen to be working.
class AnswerProgress extends StatefulWidget {
  const AnswerProgress({required this.pending, super.key});

  final PendingTurn pending;

  /// How long a model on this computer reads before it is said why.
  static const Duration slowReading = Duration(seconds: 15);

  @override
  State<AnswerProgress> createState() => _AnswerProgressState();
}

class _AnswerProgressState extends State<AnswerProgress> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pending;
    final progress = pending.progress;
    final now = DateTime.now();
    final took = now.difference(pending.since);
    final scheme = Theme.of(context).colorScheme;
    final faint = TextStyle(fontSize: 12, color: scheme.outline);

    final speed = _speed(progress.written - pending.writtenBefore, took);
    final details = <Widget>[
      if (progress.stage == AgentStage.thinking &&
          progress.reasoning.trim().isNotEmpty)
        _Reasoning(text: progress.reasoning, live: true),
      if (progress.stage == AgentStage.reading &&
          pending.local &&
          took >= AnswerProgress.slowReading)
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 2),
          child: Text(
            'Models on this computer take a while to read, the first '
            'question of a conversation longest. It is working.',
            style: faint,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final step in pending.steps) _StepRow(step: step),
          _Row(
            leading: const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
            label: '${progress.activity}…',
            detail: speed,
            took: wholeSeconds(took),
            strong: true,
          ),
          ...details,
        ],
      ),
    );
  }

  /// How fast [written] characters in [took] are, in tokens a second —
  /// once there is enough to tell.
  static String? _speed(int written, Duration took) {
    if (written < 40 || took.inMilliseconds < 1000) return null;
    final perSecond = written / 4 / (took.inMilliseconds / 1000);
    return '~${perSecond.round()} tokens/s';
  }
}

/// A step done with, and how long it took; a step of thinking opens to
/// what was thought.
class _StepRow extends StatefulWidget {
  const _StepRow({required this.step});

  final AiStep step;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final scheme = Theme.of(context).colorScheme;
    final thought = step.reasoning.trim().isNotEmpty;
    final row = _Row(
      leading: Icon(Icons.check_rounded, size: 14, color: scheme.outline),
      label: thought ? 'Thought' : step.activity,
      took: _took(step.took),
      trailing: thought
          ? Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 16,
              color: scheme.outline,
            )
          : null,
    );
    if (!thought) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _open = !_open),
          child: row,
        ),
        if (_open) _Reasoning(text: step.reasoning, live: false),
      ],
    );
  }

  /// A step's time: tenths of a second under ten, whole seconds after.
  static String _took(Duration took) => took.inMilliseconds < 10000
      ? '${(took.inMilliseconds / 1000).toStringAsFixed(1)} s'
      : wholeSeconds(took);
}

/// One line of the progress.
class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.label,
    required this.took,
    this.detail,
    this.trailing,
    this.strong = false,
  });

  final Widget leading;
  final String label;
  final String took;
  final String? detail;
  final Widget? trailing;

  /// Whether it is the step being taken, rather than one done with.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faint = TextStyle(fontSize: 12, color: scheme.outline);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 16, child: Center(child: leading)),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: strong ? scheme.onSurfaceVariant : scheme.outline,
                    ),
                  ),
                ),
                if (detail != null) Text('  ·  $detail', style: faint),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            took,
            style: faint.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a model reasoned, set apart and faint: while it thinks, its last
/// lines as they come; after, all of it.
class _Reasoning extends StatelessWidget {
  const _Reasoning({required this.text, required this.live});

  final String text;
  final bool live;

  /// How many of the last lines show while it thinks.
  static const int _lines = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 12,
      height: 1.4,
      fontStyle: FontStyle.italic,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
    );
    final shown = text.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(7, 2, 0, 4),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
      ),
      child: live
          ? Text(
              _tail(shown),
              maxLines: _lines,
              overflow: TextOverflow.fade,
              style: style,
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(shown, style: style),
              ),
            ),
    );
  }

  /// The last lines of [text], about as much as shows.
  static String _tail(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final last = lines.skip(math.max(0, lines.length - _lines)).join('\n');
    return last.length <= 240 ? last : '…${last.substring(last.length - 240)}';
  }
}

/// [took] in whole seconds, and minutes past a minute.
String wholeSeconds(Duration took) {
  final seconds = took.inSeconds;
  return seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min ${seconds % 60} s';
}

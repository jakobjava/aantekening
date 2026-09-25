/// What to type for each structure and symbol of a formula, beside the page.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../look/appearance.dart';
import '../../look/controls.dart';
import '../../look/marks.dart';
import '../../look/tones.dart';
import '../../preferences.dart';
import 'math_syntax.dart';
import 'math_templates.dart';

/// Whether the cheat sheet is open, remembered between sessions.
class CheatSheetController extends Notifier<bool> {
  static const String _key = 'math.cheatSheet';

  @override
  bool build() => ref.preference(_key) == true;

  void toggle() {
    state = !state;
    ref.savePreference(_key, state ? true : null);
  }
}

final cheatSheetProvider = NotifierProvider<CheatSheetController, bool>(
  CheatSheetController.new,
);

/// The Simple syntax, subject by subject, each example spelled in the syntax
/// formulas are typed in and typeset beside it.
///
/// Clicking an example writes it into the formula being edited, or into a
/// new one, through [onInsert]; without it the examples are only shown.
/// Nothing here takes the keyboard, so the caret stays in the text box.
class CheatSheet extends ConsumerWidget {
  const CheatSheet({required this.onInsert, super.key});

  static const double width = 300;

  /// Each topic's heading, followed by its examples.
  static final List<(SyntaxTopic, SyntaxExample?)> _rows =
      <(SyntaxTopic, SyntaxExample?)>[
        for (final topic in SimpleSyntaxGuide.topics) ...[
          (topic, null),
          for (final example in topic.examples) (topic, example),
        ],
      ];

  final ValueChanged<MathTemplate>? onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final syntax = ref.watch(mathSyntaxProvider);

    return ExcludeFocus(
      child: Material(
        color: tones.pane,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PaneHeader(
                title: 'Cheat sheet',
                trailing: MarkButton(
                  MarkShape.close,
                  tooltip: 'Close the cheat sheet',
                  onPressed: ref.read(cheatSheetProvider.notifier).toggle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: <Widget>[
                    const MathSyntaxToggle(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        onInsert == null
                            ? 'What to type'
                            : 'What to type; click one to write it',
                        style: TextStyle(fontSize: 11.5, color: tones.muted),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) => switch (_rows[index]) {
                    (final topic, null) => _TopicHeading(topic.title),
                    (_, final example?) => _ExampleRow(
                      example: example,
                      syntax: syntax,
                      onInsert: onInsert,
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicHeading extends StatelessWidget {
  const _TopicHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
    child: SmallCaps(title),
  );
}

class _ExampleRow extends StatelessWidget {
  const _ExampleRow({
    required this.example,
    required this.syntax,
    required this.onInsert,
  });

  final SyntaxExample example;
  final MathMode syntax;
  final ValueChanged<MathTemplate>? onInsert;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final typed = syntax == MathMode.latex ? example.latex : example.typed;
    final insert = onInsert;

    return InkWell(
      onTap: insert == null
          ? null
          : () => insert(
              MathTemplate.spaced(
                example.meaning,
                simple: example.typed,
                latex: example.latex,
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    typed,
                    style: TextStyle(
                      fontFamily: InterfaceFont.mono.family,
                      fontSize: 12.5,
                      color: tones.text,
                    ),
                  ),
                  Text(
                    example.meaning,
                    style: TextStyle(fontSize: 11, color: tones.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: MathView(
                  source: example.latex,
                  mode: MathMode.latex,
                  textStyle: TextStyle(fontSize: 15, color: tones.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

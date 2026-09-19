/// What to type for each structure and symbol of a formula, beside the page.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../preferences.dart';
import '../../shell/library_pane.dart';
import '../../theme.dart';
import 'math_syntax.dart';
import 'math_templates.dart';
import 'text_styles.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final syntax = ref.watch(mathSyntaxProvider);

    return ExcludeFocus(
      child: Material(
        color: AppTheme.paneColor(scheme),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PaneHeader(
                title: 'Cheat sheet',
                actionIcon: Icons.close_rounded,
                actionTooltip: 'Close the cheat sheet',
                onAction: ref.read(cheatSheetProvider.notifier).toggle,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: <Widget>[
                    const MathSyntaxToggle(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        onInsert == null
                            ? 'What to type'
                            : 'What to type; click one to write it',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
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
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
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
    final scheme = Theme.of(context).colorScheme;
    final typed = syntax == MathMode.latex ? example.latex : example.typed;
    final insert = onInsert;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
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
                    style: RichTextStyles.monospace.copyWith(
                      fontSize: 12.5,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    example.meaning,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
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
                  textStyle: TextStyle(fontSize: 15, color: scheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

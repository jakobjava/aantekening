/// A summary set out as a study sheet: the gist, the ideas under numbered
/// headings, the formulas each in a box, and what goes beyond the notes
/// apart — every point numbered to the sentence of the notes it comes from.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';

import 'math_text.dart';
import 'sources_view.dart';
import 'study_style.dart';

class SummarySheet extends StatelessWidget {
  const SummarySheet({
    required this.summary,
    required this.onOpen,
    this.fallbackTitle = '',
    super.key,
  });

  final StudySummary summary;
  final void Function(Citation citation) onOpen;

  /// The title when the summary has none of its own.
  final String fallbackTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = StudyKind.summary.accent(scheme);
    final footnotes = Footnotes()
      ..numberAll(<List<Citation>>[
        for (final section in summary.sections)
          for (final point in section.points) point.sources,
        for (final formula in summary.formulas) formula.sources,
      ]);
    final body = TextStyle(fontSize: 15, height: 1.55, color: scheme.onSurface);
    List<InlineSpan> marks(List<Citation> sources) => sources.isEmpty
        ? const <InlineSpan>[]
        : <InlineSpan>[footnoteMarks(sources, footnotes, onOpen: onOpen)];

    final title = summary.title.isNotEmpty ? summary.title : fallbackTitle;
    return StudyPaper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SmallCaps('Summary', color: accent),
          if (title.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
          if (summary.gist.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SmallCaps('In short', color: accent),
                  const SizedBox(height: 4),
                  MathText(summary.gist, style: body.copyWith(fontSize: 16)),
                ],
              ),
            ),
          for (final (i, section) in summary.sections.indexed) ...<Widget>[
            const SizedBox(height: 26),
            Row(
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MathText(
                    section.heading,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final point in section.points)
              Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 9, right: 12),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: MathText(
                        point.text,
                        style: body,
                        trailing: marks(point.sources),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (summary.formulas.isNotEmpty) ...<Widget>[
            const SizedBox(height: 30),
            SmallCaps('Formulas', color: accent),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 560 ? 2 : 1;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final formula in summary.formulas)
                      SizedBox(
                        width: width,
                        child: _FormulaCard(
                          formula: formula,
                          marks: marks(formula.sources),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (summary.beyond.isNotEmpty) ...<Widget>[
            const SizedBox(height: 30),
            _Beyond(lines: summary.beyond, style: body),
          ],
          const SizedBox(height: 26),
          SourceList(footnotes: footnotes, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _FormulaCard extends StatelessWidget {
  const _FormulaCard({required this.formula, required this.marks});

  final StudyFormula formula;
  final List<InlineSpan> marks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MathView(
              source: formula.latex,
              mode: MathMode.latex,
              displayStyle: true,
              textStyle: TextStyle(fontSize: 19, color: scheme.onSurface),
            ),
          ),
          if (formula.meaning.isNotEmpty || marks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            MathText(
              formula.meaning,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
              trailing: marks,
            ),
          ],
        ],
      ),
    );
  }
}

/// What the model adds that the notes do not say, set apart so it is never
/// taken for them.
class _Beyond extends StatelessWidget {
  const _Beyond({required this.lines, required this.style});

  final List<String> lines;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_outlined,
                size: 15,
                color: OriginColors.model(scheme),
              ),
              const SizedBox(width: 6),
              const SmallCaps('Beyond your notes'),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'from the model, not from what you wrote',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: MathText(
                line,
                style: style.copyWith(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A sheet of paper a study set is set out on, centred on the page.
class StudyPaper extends StatelessWidget {
  const StudyPaper({required this.child, this.maxWidth = 780, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          padding: const EdgeInsets.fromLTRB(36, 30, 36, 24),
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
          child: SelectionArea(child: child),
        ),
      ),
    );
  }
}

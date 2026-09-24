/// The key terms, as a glossary: each term beside what it means, numbered
/// to where the notes say it, and a filter to find one.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';

import 'math_text.dart';
import 'sources_view.dart';
import 'study_style.dart';
import 'summary_sheet.dart';

class GlossaryView extends StatefulWidget {
  const GlossaryView({
    required this.glossary,
    required this.onOpen,
    this.scrolls = true,
    super.key,
  });

  /// Whether it scrolls itself, rather than lying in something that does.
  final bool scrolls;

  final Glossary glossary;
  final void Function(Citation citation) onOpen;

  @override
  State<GlossaryView> createState() => _GlossaryViewState();
}

class _GlossaryViewState extends State<GlossaryView> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = StudyKind.terms.accent(scheme);
    final filter = _filter.toLowerCase();
    final terms = <GlossaryTerm>[
      for (final term in widget.glossary.terms)
        if (filter.isEmpty ||
            term.term.toLowerCase().contains(filter) ||
            term.meaning.toLowerCase().contains(filter))
          term,
    ];
    final footnotes = Footnotes()
      ..numberAll(<List<Citation>>[for (final term in terms) term.sources]);
    final paper = StudyPaper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SmallCaps('Key terms', color: accent),
              const Spacer(),
              if (widget.glossary.terms.length > 8)
                SizedBox(
                  width: 220,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      hintText: 'Find a term',
                    ),
                    onChanged: (text) => setState(() => _filter = text),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, term) in terms.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final termText = MathText(
                    term.term,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  );
                  final meaning = MathText(
                    term.meaning,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: scheme.onSurface,
                    ),
                    trailing: <InlineSpan>[
                      if (term.sources.isNotEmpty)
                        footnoteMarks(
                          term.sources,
                          footnotes,
                          onOpen: widget.onOpen,
                        ),
                    ],
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        termText,
                        const SizedBox(height: 4),
                        meaning,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(width: 190, child: termText),
                      const SizedBox(width: 16),
                      Expanded(child: meaning),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
          SourceList(footnotes: footnotes, onOpen: widget.onOpen),
        ],
      ),
    );
    return widget.scrolls ? SingleChildScrollView(child: paper) : paper;
  }
}

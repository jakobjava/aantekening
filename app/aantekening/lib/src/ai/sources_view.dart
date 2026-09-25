/// Where what the AI says comes from, shown: small numbers after what they
/// support, the sentence each points at on hover, and a list of them
/// beneath — the person's notes kept apart from the web.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import 'math_text.dart';

/// How where something comes from is shown, the same everywhere: the
/// person's notes in the interface's mark, the web more quietly and in a
/// box, and the model's own words fainter still.
abstract final class Origins {
  static Color colourOf(SourceOrigin? origin, Tones tones) => switch (origin) {
    SourceOrigin.notes => tones.emphasis,
    SourceOrigin.web => tones.muted,
    null => tones.faint,
  };

  static String nameOf(SourceOrigin origin) => switch (origin) {
    SourceOrigin.notes => 'Notes',
    SourceOrigin.web => 'Web',
  };
}

/// A number for each place cited, in the order first cited: each sentence
/// of the notes, each web page, once however often it is cited.
class Footnotes {
  final List<Citation> _cited = <Citation>[];

  /// [citation]'s number, from one.
  int number(Citation citation) {
    final at = _cited.indexWhere((c) => c.uri == citation.uri);
    if (at >= 0) return at + 1;
    _cited.add(citation);
    return _cited.length;
  }

  /// Numbers [citations], in reading order, before anything showing them
  /// is laid out — which may be later than the list of them is.
  void numberAll(Iterable<List<Citation>> citations) {
    for (final group in citations) {
      group.forEach(number);
    }
  }

  /// What was cited, in the order of its numbers.
  List<Citation> get cited => List<Citation>.unmodifiable(_cited);

  bool get isEmpty => _cited.isEmpty;
}

/// Superscript numbers for [citations], after the words they support:
/// coloured by where they come from, the sentence cited on hover, and a
/// click opens it.
WidgetSpan footnoteMarks(
  List<Citation> citations,
  Footnotes footnotes, {
  required void Function(Citation citation) onOpen,
}) => WidgetSpan(
  alignment: PlaceholderAlignment.top,
  child: Padding(
    padding: const EdgeInsets.only(left: 1),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final citation in <Citation>{...citations})
          FootnoteMark(
            citation: citation,
            number: footnotes.number(citation),
            onOpen: onOpen,
          ),
      ],
    ),
  ),
);

/// One superscript number: what it cites shows on hover, and a click opens
/// the very place.
class FootnoteMark extends StatelessWidget {
  const FootnoteMark({
    required this.citation,
    required this.number,
    required this.onOpen,
    super.key,
  });

  final Citation citation;
  final int number;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final color = Origins.colourOf(citation.origin, tones);
    final web = citation.origin == SourceOrigin.web;
    return Tooltip(
      richMessage: _preview(citation, tones),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      constraints: const BoxConstraints(maxWidth: 360),
      waitDuration: const Duration(milliseconds: 200),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onOpen(citation),
          child: Container(
            constraints: const BoxConstraints(minWidth: 15),
            margin: const EdgeInsets.only(left: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: web ? null : tones.selection,
              border: web ? Border.all(color: tones.line) : null,
            ),
            child: Text(
              '$number',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static TextSpan _preview(Citation citation, Tones tones) {
    final quote = _quoteOf(citation);
    // A tooltip is the text's colour, with the base's on it.
    final on = tones.base;
    return TextSpan(
      children: <InlineSpan>[
        TextSpan(
          text: citation.origin == SourceOrigin.notes
              ? 'YOUR NOTES  ·  '
              : 'THE WEB  ·  ',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
            color: on.withValues(alpha: 0.7),
          ),
        ),
        TextSpan(
          text: citation.title,
          style: TextStyle(fontWeight: FontWeight.w600, color: on),
        ),
        if (quote.isNotEmpty)
          TextSpan(
            // A tooltip shows text alone: formulas in their LaTeX.
            text: '\n“${quote.replaceAll(r'$', '')}”',
            style: TextStyle(height: 1.45, color: on.withValues(alpha: 0.9)),
          ),
        TextSpan(
          text: '\nClick to open it',
          style: TextStyle(fontSize: 11, color: on.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}

/// What [citation] quotes, on one line, not too long to read at a glance.
String _quoteOf(Citation citation, {int max = 220}) {
  final quote = (citation.quote ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\*\*|==|~~'), '')
      .trim();
  return quote.length > max ? '${quote.substring(0, max)}…' : quote;
}

/// Where a card, a question or a term comes from, as a line to click: the
/// page, and the sentence.
class SourceLine extends StatelessWidget {
  const SourceLine({required this.sources, required this.onOpen, super.key});

  final List<Citation> sources;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    final tones = context.tones;
    final first = sources.first;
    final color = Origins.colourOf(first.origin, tones);
    final quote = _quoteOf(first, max: 140);
    return Material(
      color: tones.pane,
      child: InkWell(
        onTap: () => onOpen(first),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(
            children: <Widget>[
              SmallCaps(Origins.nameOf(first.origin), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: first.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: tones.text,
                        ),
                      ),
                      if (quote.isNotEmpty)
                        TextSpan(
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: tones.muted,
                          ),
                          children: MathText.spans(
                            '  “$quote”',
                            TextStyle(fontSize: 12.5, color: tones.muted),
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (sources.length > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: KeyHint('+${sources.length - 1}'),
                ),
              const SizedBox(width: 6),
              Mark(MarkShape.chevronRight, size: 10, color: tones.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The places [footnotes] numbers, listed: the person's notes by page,
/// each sentence quoted after its number, and the web after.
class SourceList extends StatelessWidget {
  const SourceList({required this.footnotes, required this.onOpen, super.key});

  final Footnotes footnotes;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final cited = footnotes.cited;
    if (cited.isEmpty) return const SizedBox.shrink();

    // The notes by page, in the order first cited; the web after.
    final pages = <String, List<(int, Citation)>>{};
    final web = <(int, Citation)>[];
    for (final (i, citation) in cited.indexed) {
      if (citation.origin == SourceOrigin.web) {
        web.add((i + 1, citation));
      } else {
        final page = NoteLink.tryParse(citation.uri)?.id ?? citation.uri;
        (pages[page] ??= <(int, Citation)>[]).add((i + 1, citation));
      }
    }

    Widget heading(String label, SourceOrigin origin) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: SmallCaps(label, color: Origins.colourOf(origin, tones)),
    );

    Widget entry(int number, Citation citation, {String? text}) {
      final color = Origins.colourOf(citation.origin, tones);
      return InkWell(
        onTap: () => onOpen(citation),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: MathText(
                  text ?? '“${_quoteOf(citation)}”',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: tones.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tones.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (pages.isNotEmpty) heading('From your notes', SourceOrigin.notes),
          for (final entries in pages.values) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Text(
                entries.first.$2.title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final (n, citation) in entries)
              if (_quoteOf(citation).isNotEmpty) entry(n, citation),
          ],
          if (web.isNotEmpty) heading('From the web', SourceOrigin.web),
          for (final (n, citation) in web)
            entry(
              n,
              citation,
              text:
                  '${citation.title} — ${Uri.tryParse(citation.uri)?.host ?? citation.uri}',
            ),
        ],
      ),
    );
  }
}

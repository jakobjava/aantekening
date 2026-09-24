/// An AI answer on screen: its Markdown, its formulas, and what it cites.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'flashcards_view.dart';
import 'quiz_view.dart';
import 'sources_view.dart';

/// [answer], rendered: each stretch that draws on a source followed by
/// small numbers for the sentences it cites, what comes from neither the
/// notes nor the web ruled grey down its side, and what it cites listed
/// beneath, quoted.
class AnswerView extends StatelessWidget {
  const AnswerView({
    required this.answer,
    required this.onOpen,
    this.showSources = true,
    this.onAddCards,
    super.key,
  });

  final AiAnswer answer;

  /// Opens a cited source.
  final void Function(Citation citation) onOpen;
  final bool showSources;

  /// Adds flashcards an answer holds to those of what it is about.
  final ValueChanged<List<StudyCard>>? onAddCards;

  @override
  Widget build(BuildContext context) {
    final footnotes = Footnotes();
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: <md.InlineSyntax>[
        _CitationSyntax(),
        _MathSyntax(),
        _HighlightSyntax(),
      ],
      encodeHtml: false,
    ).parse(answer.markdown);
    final builder = _Blocks(context, answer, footnotes, onOpen, onAddCards);
    final blocks = builder.blocks(nodes);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...blocks,
          if (showSources && builder.ownKnowledge)
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: _OwnKnowledgeKey(),
            ),
          if (showSources && !footnotes.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SourceList(footnotes: footnotes, onOpen: onOpen),
          ],
        ],
      ),
    );
  }
}

/// What the grey rule down an answer's side means.
class _OwnKnowledgeKey extends StatelessWidget {
  const _OwnKnowledgeKey();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 2.5,
          height: 12,
          color: OriginColors.model(scheme).withValues(alpha: 0.5),
        ),
        const SizedBox(width: 7),
        Text(
          'From the model’s own knowledge, not from your notes',
          style: TextStyle(fontSize: 11.5, color: scheme.outline),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ inline syntax

/// `⟦1,3⟧`: the citations of the stretch before it.
class _CitationSyntax extends md.InlineSyntax {
  _CitationSyntax()
    : super('${AiAnswer.markerOpen}([0-9,]+)${AiAnswer.markerClose}');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('cite')..attributes['n'] = match[1]!);
    return true;
  }
}

/// `$…$` in a sentence, `$$…$$` on its own: LaTeX.
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax() : super(r'\$\$([\s\S]+?)\$\$|\$([^\s$](?:[^$\n]*?[^\s$])?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    parser.addNode(
      md.Element.empty('math')
        ..attributes['tex'] = (match[1] ?? match[2])!
        ..attributes['display'] = '$display',
    );
    return true;
  }
}

/// `==…==`: highlighted, as the notes highlight.
class _HighlightSyntax extends md.DelimiterSyntax {
  _HighlightSyntax()
    : super(
        '=+',
        requiresDelimiterRun: true,
        allowIntraWord: true,
        tags: <md.DelimiterTag>[md.DelimiterTag('mark', 2)],
      );
}

// ------------------------------------------------------------------ blocks

class _Blocks {
  _Blocks(
    this.context,
    this.answer,
    this.footnotes,
    this.onOpen,
    this.onAddCards,
  ) : theme = Theme.of(context),
      scheme = Theme.of(context).colorScheme;

  final BuildContext context;
  final AiAnswer answer;
  final Footnotes footnotes;
  final void Function(Citation citation) onOpen;
  final ValueChanged<List<StudyCard>>? onAddCards;
  final ThemeData theme;
  final ColorScheme scheme;

  /// Whether any of the answer is from the model's own knowledge, ruled
  /// grey — once the blocks are built.
  bool ownKnowledge = false;

  TextStyle get _body =>
      theme.textTheme.bodyMedium!.copyWith(fontSize: 14.5, height: 1.5);

  List<Widget> blocks(List<md.Node> nodes) => <Widget>[
    for (final node in nodes) ?_block(node),
  ];

  Widget? _block(md.Node node) {
    if (node is md.Text) {
      return node.text.trim().isEmpty
          ? null
          : _ruled(node, _paragraph(<md.Node>[node]));
    }
    if (node is! md.Element) return null;
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'p':
        return _ruled(node, _paragraph(children));
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 14 : 10, bottom: 4),
          child: _paragraph(
            children,
            style: _body.copyWith(
              fontSize: switch (level) {
                1 => 20,
                2 => 17.5,
                _ => 15.5,
              },
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        );
      case 'ul' || 'ol':
        return _ruled(
          node,
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final (i, item)
                    in children.whereType<md.Element>().indexed)
                  _listItem(
                    item,
                    node.tag == 'ol' ? '${_start(node) + i}.' : '•',
                  ),
              ],
            ),
          ),
        );
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.outlineVariant, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: blocks(children),
          ),
        );
      case 'pre':
        return _fenced(node);
      case 'table':
        return _table(node);
      case 'hr':
        return const Divider(height: 24);
    }
    return _ruled(node, _paragraph(<md.Node>[node]));
  }

  int _start(md.Element list) =>
      int.tryParse(list.attributes['start'] ?? '') ?? 1;

  Widget _listItem(md.Element item, String marker) {
    final children = item.children ?? const <md.Node>[];
    final inline = children.every(
      (child) =>
          child is md.Text || (child is md.Element && !_isBlock(child.tag)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 22,
            child: Text(
              marker,
              style: _body.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: inline
                ? _paragraph(children, bottom: 2)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: blocks(children),
                  ),
          ),
        ],
      ),
    );
  }

  static bool _isBlock(String tag) => const <String>{
    'p',
    'ul',
    'ol',
    'pre',
    'blockquote',
    'table',
    'hr',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  }.contains(tag);

  /// [child], ruled grey down its left if nothing in [node] cites a
  /// source while the answer cites some — the model's own knowledge.
  Widget _ruled(md.Node node, Widget child) {
    if (answer.citations.isEmpty || _cites(node)) {
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: child);
    }
    ownKnowledge = true;
    return Tooltip(
      message: 'From the model’s own knowledge, not from your notes',
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: OriginColors.model(scheme).withValues(alpha: 0.4),
              width: 2.5,
            ),
          ),
        ),
        child: child,
      ),
    );
  }

  /// Whether [node] cites anything, anywhere in it.
  static bool _cites(md.Node node) =>
      node is md.Element &&
      (node.tag == 'cite' || (node.children ?? const <md.Node>[]).any(_cites));

  Widget _paragraph(
    List<md.Node> nodes, {
    TextStyle? style,
    double bottom = 8,
  }) {
    final base = style ?? _body;
    // A formula alone in its paragraph is set on its own, in the middle.
    final only = nodes
        .where((n) => !(n is md.Text && n.text.trim().isEmpty))
        .toList();
    if (only.length == 1 &&
        only.single is md.Element &&
        (only.single as md.Element).tag == 'math') {
      return Padding(
        padding: EdgeInsets.only(bottom: bottom, top: 4),
        child: Center(
          child: _math(only.single as md.Element, base, display: true),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text.rich(
        TextSpan(style: base, children: _inline(nodes, base)),
        textScaler: TextScaler.noScaling,
      ),
    );
  }

  List<InlineSpan> _inline(List<md.Node> nodes, TextStyle style) =>
      <InlineSpan>[for (final node in nodes) ..._span(node, style)];

  List<InlineSpan> _span(md.Node node, TextStyle style) {
    if (node is md.Text) return <InlineSpan>[TextSpan(text: node.text)];
    if (node is! md.Element) return const <InlineSpan>[];
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        return _styled(children, style.copyWith(fontWeight: FontWeight.w700));
      case 'em':
        return _styled(children, style.copyWith(fontStyle: FontStyle.italic));
      case 'del':
        return _styled(
          children,
          style.copyWith(decoration: TextDecoration.lineThrough),
        );
      case 'mark':
        return _styled(
          children,
          style.copyWith(backgroundColor: const Color(0x66FFD60A)),
        );
      case 'code':
        return <InlineSpan>[
          TextSpan(
            text: node.textContent,
            style: style.copyWith(
              fontFamily: 'monospace',
              fontSize: (style.fontSize ?? 14) * 0.92,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ];
      case 'br':
        return const <InlineSpan>[TextSpan(text: '\n')];
      case 'a':
        final href = node.attributes['href'] ?? '';
        return <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _Link(
              label: node.textContent,
              style: style.copyWith(
                color: scheme.primary,
                decoration: TextDecoration.underline,
              ),
              onTap: () => onOpen(
                Citation(
                  uri: href,
                  title: node.textContent,
                  origin: NoteLink.isNoteLink(href)
                      ? SourceOrigin.notes
                      : SourceOrigin.web,
                ),
              ),
            ),
          ),
        ];
      case 'math':
        return <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _math(
              node,
              style,
              display: node.attributes['display'] == 'true',
            ),
          ),
        ];
      case 'cite':
        final citations = answer.citationsOf(node.attributes['n']!);
        return <InlineSpan>[
          if (citations.isNotEmpty)
            footnoteMarks(citations, footnotes, onOpen: onOpen),
        ];
      case 'img':
        return const <InlineSpan>[];
    }
    return _styled(children, style);
  }

  List<InlineSpan> _styled(List<md.Node> children, TextStyle style) =>
      <InlineSpan>[TextSpan(style: style, children: _inline(children, style))];

  Widget _math(md.Element node, TextStyle style, {required bool display}) =>
      MathView(
        source: node.attributes['tex']!,
        mode: MathMode.latex,
        displayStyle: display,
        textStyle: style.copyWith(color: scheme.onSurface),
      );

  Widget _fenced(md.Element pre) {
    final code = pre.children?.whereType<md.Element>().firstOrNull;
    final language = (code?.attributes['class'] ?? '').replaceFirst(
      'language-',
      '',
    );
    final body = (code?.textContent ?? pre.textContent).trimRight();
    if (language == AnswerBlocks.flashcards) {
      final cards = AnswerBlocks.cardsIn(body);
      if (cards != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CardList(cards: cards, onOpen: onOpen, scrolls: false),
            if (onAddCards case final add?)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.style_outlined, size: 18),
                  label: const Text('Add these to my flashcards'),
                  onPressed: () => add(cards),
                ),
              ),
          ],
        );
      }
    }
    if (language == AnswerBlocks.quiz) {
      final questions = AnswerBlocks.questionsIn(body);
      if (questions != null) {
        return QuizView(
          quiz: QuizSet(questions),
          onOpen: onOpen,
          scrolls: false,
        );
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        body.replaceAll(AiAnswer.marker, ''),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }

  Widget _table(md.Element table) {
    final rows = <md.Element>[
      for (final section in table.children!.whereType<md.Element>())
        ...section.children!.whereType<md.Element>(),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: scheme.outlineVariant),
          children: <TableRow>[
            for (final (i, row) in rows.indexed)
              TableRow(
                decoration: i == 0
                    ? BoxDecoration(color: scheme.surfaceContainerHigh)
                    : null,
                children: <Widget>[
                  for (final cell in row.children!.whereType<md.Element>())
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: _paragraph(
                        cell.children ?? const <md.Node>[],
                        bottom: 0,
                        style: i == 0
                            ? _body.copyWith(fontWeight: FontWeight.w600)
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.style, required this.onTap});

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(label, style: style),
    ),
  );
}

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:test/test.dart';

const Citation speed = Citation(
  uri: 'aantekening://page/p1#element=b&block=0',
  title: 'Speed',
  origin: SourceOrigin.notes,
);
const Citation force = Citation(
  uri: 'aantekening://page/p2#element=b&block=0',
  title: 'Forces',
  origin: SourceOrigin.notes,
);
const Citation energy = Citation(
  uri: 'aantekening://page/p3#element=b&block=0',
  title: 'Energy',
  origin: SourceOrigin.notes,
);

const AiAnswer answer = AiAnswer(
  markdown:
      '## Motion\n'
      '\n'
      'Speed is distance over time⟦1⟧. It is measured in metres a second.\n'
      '\n'
      '- Force is \$m \\cdot a\$⟦2⟧.\n'
      '- Without a force, nothing changes.\n'
      '\n'
      '\$\$\n'
      'E = \\frac{1}{2} m v^2\n'
      '\$\$\n'
      '\n'
      'That is all⟦1,2⟧.',
  citations: <Citation>[speed, force],
);

void main() {
  String section(String selected) => answer.markdown.substring(
    answer.sectionOf(selected)!.start,
    answer.sectionOf(selected)!.end,
  );

  test('an answer is cut into the blocks it would be written again by', () {
    expect(
      AnswerSection.blocksOf(
        answer.markdown,
      ).map((b) => answer.markdown.substring(b.start, b.end)),
      <String>[
        '## Motion',
        'Speed is distance over time⟦1⟧. It is measured in metres a second.',
        r'- Force is $m \cdot a$⟦2⟧.',
        '- Without a force, nothing changes.',
        '\$\$\nE = \\frac{1}{2} m v^2\n\$\$',
        'That is all⟦1,2⟧.',
      ],
    );
  });

  test('what is selected is found as the whole blocks it lies in', () {
    expect(
      section('over time1. It is measured'),
      'Speed is distance over time⟦1⟧. It is measured in metres a second.',
      reason: 'the cited number drawn as a 1, and a part of a paragraph',
    );
    expect(
      section('Force is m·a2.\nWithout a force'),
      '- Force is \$m \\cdot a\$⟦2⟧.\n- Without a force, nothing changes.',
      reason: 'two list items, a formula drawn as other letters',
    );
    expect(
      section('metres a second.\n\n• Force is'),
      'Speed is distance over time⟦1⟧. It is measured in metres a second.\n'
      '\n'
      '- Force is \$m \\cdot a\$⟦2⟧.',
      reason: 'from a paragraph into a list',
    );
    expect(answer.sectionOf('Nothing like this is here at all.'), isNull);
    expect(answer.sectionOf('  1 2 '), isNull, reason: 'no words');
  });

  test('a part written again takes its place, and the citations are '
      'numbered again', () {
    final paragraph = answer.sectionOf('It is measured in metres')!;
    expect(
      answer.textOf(paragraph),
      'Speed is distance over time. It is measured in metres a second.',
    );
    final again = answer.replacing(
      paragraph,
      const AiAnswer(
        markdown:
            '\nSpeed is how far a thing goes in a time⟦1⟧, and energy '
            'grows with it⟦2⟧.\n',
        citations: <Citation>[speed, energy],
      ),
    );
    expect(
      again.markdown,
      '## Motion\n'
      '\n'
      'Speed is how far a thing goes in a time⟦1⟧, and energy grows with '
      'it⟦2⟧.\n'
      '\n'
      '- Force is \$m \\cdot a\$⟦3⟧.\n'
      '- Without a force, nothing changes.\n'
      '\n'
      '\$\$\n'
      'E = \\frac{1}{2} m v^2\n'
      '\$\$\n'
      '\n'
      'That is all⟦1,3⟧.',
    );
    expect(again.citations, <Citation>[speed, energy, force]);

    final without = answer.replacing(
      answer.sectionOf('Force is')!,
      const AiAnswer(markdown: '- Force moves things.'),
    );
    expect(without.citations, <Citation>[
      speed,
      force,
    ], reason: 'force is still cited at the end');
    expect(
      answer
          .replacing(
            AnswerSection(0, answer.markdown.length),
            const AiAnswer(markdown: 'New.'),
          )
          .citations,
      isEmpty,
      reason: 'what is cited no more is left out',
    );
  });

  test('a part is asked for again in its own language, as the person says', () {
    final asked = NoteAgent.rewriteRequest(
      'Speed is distance over time.',
      question: 'What is speed?',
      instruction: 'with an example',
    );
    expect(asked, contains('"What is speed?"'));
    expect(asked, contains('with an example'));
    expect(asked, contains('<part>\nSpeed is distance over time.\n</part>'));
    expect(asked, contains('in the language the part is written in'));
    expect(
      NoteAgent.rewriteRequest('x', question: 'q'),
      contains('clearer and more accurate'),
      reason: 'asked again without saying how',
    );
  });
}

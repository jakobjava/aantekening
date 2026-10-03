import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  test('what text brought from elsewhere keeps survives saving', () {
    const block = TextBlock(
      kind: TextBlockKind.bulleted,
      marker: '▪',
      align: BlockAlign.end,
      spacing: BlockSpacing(before: 3, after: 6, line: 14),
      indent: 1,
      runs: <TextRun>[
        TextRun(
          'x',
          TextMarks(font: 'Consolas', script: TextScript.superscript),
        ),
      ],
      cell: TableCell(1, 2, width: 96, shading: 0xFFFFFF00, borders: false),
    );
    expect(TextBlock.fromJson(block.toJson()), block);
    expect(block.toJson()['spacing'], <String, Object?>{
      'before': 3.0,
      'after': 6.0,
      'line': 14.0,
    });
  });

  test('a page written before these existed reads as it did', () {
    final block = TextBlock.fromJson(<String, Object?>{
      'runs': <Object?>[
        <String, Object?>{'text': 'plain'},
      ],
    });
    expect(block.marker, isNull);
    expect(block.align, BlockAlign.start);
    expect(block.spacing, isNull);
    expect(block.runs.single.marks, TextMarks.none);
  });

  test('Enter carries a line\'s layout and mark onto the next', () {
    const block = TextBlock(
      kind: TextBlockKind.bulleted,
      marker: '○',
      align: BlockAlign.center,
      spacing: BlockSpacing.tight,
      runs: <TextRun>[TextRun('ab')],
    );
    final split = RichTextEditing.splitBlock(<TextBlock>[
      block,
    ], const RichPosition(0, 1)).blocks;
    expect(split.last.marker, '○');
    expect(split.last.align, BlockAlign.center);
    expect(split.last.spacing, BlockSpacing.tight);
    expect(block.copyWith(kind: TextBlockKind.paragraph).marker, isNull);
  });

  test(
    'a TikZ picture is an object, its source kept, a formula read as one',
    () {
      const picture = BlockEmbed.tikz(
        '\\begin{tikzpicture}\n  \\draw (0,0) -- (1,0);\n\\end{tikzpicture}',
      );
      expect(BlockEmbed.fromJson(picture.toJson()), picture);
      expect(picture.copyWith(width: 90).source, picture.source);
      const box = TextElement(
        id: 'b',
        frame: Frame(x: 0, y: 0, width: 100, height: 100),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[TextBlock.embedded(picture)],
      );
      expect(box.assetIds, isEmpty, reason: 'it is stored in the text');

      // On the page by itself it is a picture of its own, and back in text
      // as large as it was there.
      final alone = picture.toElement(frame: box.frame, now: 1) as TikzElement;
      expect(alone.source, picture.source);
      final again = NoteElement.fromJson(alone.toJson());
      expect(again, isA<TikzElement>());
      expect((again! as TikzElement).source, picture.source);
      expect(alone.asEmbed.source, picture.source);
      expect(alone.asEmbed.width, box.frame.width);
      expect(alone.assetIds, isEmpty);

      // Kept as a formula alone on its line, it is read as a picture; in a
      // line of text it stays a formula.
      final formula = TextBlock(
        runs: <TextRun>[TextRun.imported(picture.source!)],
        align: BlockAlign.center,
      );
      final read = TextBlock.fromJson(formula.toJson());
      expect(read.embed, picture);
      expect(read.align, BlockAlign.center);
      const inLine = TextBlock(
        runs: <TextRun>[
          TextRun('A dot: '),
          TextRun.imported(r'\tikz\fill circle (1pt);'),
        ],
      );
      expect(TextBlock.fromJson(inLine.toJson()), inLine);
    },
  );

  test('attached files keep their names, and go on the page in a box', () {
    const embed = BlockEmbed(
      kind: EmbedKind.file,
      assetId: 'a',
      width: 200,
      height: 30,
      name: 'report.docx',
    );
    expect(BlockEmbed.fromJson(embed.toJson()), embed);
    final box = embed.toElement(
      frame: const Frame(x: 0, y: 0, width: 200, height: 30),
      now: 1,
    );
    expect((box as TextElement).blocks.single.embed, embed);
  });

  test('a page names its pictures and files anew', () {
    final document = PageDocument.empty(id: 'p')
        .withElementAdded(
          const ImageElement(
            id: 'i',
            frame: Frame(x: 0, y: 0, width: 1, height: 1),
            createdAt: 1,
            updatedAt: 1,
            assetId: 'old-picture',
          ),
        )
        .withElementAdded(
          const TextElement(
            id: 't',
            frame: Frame(x: 0, y: 0, width: 1, height: 1),
            createdAt: 1,
            updatedAt: 1,
            blocks: <TextBlock>[
              TextBlock.embedded(
                BlockEmbed(
                  kind: EmbedKind.file,
                  assetId: 'old-file',
                  width: 1,
                  height: 1,
                ),
              ),
            ],
          ),
        );
    final renamed = document.withAssetsRenamed(<String, String>{
      'old-picture': 'new-picture',
      'old-file': 'new-file',
    });
    expect(renamed.referencedAssetIds, <String>{'new-picture', 'new-file'});
  });
}

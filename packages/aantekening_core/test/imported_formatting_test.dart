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
          ImageElement(
            id: 'i',
            frame: const Frame(x: 0, y: 0, width: 1, height: 1),
            createdAt: 1,
            updatedAt: 1,
            assetId: 'old-picture',
          ),
        )
        .withElementAdded(
          TextElement(
            id: 't',
            frame: const Frame(x: 0, y: 0, width: 1, height: 1),
            createdAt: 1,
            updatedAt: 1,
            blocks: const <TextBlock>[
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

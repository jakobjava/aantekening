import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

/// A provider that answers with what it is given to say, in turn, and
/// keeps what it was asked.
class ScriptedProvider implements ChatProvider {
  ScriptedProvider(
    this.script, {
    this.capabilities = const ModelCapabilities(
      vision: true,
      tools: true,
      contextTokens: 100000,
    ),
  });

  final List<List<ChatEvent>> script;
  final ModelCapabilities capabilities;
  final List<ChatRequest> asked = <ChatRequest>[];

  @override
  String get name => 'Scripted';

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) async => capabilities;

  @override
  Stream<ChatEvent> chat(ChatRequest request) {
    asked.add(request);
    return Stream<ChatEvent>.fromIterable(script[asked.length - 1]);
  }

  @override
  Future<List<ModelInfo>> listModels() async => const <ModelInfo>[];

  @override
  void close() {}
}

TextElement box(String id, String text, {double y = 0}) => TextElement(
  id: id,
  frame: Frame(x: 0, y: y, width: 300, height: 60),
  createdAt: 0,
  updatedAt: 0,
  blocks: <TextBlock>[TextBlock.plain(text)],
);

/// A notebook of pages, each a page document, in memory.
class Notes implements NoteReader {
  Notes(this.pages);

  final Map<String, (String title, PageDocument document)> pages;
  final List<String> rendered = <String>[];

  @override
  Future<ScopeInfo?> scope(NoteLink link) async => ScopeInfo(
    link: link,
    title: link.kind == NoteLinkKind.page ? pages[link.id]!.$1 : 'Mechanics',
    path: const <String>['Physics'],
  );

  @override
  Future<List<PageEntry>> pagesIn(NoteLink scope) async => <PageEntry>[
    for (final entry in pages.entries)
      if (scope.kind != NoteLinkKind.page || scope.id == entry.key)
        PageEntry(
          id: entry.key,
          title: entry.value.$1,
          path: const <String>['Physics'],
        ),
  ];

  @override
  Future<PageDigest?> digest(String pageId) async {
    final page = pages[pageId];
    return page == null ? null : PageDigest.of(page.$2, title: page.$1);
  }

  @override
  Future<List<String>> searchPages(
    String query, {
    NoteLink? within,
    int limit = 10,
  }) async {
    final terms = SearchTerms.parse(query);
    return <String>[
      for (final entry in pages.entries)
        if (PageDigest.of(
          entry.value.$2,
          title: entry.value.$1,
        ).passages.any((p) => terms.matchesIn(p.text).isNotEmpty))
          entry.key,
    ];
  }

  @override
  Future<ImagePart?> render(String pageId, DigestVisual visual) async {
    rendered.add('$pageId/${visual.id}');
    return ImagePart(
      Uint8List(4),
      mediaType: 'image/png',
      label: visual.description,
    );
  }
}

final Notes notes = Notes(<String, (String, PageDocument)>{
  'p1': (
    'Speed',
    PageDocument(
      id: 'p1',
      elements: <NoteElement>[box('b1', 'Speed is distance over time.')],
    ),
  ),
  'p2': (
    'Forces',
    PageDocument(
      id: 'p2',
      elements: <NoteElement>[
        box('b2', 'Force is mass times acceleration.'),
        PdfElement(
          id: 'slide',
          frame: const Frame(x: 0, y: 200, width: 400, height: 500),
          createdAt: 0,
          updatedAt: 0,
          assetId: 'a',
          pageIndex: 0,
        ),
        InkElement(
          id: 'arrow',
          frame: const Frame(x: 50, y: 300, width: 40, height: 40),
          createdAt: 0,
          updatedAt: 0,
          strokes: <InkStroke>[
            InkStroke(
              tool: InkTool.pen,
              color: 0xFF000000,
              width: 2,
              points: Float32List.fromList(<double>[
                50,
                300,
                1,
                0,
                90,
                340,
                1,
                0,
              ]),
            ),
          ],
        ),
      ],
    ),
  ),
});

const ScopeInfo section = ScopeInfo(
  link: NoteLink.section('s'),
  title: 'Mechanics',
  path: <String>['Physics'],
);

void main() {
  test('the first question comes with the notes, an overview, and the '
      'writing over a PDF page to look at', () async {
    final provider = ScriptedProvider(<List<ChatEvent>>[
      <ChatEvent>[
        const TextDelta('Force is mass times acceleration.'),
        const MessageDone(
          ChatMessage(ChatRole.assistant, <ChatPart>[]),
          stop: StopReason.done,
        ),
      ],
    ]);
    final agent = NoteAgent(provider: provider, model: 'm', reader: notes);
    final last = await agent
        .ask(
          scope: section,
          history: const <ChatMessage>[],
          question: 'Explain force',
        )
        .last;

    final first = provider.asked.single.messages.single;
    final sources = first.parts.whereType<SourcesPart>().single.sources;
    expect(sources.map((s) => s.title), <String>[
      'Forces',
      'Speed',
    ], reason: 'the page about the question first');
    expect(first.parts.whereType<ImagePart>(), hasLength(1));
    expect(notes.rendered, <String>['p2/v1']);
    expect(first.text, contains('holds 2 pages'));
    expect(first.text, endsWith('Explain force'));
    expect(provider.asked.single.system, contains('section "Mechanics"'));
    expect(last.done, isTrue);
    expect(last.messages, hasLength(2), reason: 'the question and the answer');
  });

  test('runs the tools asked for, and answers with what they gave', () async {
    final provider = ScriptedProvider(<List<ChatEvent>>[
      <ChatEvent>[
        const TextDelta('Let me look.'),
        MessageDone(
          ChatMessage.assistant(const <ChatPart>[
            TextPart('Let me look.'),
            ToolCallPart(
              id: 't1',
              name: NoteTools.searchNotes,
              input: <String, Object?>{'query': 'speed', 'everywhere': true},
            ),
          ]),
          stop: StopReason.toolUse,
        ),
      ],
      <ChatEvent>[
        const TextDelta('Speed is distance over time.'),
        const CitedSpan(<Citation>[
          Citation(
            uri: 'aantekening://page/p1',
            title: 'Speed',
            origin: SourceOrigin.notes,
          ),
        ]),
        const MessageDone(
          ChatMessage(ChatRole.assistant, <ChatPart>[]),
          stop: StopReason.done,
        ),
      ],
    ]);
    final agent = NoteAgent(provider: provider, model: 'm', reader: notes);
    final progress = await agent
        .ask(
          scope: const ScopeInfo(
            link: NoteLink.page('p2'),
            title: 'Forces',
            path: <String>[],
          ),
          history: const <ChatMessage>[],
          question: 'And speed?',
        )
        .toList();

    expect(
      progress.map((p) => p.activity),
      contains('Searching all your notes for “speed”'),
    );
    final stages = <AgentStage>[];
    for (final p in progress) {
      if (p.stage != stages.lastOrNull) stages.add(p.stage);
    }
    expect(stages, <AgentStage>[
      AgentStage.gathering,
      AgentStage.reading,
      AgentStage.writing,
      AgentStage.working,
      AgentStage.reading,
      AgentStage.writing,
      AgentStage.done,
    ]);
    final reading = progress
        .where((p) => p.stage == AgentStage.reading)
        .map((p) => p.activity)
        .toList();
    expect(reading.first, startsWith('m is reading your question — 1 page, '));
    expect(reading.last, startsWith('m is reading what it found — about '));
    expect(
      progress.last.written,
      'Let me look.Speed is distance over time.'.length,
    );
    final results =
        provider.asked.last.messages.last.parts.single as ToolResultPart;
    final found = (results.content.single as SourcesPart).sources.single;
    expect(found.title, 'Speed');
    expect(
      found.passages.single.uri,
      'aantekening://page/p1#element=b1&block=0',
    );
    expect(
      progress.last.answer.markdown,
      'Let me look.\n\nSpeed is distance over time.⟦1⟧',
    );
    expect(progress.last.messages, hasLength(4));
  });

  test('a model that thinks its room away is said to have, and what to do '
      'about it', () async {
    final provider = ScriptedProvider(<List<ChatEvent>>[
      <ChatEvent>[
        const Reasoning('Hmm.'),
        const MessageDone(
          ChatMessage(ChatRole.assistant, <ChatPart>[]),
          stop: StopReason.maxTokens,
        ),
      ],
    ], capabilities: const ModelCapabilities(contextTokens: 4096));
    final last = await NoteAgent(
      provider: provider,
      model: 'm',
      reader: notes,
    ).ask(scope: section, history: const <ChatMessage>[], question: 'Hi').last;
    expect(last.answer.markdown, contains('thought until its room ran out'));
    expect(last.answer.markdown, contains('4.1k tokens'));
  });

  test('stopping breaks the request off at once, even while the model is '
      'still reading and has sent nothing', () async {
    final ollama = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final reading = Completer<void>();
    final brokenOff = Completer<void>();
    ollama.listen((socket) {
      var asked = '';
      socket.listen(
        (bytes) {
          asked += latin1.decode(bytes);
          if (asked.startsWith('POST /api/show')) {
            socket.write(
              'HTTP/1.1 404 Not Found\r\nconnection: close\r\n'
              'content-length: 0\r\n\r\n',
            );
            unawaited(socket.close());
          } else if (!reading.isCompleted) {
            // Reads for as long as it takes, answering nothing meanwhile.
            reading.complete();
          }
        },
        onDone: () {
          if (asked.startsWith('POST /api/chat')) brokenOff.complete();
        },
      );
    });
    addTearDown(ollama.close);

    final provider = OllamaProvider(
      name: 'Ollama',
      baseUrl: 'http://127.0.0.1:${ollama.port}',
    );
    addTearDown(provider.close);
    final asking = NoteAgent(
      provider: provider,
      model: 'm',
      reader: notes,
    ).ask(scope: section, history: const <ChatMessage>[], question: 'Hi');
    final subscription = asking.listen(null);
    await reading.future;

    await subscription.cancel().timeout(const Duration(seconds: 1));
    await brokenOff.future.timeout(const Duration(seconds: 1));
  });

  test('a model without tools is given the passages about each later '
      'question', () async {
    final provider = ScriptedProvider(<List<ChatEvent>>[
      <ChatEvent>[
        const MessageDone(
          ChatMessage(ChatRole.assistant, <ChatPart>[]),
          stop: StopReason.done,
        ),
      ],
    ], capabilities: const ModelCapabilities(contextTokens: 8000));
    final agent = NoteAgent(provider: provider, model: 'm', reader: notes);
    await agent
        .ask(
          scope: section,
          history: <ChatMessage>[
            ChatMessage.user(const <ChatPart>[TextPart('Hi')]),
            ChatMessage.assistant(const <ChatPart>[TextPart('Hello')]),
          ],
          question: 'What about acceleration?',
        )
        .last;
    final asked = provider.asked.single;
    expect(asked.tools, isEmpty);
    final sources = asked.messages.last.parts.whereType<SourcesPart>().single;
    expect(sources.sources.single.title, 'Forces');
  });

  test('a section too big for the budget is named, page by page', () async {
    final built = await NoteContext(
      notes,
    ).build(section, budget: const ContextBudget(characters: 40, images: 0));
    expect(built.sources.map((s) => s.title), <String>['Speed']);
    expect(built.overview, contains('"Forces"'));
    expect(built.overview, contains('not given here'));
  });

  test('a worksheet is written out with its visual named once, and the '
      'answer typed onto it saying so', () {
    final digest = PageDigest.of(
      PageDocument(
        id: 'ws',
        elements: <NoteElement>[
          const PdfElement(
            id: 'sheet',
            frame: Frame(x: 0, y: 0, width: 600, height: 800),
            createdAt: 0,
            updatedAt: 0,
            assetId: 'a',
            pageIndex: 0,
            extractedText: 'Aufgabe 1',
          ),
          box('answer', 'v = 12 m/s', y: 100),
        ],
      ),
      title: 'Arbeitsblatt',
    );
    final texts = NoteContext.pageSource(
      digest,
    ).passages.map((p) => p.text).toList();
    expect(texts.where((t) => t.startsWith('[Visual v1')), hasLength(1));
    expect(texts, contains('v = 12 m/s'));
    expect(texts.last, contains('typed onto page 1 of a PDF'));
  });

  test(
    'a broken tool input is handed back to the model to try again',
    () async {
      final result = await NoteTools(reader: notes, scope: section).run(
        const ToolCallPart(
          id: 't',
          name: NoteTools.readPage,
          input: <String, Object?>{'__invalid_json': '{"page_id": "p'},
        ),
      );
      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextPart).text,
        contains('INVALID_JSON'),
      );
    },
  );
}

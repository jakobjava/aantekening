import 'dart:convert';
import 'dart:typed_data';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_ai/src/sse.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A page of notes as a source, its passages linked to their paragraphs.
const Source lecture = Source(
  uri: 'aantekening://page/p1',
  title: 'Lecture 1',
  origin: SourceOrigin.notes,
  context: 'Physics › Mechanics',
  passages: <SourcePassage>[
    SourcePassage(
      'Speed is distance over time.',
      uri: 'aantekening://page/p1#element=b&block=0',
    ),
    SourcePassage(
      'Acceleration is change of speed.',
      uri: 'aantekening://page/p1#element=b&block=1',
    ),
  ],
);

String sse(List<Map<String, Object?>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

/// A server answering every request with [body], and keeping what it was
/// sent.
({http.Client client, List<http.BaseRequest> sent, List<String> bodies}) server(
  String body, {
  int status = 200,
}) {
  final sent = <http.BaseRequest>[];
  final bodies = <String>[];
  final client = MockClient.streaming((request, stream) async {
    sent.add(request);
    bodies.add(await stream.bytesToString());
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  });
  return (client: client, sent: sent, bodies: bodies);
}

ChatRequest question(String text, {List<ToolSpec> tools = const []}) =>
    ChatRequest(
      model: 'claude-opus-5',
      system: 'Be brief.',
      messages: <ChatMessage>[
        ChatMessage.user(<ChatPart>[
          const SourcesPart(<Source>[lecture]),
          TextPart(text),
        ]),
      ],
      tools: tools,
      webSearch: true,
    );

const ToolSpec readTool = ToolSpec(
  name: 'read_page',
  description: 'Reads a page.',
  parameters: <String, Map<String, Object?>>{
    'page_id': <String, Object?>{'type': 'string'},
  },
  required: <String>['page_id'],
);

void main() {
  test('server-sent events are read whole, however they arrive', () async {
    final events = await serverEvents(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode('event: a\nda'),
        utf8.encode('ta: {"x":1}\n\n: comment\ndata: two\ndata: lines\n\n'),
      ]),
    ).toList();
    expect(
      events.map((ServerEvent e) => (e.event, e.data)),
      <(String?, String)>[('a', '{"x":1}'), (null, 'two\nlines')],
    );
  });

  group('Anthropic', () {
    test('gives notes as search results, and asks with tools, search and '
        'a fallback', () {
      final body = AnthropicProvider(
        apiKey: 'k',
      ).body(question('How fast?', tools: const <ToolSpec>[readTool]));
      final content =
          ((body['messages']! as List).single as Map)['content']! as List;
      expect(content.first, <String, Object?>{
        'type': 'search_result',
        'source': 'aantekening://page/p1',
        'title': 'Lecture 1 — Physics › Mechanics',
        'content': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'Speed is distance over time.',
          },
          <String, Object?>{
            'type': 'text',
            'text': 'Acceleration is change of speed.',
          },
        ],
        'citations': <String, Object?>{'enabled': true},
      });
      final tools = body['tools']! as List;
      expect((tools.first as Map)['eager_input_streaming'], isTrue);
      expect((tools.last as Map)['type'], 'web_search_20260209');
      expect(body['fallbacks'], 'default');
      expect(body['cache_control'], <String, Object?>{'type': 'ephemeral'});
    });

    test('streams text, cites the passage it drew on, and keeps the turn '
        'as it came', () async {
      final fake = server(
        sse(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'message_start',
            'message': <String, Object?>{
              'usage': <String, Object?>{'input_tokens': 100},
            },
          },
          <String, Object?>{
            'type': 'content_block_start',
            'index': 0,
            'content_block': <String, Object?>{'type': 'text', 'text': ''},
          },
          <String, Object?>{
            'type': 'content_block_delta',
            'index': 0,
            'delta': <String, Object?>{
              'type': 'citations_delta',
              'citation': <String, Object?>{
                'type': 'search_result_location',
                'cited_text': 'Acceleration is change of speed.',
                'source': 'aantekening://page/p1',
                'title': 'Lecture 1',
                'search_result_index': 0,
                'start_block_index': 1,
                'end_block_index': 2,
              },
            },
          },
          <String, Object?>{
            'type': 'content_block_delta',
            'index': 0,
            'delta': <String, Object?>{
              'type': 'text_delta',
              'text': 'It is change of speed.',
            },
          },
          <String, Object?>{'type': 'content_block_stop', 'index': 0},
          <String, Object?>{
            'type': 'message_delta',
            'delta': <String, Object?>{'stop_reason': 'end_turn'},
            'usage': <String, Object?>{'output_tokens': 7},
          },
          <String, Object?>{'type': 'message_stop'},
        ]),
      );
      final provider = AnthropicProvider(apiKey: 'k', client: fake.client);
      final events = await provider
          .chat(question('What is acceleration?'))
          .toList();

      expect(fake.sent.single.headers['x-api-key'], 'k');
      expect(
        fake.sent.single.headers['anthropic-beta'],
        'server-side-fallback-2026-07-01',
      );
      final builder = AnswerBuilder();
      events.forEach(builder.add);
      expect(builder.answer.markdown, 'It is change of speed.⟦1⟧');
      expect(
        builder.answer.citations.single.uri,
        'aantekening://page/p1#element=b&block=1',
      );
      final done = events.whereType<MessageDone>().single;
      expect(done.stop, StopReason.done);
      expect(done.usage!.output, 7);
      final native = done.message.parts.whereType<NativePart>().single;
      expect(
        ((native.block['content']! as List).single as Map)['citations'],
        hasLength(1),
      );
    });

    test('asks for tools with the input it streamed', () async {
      final fake = server(
        sse(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'content_block_start',
            'index': 0,
            'content_block': <String, Object?>{
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'read_page',
              'input': <String, Object?>{},
            },
          },
          for (final piece in <String>['{"page_', 'id": "p2"}'])
            <String, Object?>{
              'type': 'content_block_delta',
              'index': 0,
              'delta': <String, Object?>{
                'type': 'input_json_delta',
                'partial_json': piece,
              },
            },
          <String, Object?>{'type': 'content_block_stop', 'index': 0},
          <String, Object?>{
            'type': 'message_delta',
            'delta': <String, Object?>{'stop_reason': 'tool_use'},
          },
        ]),
      );
      final done = await AnthropicProvider(apiKey: 'k', client: fake.client)
          .chat(question('More?', tools: const <ToolSpec>[readTool]))
          .where((e) => e is MessageDone)
          .cast<MessageDone>()
          .single;
      expect(done.stop, StopReason.toolUse);
      expect(done.message.toolCalls.single.input, <String, Object?>{
        'page_id': 'p2',
      });
    });

    test('cites the web as the web', () async {
      final fake = server(
        sse(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'content_block_start',
            'index': 0,
            'content_block': <String, Object?>{
              'type': 'text',
              'text': '',
              'citations': <Object?>[
                <String, Object?>{
                  'type': 'web_search_result_location',
                  'url': 'https://example.org/g',
                  'title': 'Gravity',
                  'cited_text': 'g is 9.81',
                  'encrypted_index': 'x',
                },
              ],
            },
          },
          <String, Object?>{
            'type': 'content_block_delta',
            'index': 0,
            'delta': <String, Object?>{
              'type': 'text_delta',
              'text': 'g ≈ 9.81.',
            },
          },
          <String, Object?>{'type': 'content_block_stop', 'index': 0},
        ]),
      );
      final builder = AnswerBuilder();
      await AnthropicProvider(
        apiKey: 'k',
        client: fake.client,
      ).chat(question('g?')).forEach(builder.add);
      expect(builder.answer.citations.single.origin, SourceOrigin.web);
      expect(builder.answer.citations.single.uri, 'https://example.org/g');
    });

    test('says plainly when the key is refused', () async {
      final fake = server(
        '{"error":{"message":"invalid x-api-key"}}',
        status: 401,
      );
      expect(
        AnthropicProvider(
          apiKey: 'bad',
          client: fake.client,
        ).chat(question('?')).toList(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('API key'),
          ),
        ),
      );
    });
  });

  group('OpenAI-compatible', () {
    OpenAiCompatibleProvider provider(http.Client client) =>
        OpenAiCompatibleProvider(
          name: 'Ollama',
          baseUrl: 'http://127.0.0.1:11434/v1',
          client: client,
        );

    test('numbers the sources to be cited, and sends tool results as tool '
        'messages with their images after', () {
      final body = provider(http.Client()).body(
        ChatRequest(
          model: 'qwen',
          system: 'Be brief.',
          messages: <ChatMessage>[
            ChatMessage.user(<ChatPart>[
              const SourcesPart(<Source>[lecture]),
              const TextPart('How fast?'),
            ]),
            ChatMessage.assistant(const <ChatPart>[
              ToolCallPart(
                id: 'c1',
                name: 'look_at',
                input: <String, Object?>{},
              ),
            ]),
            ChatMessage.user(<ChatPart>[
              ToolResultPart(
                callId: 'c1',
                content: <ChatPart>[
                  ImagePart(
                    Uint8List(3),
                    mediaType: 'image/png',
                    label: 'Visual v1',
                  ),
                ],
              ),
            ]),
          ],
        ),
      );
      final messages = (body['messages']! as List).cast<Map<String, Object?>>();
      expect(messages.first['content'], contains('[3.2]'));
      expect(
        messages[1]['content'],
        contains('[1.2] Acceleration is change of speed.'),
      );
      expect(
        messages[1]['content'],
        contains('<source n="1" title="Lecture 1"'),
      );
      expect(messages[2]['tool_calls'], hasLength(1));
      expect(messages[3]['role'], 'tool');
      expect(messages[4]['role'], 'user');
      expect(
        ((messages[4]['content']! as List).single as Map)['type'],
        'image_url',
      );
    });

    test('reads the numbers the model cites by, even split in two', () async {
      final chunks = <String>[
        'Acceleration is change of speed [1',
        '.2]. Done.',
      ];
      final fake = server(
        <String>[
          for (final chunk in chunks)
            'data: ${jsonEncode(<String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{'content': chunk},
                },
              ],
            })}\n\n',
          'data: ${jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{'delta': <String, Object?>{}, 'finish_reason': 'stop'},
            ],
          })}\n\n',
          'data: [DONE]\n\n',
        ].join(),
      );
      final builder = AnswerBuilder();
      await provider(fake.client)
          .chat(
            ChatRequest(
              model: 'qwen',
              system: '',
              messages: <ChatMessage>[
                ChatMessage.user(const <ChatPart>[
                  SourcesPart(<Source>[lecture]),
                ]),
              ],
            ),
          )
          .forEach(builder.add);
      expect(
        builder.answer.markdown,
        'Acceleration is change of speed⟦1⟧. Done.',
      );
      expect(
        builder.answer.citations.single.quote,
        'Acceleration is change of speed.',
      );
    });

    test('tells reasoning apart from the answer, given apart or in tags '
        'at its start', () async {
      String chunk(Map<String, Object?> delta) =>
          'data: ${jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{'delta': delta},
            ],
          })}\n\n';
      final fake = server(
        <String>[
          chunk(<String, Object?>{'reasoning': 'Speed first.'}),
          chunk(<String, Object?>{'content': '\n<thi'}),
          chunk(<String, Object?>{'content': 'nk>Then time.</th'}),
          chunk(<String, Object?>{'content': 'ink>\n\nIt is '}),
          chunk(<String, Object?>{'content': 'fast.'}),
          'data: [DONE]\n\n',
        ].join(),
      );
      final events = await provider(fake.client)
          .chat(
            const ChatRequest(
              model: 'qwen',
              system: '',
              messages: <ChatMessage>[],
            ),
          )
          .toList();
      expect(
        events.whereType<Reasoning>().map((e) => e.text).join(),
        'Speed first.Then time.',
      );
      expect(
        events.whereType<TextDelta>().map((e) => e.text).join(),
        'It is fast.',
      );
      expect(
        (events.last as MessageDone).message.text,
        'It is fast.',
        reason: 'the reasoning is no part of what is kept',
      );
    });

    test('gathers a tool call streamed in pieces', () async {
      final fake = server(
        <String>[
          for (final piece in <Map<String, Object?>>[
            <String, Object?>{
              'index': 0,
              'id': 'call_1',
              'function': <String, Object?>{
                'name': 'read_page',
                'arguments': '{"page',
              },
            },
            <String, Object?>{
              'index': 0,
              'function': <String, Object?>{'arguments': '_id":"p2"}'},
            },
          ])
            'data: ${jsonEncode(<String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{
                    'tool_calls': <Object?>[piece],
                  },
                },
              ],
            })}\n\n',
          'data: [DONE]\n\n',
        ].join(),
      );
      final done = await provider(fake.client)
          .chat(
            ChatRequest(
              model: 'qwen',
              system: '',
              messages: const <ChatMessage>[],
            ),
          )
          .where((e) => e is MessageDone)
          .cast<MessageDone>()
          .single;
      expect(done.stop, StopReason.toolUse);
      expect(done.message.toolCalls.single.input, <String, Object?>{
        'page_id': 'p2',
      });
    });

    test('says where it could not reach', () async {
      final client = MockClient((request) async => throw Exception('refused'));
      expect(
        provider(client).listModels(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('Is it running?'),
          ),
        ),
      );
    });
  });

  group('Ollama', () {
    /// An Ollama whose model thinks, sees and runs tools, answering chats
    /// with [lines].
    ({OllamaProvider provider, List<Map<String, Object?>> chats}) ollama(
      List<Map<String, Object?>> lines, {
      List<List<Map<String, Object?>>> later = const [],
      int contextTokens = 16384,
      Duration? thinkingTime,
      DateTime Function()? clock,
    }) {
      final chats = <Map<String, Object?>>[];
      final client = MockClient.streaming((request, stream) async {
        final body = await stream.bytesToString();
        final reply = switch (request.url.path) {
          '/api/show' => jsonEncode(<String, Object?>{
            'capabilities': <String>[
              'completion',
              'vision',
              'tools',
              'thinking',
            ],
            'model_info': <String, Object?>{'qwen3vl.context_length': 262144},
          }),
          '/api/chat' => () {
            chats.add((jsonDecode(body) as Map).cast<String, Object?>());
            final reply = chats.length == 1 ? lines : later[chats.length - 2];
            return reply.map(jsonEncode).join('\n');
          }(),
          _ => throw StateError('asked for ${request.url}'),
        };
        return http.StreamedResponse(Stream.value(utf8.encode(reply)), 200);
      });
      return (
        provider: OllamaProvider(
          name: 'Ollama',
          baseUrl: 'http://127.0.0.1:11434/v1',
          contextTokens: contextTokens,
          think: false,
          thinkingTime: thinkingTime,
          clock: clock,
          client: client,
        ),
        chats: chats,
      );
    }

    test('runs the model with the room it is given, tells it whether to '
        'think, and says what it can do', () async {
      final fake = ollama(<Map<String, Object?>>[
        <String, Object?>{
          'message': <String, Object?>{'content': 'Hi.'},
          'done': true,
          'done_reason': 'stop',
        },
      ]);
      final capabilities = await fake.provider.capabilitiesOf('qwen3-vl:4b');
      expect(capabilities.contextTokens, 16384, reason: 'as it is run');
      expect(capabilities.reasoning, isTrue);
      expect(capabilities.vision, isTrue);

      await fake.provider
          .chat(
            ChatRequest(
              model: 'qwen3-vl:4b',
              system: 'Be brief.',
              messages: <ChatMessage>[
                ChatMessage.user(<ChatPart>[
                  const SourcesPart(<Source>[lecture]),
                  ImagePart(Uint8List(3), mediaType: 'image/png', label: 'v1'),
                  const TextPart('How fast?'),
                ]),
                ChatMessage.assistant(const <ChatPart>[
                  ToolCallPart(
                    id: 'c1',
                    name: 'read_page',
                    input: <String, Object?>{'page_id': 'p1'},
                  ),
                ]),
                ChatMessage.user(const <ChatPart>[
                  ToolResultPart(
                    callId: 'c1',
                    content: <ChatPart>[TextPart('The page.')],
                  ),
                ]),
              ],
              tools: const <ToolSpec>[readTool],
            ),
          )
          .drain<void>();
      final sent = fake.chats.single;
      expect(sent['options'], <String, Object?>{
        'num_ctx': 16384,
        'num_batch': 512,
      });
      expect(sent['think'], isFalse);
      final messages = (sent['messages']! as List).cast<Map<String, Object?>>();
      expect(messages[1]['content'], contains('[1.1] Speed is distance'));
      expect(messages[1]['images'], hasLength(1));
      expect((messages[2]['tool_calls'] as List).single, <String, Object?>{
        'function': <String, Object?>{
          'name': 'read_page',
          'arguments': <String, Object?>{'page_id': 'p1'},
        },
      });
      expect(messages[3], <String, Object?>{
        'role': 'tool',
        'content': 'The page.\n',
        'tool_name': 'read_page',
      });
    });

    test('streams thinking apart from the answer, and says when the room '
        'ran out', () async {
      final fake = ollama(<Map<String, Object?>>[
        <String, Object?>{
          'message': <String, Object?>{'thinking': '<think>\nSpeed first.'},
          'done': false,
        },
        <String, Object?>{
          'message': <String, Object?>{'content': 'It is [1.1'},
          'done': false,
        },
        <String, Object?>{
          'message': <String, Object?>{'content': '] fast.'},
          'done': false,
        },
        <String, Object?>{
          'message': <String, Object?>{'content': ''},
          'done': true,
          'done_reason': 'length',
          'prompt_eval_count': 1846,
          'eval_count': 2250,
        },
      ]);
      final events = await fake.provider.chat(question('How fast?')).toList();
      expect(
        events.whereType<Reasoning>().map((e) => e.text).join(),
        'Speed first.',
      );
      final builder = AnswerBuilder();
      events.forEach(builder.add);
      expect(builder.answer.markdown, 'It is⟦1⟧ fast.');
      final done = events.last as MessageDone;
      expect(done.stop, StopReason.maxTokens);
      expect(done.usage!.output, 2250);
    });

    Map<String, Object?> thinking(String text) => <String, Object?>{
      'message': <String, Object?>{'thinking': text},
      'done': false,
    };
    const answered = <Map<String, Object?>>[
      <String, Object?>{
        'message': <String, Object?>{'content': 'Fast.'},
        'done': true,
        'done_reason': 'stop',
      },
    ];

    test('stops a model thinking into the room its answer needs, and has it '
        'answer from what it thought', () async {
      final fake = ollama(
        <Map<String, Object?>>[
          for (var i = 0; i < 800; i++) thinking('round and round '),
          ...answered,
        ],
        later: <List<Map<String, Object?>>>[answered],
        contextTokens: 4096,
      );
      final events = await fake.provider.chat(question('How fast?')).toList();
      expect(fake.chats, hasLength(2));
      final last = (fake.chats.last['messages']! as List).last as Map;
      expect(last['role'], 'assistant');
      expect(last['content'], '\n', reason: 'begun, so thinking is over');
      expect(last['thinking'], startsWith('round and round'));
      expect(last['thinking'], endsWith('without thinking further.'));
      expect(
        (fake.chats.last['options']! as Map)['num_predict'],
        OllamaProvider.answerRoom * 2,
      );
      expect(
        events.whereType<Activity>().single.description,
        'Stopping its thinking, to answer',
      );
      expect((events.last as MessageDone).message.text, 'Fast.');
    });

    test('stops a model thinking longer than it may', () async {
      var now = DateTime(2026);
      final fake = ollama(
        <Map<String, Object?>>[
          for (var i = 0; i < 5; i++) thinking('hmm '),
          ...answered,
        ],
        later: <List<Map<String, Object?>>>[answered],
        thinkingTime: const Duration(minutes: 1),
        clock: () => now = now.add(const Duration(seconds: 40)),
      );
      await fake.provider.chat(question('How fast?')).drain<void>();
      expect(fake.chats, hasLength(2));
      final last = (fake.chats.last['messages']! as List).last as Map;
      expect(
        last['thinking'],
        startsWith('hmm hmm \n'),
        reason: 'stopped once past the minute',
      );
    });

    test('lets a model that thinks within bounds answer at once', () async {
      final fake = ollama(<Map<String, Object?>>[
        thinking('Speed first.'),
        ...answered,
      ]);
      await fake.provider.chat(question('How fast?')).drain<void>();
      expect(fake.chats, hasLength(1));
    });

    test('lists its models with what each can do', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(<String, Object?>{
            'models': <Object?>[
              <String, Object?>{
                'name': 'qwen3-vl:4b',
                'capabilities': <String>['completion', 'vision', 'thinking'],
                'details': <String, Object?>{'context_length': 262144},
              },
            ],
          }),
          200,
        ),
      );
      final models = await OllamaProvider(
        name: 'Ollama',
        baseUrl: 'http://127.0.0.1:11434',
        client: client,
      ).listModels();
      expect(models.single.id, 'qwen3-vl:4b');
      expect(models.single.capabilities.reasoning, isTrue);
      expect(models.single.capabilities.tools, isFalse);
    });
  });

  group('think tags', () {
    test('leave an answer without them as it is', () {
      final tags = ThinkTags();
      final events = <ChatEvent>[
        ...tags.add('<b>Hi'),
        ...tags.add('</b>'),
        ...tags.close(),
      ];
      expect(
        events.whereType<TextDelta>().map((e) => e.text).join(),
        '<b>Hi</b>',
      );
      expect(events.whereType<Reasoning>(), isEmpty);
    });

    test('keep reasoning never closed as reasoning', () {
      final tags = ThinkTags();
      final events = <ChatEvent>[...tags.add('<think>Hmm </'), ...tags.close()];
      expect(events.whereType<Reasoning>().map((e) => e.text).join(), 'Hmm </');
    });
  });

  test('a prompt\'s size counts its text and its pictures, in tool results '
      'too', () {
    final size = PromptSize.of(<ChatMessage>[
      ChatMessage.user(<ChatPart>[
        TextPart('x' * 400),
        ToolResultPart(
          callId: 'c',
          content: <ChatPart>[
            ImagePart(Uint8List(1), mediaType: 'image/png', label: 'v1'),
          ],
        ),
      ]),
    ]);
    expect(size.images, 1);
    expect(size.tokens, inInclusiveRange(100, 120));
  });

  group('citation markers', () {
    test('leave numbers that name no source as they are', () {
      final events = MarkerReader(const <Source>[
        lecture,
      ]).add('see [7] and [1]');
      final builder = AnswerBuilder();
      events.forEach(builder.add);
      expect(builder.answer.markdown, 'see [7] and⟦1⟧');
    });
  });

  group('answer blocks', () {
    test('flashcards and quizzes are read from their fenced blocks', () {
      const markdown = '''
Here are cards from your notes⟦1⟧.

```flashcards
[{"front": "What is speed?", "back": "Distance over time"}]
```

```quiz
[{"question": "Speed is…", "options": ["d/t", "t/d"], "answer": 0}]
```''';
      final blocks = AnswerBlocks.fence.allMatches(markdown).toList();
      expect(
        AnswerBlocks.cardsIn(blocks[0].group(2)!)!.single.back,
        'Distance over time',
      );
      expect(AnswerBlocks.questionsIn(blocks[1].group(2)!)!.single.answer, 0);
      expect(AnswerBlocks.kindOf(markdown), AnswerBlocks.flashcards);
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const AiSettings _settings = AiSettings(
  enabled: true,
  chatModel: 'test-chat',
  embeddingModel: 'test-embed',
);

/// Encodes an Ollama streaming response body.
String _ndjson(List<Map<String, Object?>> frames) =>
    frames.map(jsonEncode).join('\n');

void main() {
  group('TextChunker', () {
    test('keeps a short page as one chunk', () {
      final chunks = const TextChunker().split('a short note');
      expect(chunks, hasLength(1));
      expect(chunks.single.text, 'a short note');
    });

    test('returns nothing for blank text', () {
      expect(const TextChunker().split('   \n  '), isEmpty);
    });

    test('splits long text into overlapping chunks', () {
      final text = List<String>.generate(
        200,
        (i) => 'Sentence number $i about the topic.',
      ).join(' ');

      final chunks = const TextChunker(
        targetSize: 400,
        overlap: 80,
      ).split(text);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.text.length, lessThanOrEqualTo(500));
      }
      expect(
        chunks.map((c) => c.index).toList(),
        List<int>.generate(chunks.length, (i) => i),
      );
    });

    test('prefers paragraph boundaries', () {
      final text = '${'a' * 300}\n\n${'b' * 300}';
      final chunks = const TextChunker(
        targetSize: 320,
        overlap: 40,
      ).split(text);

      expect(chunks.first.text, endsWith('a'));
    });

    test('covers the whole input', () {
      final text = List<String>.generate(80, (i) => 'word$i').join(' ');
      final chunks = const TextChunker(
        targetSize: 120,
        overlap: 20,
      ).split(text);

      final joined = chunks.map((c) => c.text).join(' ');
      expect(joined, contains('word0'));
      expect(joined, contains('word79'));
    });
  });

  group('OllamaClient', () {
    test(
      'reports unavailable instead of throwing when nothing answers',
      () async {
        final client = OllamaClient(
          settings: _settings,
          httpClient: MockClient(
            (_) => Future<http.Response>.error(const SocketExceptionStub()),
          ),
        );

        expect(await client.isAvailable(), isFalse);
      },
    );

    test('lists installed models', () async {
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/tags');
          return http.Response(
            jsonEncode(<String, Object?>{
              'models': <Object?>[
                <String, Object?>{
                  'name': 'llama3.2:3b',
                  'size': 2019393189,
                  'details': <String, Object?>{
                    'parameter_size': '3.2B',
                    'quantization_level': 'Q4_K_M',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final models = await client.listModels();

      expect(models.single.name, 'llama3.2:3b');
      expect(models.single.parameterSize, '3.2B');
      expect(models.single.quantization, 'Q4_K_M');
    });

    test('streams generated tokens in order', () async {
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['model'], 'test-chat');
          expect(body['stream'], true);
          return http.Response(
            _ndjson(<Map<String, Object?>>[
              <String, Object?>{'response': 'The ', 'done': false},
              <String, Object?>{'response': 'chain ', 'done': false},
              <String, Object?>{'response': 'rule', 'done': false},
              <String, Object?>{'response': '', 'done': true},
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .generate(
            const GenerationRequest(model: 'test-chat', prompt: 'explain'),
          )
          .toList();

      expect(chunks.join(), 'The chain rule');
    });

    test('surfaces an error frame as an exception', () async {
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient(
          (_) async => http.Response(
            _ndjson(<Map<String, Object?>>[
              <String, Object?>{'error': 'model not found'},
            ]),
            200,
          ),
        ),
      );

      expect(
        () => client
            .complete(const GenerationRequest(model: 'gone', prompt: 'hi'))
            .then((value) => value),
        throwsA(
          isA<LocalModelException>().having(
            (e) => e.message,
            'message',
            contains('model not found'),
          ),
        ),
      );
    });

    test('reports a non-200 response', () async {
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient((_) async => http.Response('nope', 500)),
      );

      expect(() => client.listModels(), throwsA(isA<LocalModelException>()));
    });

    test('skips a malformed line rather than aborting the stream', () async {
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient(
          (_) async => http.Response(
            '${jsonEncode(<String, Object?>{'response': 'ok', 'done': false})}\n'
            'not json\n'
            '${jsonEncode(<String, Object?>{'response': '!', 'done': true})}',
            200,
          ),
        ),
      );

      final text = await client.complete(
        const GenerationRequest(model: 'test-chat', prompt: 'x'),
      );

      expect(text, 'ok!');
    });

    test('embeds a batch of passages', () async {
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(request.url.path, '/api/embed');
          expect((body['input']! as List<Object?>).length, 2);
          return http.Response(
            jsonEncode(<String, Object?>{
              'embeddings': <Object?>[
                <double>[1, 0, 0],
                <double>[0, 1, 0],
              ],
            }),
            200,
          );
        }),
      );

      final vectors = await client.embed(<String>[
        'a',
        'b',
      ], model: 'test-embed');

      expect(vectors, hasLength(2));
      expect(vectors.first, isA<Float32List>());
      expect(vectors.first.toList(), <double>[1, 0, 0]);
    });

    test('an empty batch never reaches the network', () async {
      var called = false;
      final client = OllamaClient(
        settings: _settings,
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(await client.embed(const <String>[], model: 'm'), isEmpty);
      expect(called, isFalse);
    });
  });

  group('NoteAssistant', () {
    NoteAssistant assistantWith(MockClient http_, {AiSettings? settings}) =>
        NoteAssistant(
          client: OllamaClient(
            settings: settings ?? _settings,
            httpClient: http_,
          ),
          settings: settings ?? _settings,
        );

    test('refuses to run when no model is configured', () {
      final assistant = assistantWith(
        MockClient((_) async => http.Response('{}', 200)),
        settings: const AiSettings(enabled: true),
      );

      expect(
        () => assistant.summarize('text').toList(),
        throwsA(isA<LocalModelException>()),
      );
      expect(
        () => assistant.embedQuery('text'),
        throwsA(isA<LocalModelException>()),
      );
    });

    test('grounds the summary prompt in the page text', () {
      final prompt = NoteAssistant.buildSummaryPrompt('the residue theorem');

      expect(prompt, contains('the residue theorem'));
      expect(prompt, contains('at most 5 bullet points'));
      expect(NoteAssistant.summarySystemPrompt, contains('Never add facts'));
    });

    test('numbers and titles the excerpts in an answer prompt', () {
      final prompt = NoteAssistant.buildAnswerPrompt(
        'What is the residue?',
        const <RetrievedPassage>[
          RetrievedPassage(
            pageId: 'p1',
            pageTitle: 'Complex analysis',
            text: 'the residue is the coefficient of 1/z',
          ),
          RetrievedPassage(
            pageId: 'p2',
            pageTitle: 'Lecture 7',
            text: 'contour integration',
          ),
        ],
      );

      expect(prompt, contains('[1] from "Complex analysis"'));
      expect(prompt, contains('[2] from "Lecture 7"'));
      expect(prompt, contains('Question: What is the residue?'));
    });

    test('says so when nothing was retrieved', () {
      final prompt = NoteAssistant.buildAnswerPrompt(
        'anything?',
        const <RetrievedPassage>[],
      );

      expect(prompt, contains('No excerpts'));
    });

    test('pairs each chunk with its vector', () async {
      final assistant = assistantWith(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final inputs = body['input']! as List<Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'embeddings': <Object?>[
                for (var i = 0; i < inputs.length; i++)
                  <double>[i.toDouble(), 1],
              ],
            }),
            200,
          );
        }),
      );

      final embedded = await assistant.embedPage(
        List<String>.generate(200, (i) => 'Sentence $i.').join(' '),
      );

      expect(embedded, isNotEmpty);
      expect(embedded.first.vector.length, 2);
      expect(embedded.last.chunk.index, embedded.length - 1);
    });

    test('rejects a mismatched number of vectors', () {
      final assistant = assistantWith(
        MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'embeddings': <Object?>[
                <double>[1, 0],
              ],
            }),
            200,
          ),
        ),
      );

      expect(
        () => assistant.embedPage(
          List<String>.generate(200, (i) => 'Sentence $i.').join(' '),
        ),
        throwsA(isA<LocalModelException>()),
      );
    });
  });
}

/// Stands in for a connection failure without depending on dart:io in tests.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

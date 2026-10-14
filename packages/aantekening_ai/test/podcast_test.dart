import 'dart:convert';
import 'dart:typed_data';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'agent_test.dart' show ScriptedProvider, notes;

List<ChatEvent> says(String text) => <ChatEvent>[
  TextDelta(text),
  const MessageDone(
    ChatMessage(ChatRole.assistant, <ChatPart>[]),
    stop: StopReason.done,
  ),
];

/// Speaks every line as a tone of its length in characters, a sample a
/// character, and keeps what it was asked.
class CountingSpeech implements SpeechProvider {
  final List<(String, String)> spoken = <(String, String)>[];

  @override
  int get maxCharacters => 40;

  @override
  Future<List<VoiceInfo>> listVoices() async => const <VoiceInfo>[];

  @override
  Future<Sound> speak(
    String text, {
    required String voice,
    String instructions = '',
  }) async {
    spoken.add((voice, text));
    return Sound(Int16List.fromList(List<int>.filled(text.length, 1000)));
  }

  @override
  void close() {}
}

/// [inner], failing its first [failures] requests as a router does when
/// the provider behind it is slow.
class Flaky implements ChatProvider {
  Flaky(this.inner, {required this.failures, this.retryable = true});

  final ChatProvider inner;
  final bool retryable;
  int failures;
  int tried = 0;

  @override
  String get name => inner.name;

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) =>
      inner.capabilitiesOf(model);

  @override
  Stream<ChatEvent> chat(ChatRequest request) {
    tried++;
    if (failures-- > 0) {
      return Stream<ChatEvent>.error(
        AiException('Requesty had a problem.', retryable: retryable),
      );
    }
    return inner.chat(request);
  }

  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();

  @override
  void close() {}
}

const List<PodcastSpeaker> pair = <PodcastSpeaker>[
  PodcastSpeaker(name: 'Anna', voice: 'nova', backstory: 'A teacher.'),
  PodcastSpeaker(name: 'Ben', voice: 'onyx', backstory: 'A student.'),
];

void main() {
  group('Sound', () {
    test('is written as a WAV file and read back', () {
      final sound = Sound(Int16List.fromList(<int>[0, 1000, -1000, 32767]));
      final read = Sound.wav(sound.toWav());
      expect(read.rate, Sound.podcastRate);
      expect(read.samples, sound.samples);
    });

    test('reads a stereo WAV of floats, its channels mixed to one', () {
      final data = ByteData(8);
      data.setFloat32(0, 0.5, Endian.little);
      data.setFloat32(4, -0.5, Endian.little);
      final read = Sound.wav(_wav(data, format: 3, channels: 2, bits: 32));
      expect(read.samples, <int>[0]);
    });

    test('reads a WAV streamed with a length that runs on for ever', () {
      final data = ByteData(4)
        ..setInt16(0, 7, Endian.little)
        ..setInt16(2, -7, Endian.little);
      final read = Sound.wav(_wav(data, dataSize: 0xFFFFFFFF, rate: 22050));
      expect(read.samples, <int>[7, -7]);
      expect(read.rate, 22050);
    });

    test('is joined, at the first rate, with a gap between', () {
      final joined = Sound.join(<Sound>[
        Sound(Int16List.fromList(<int>[1, 1]), rate: 1000),
        Sound(Int16List.fromList(<int>[2, 2, 2, 2]), rate: 2000),
      ], gap: const Duration(milliseconds: 3));
      expect(joined.rate, 1000);
      expect(joined.samples, <int>[1, 1, 0, 0, 0, 2, 2]);
    });

    test('refuses what is not a WAV file', () {
      expect(
        () => Sound.wav(Uint8List.fromList(utf8.encode('{"error": 1}'))),
        throwsA(isA<AiException>()),
      );
    });
  });

  test('long text is spoken in parts, between sentences', () {
    expect(speechParts('One two three. Four five six. Seven.', 20), <String>[
      'One two three.',
      'Four five six.',
      'Seven.',
    ]);
    expect(
      speechParts('averyveryverylongword', 8).join(),
      'averyveryverylongword',
    );
  });

  group('reading what the model wrote', () {
    test('an outline, as asked', () {
      final outline = PodcastMaker.readOutline(
        '{"segments": [{"name": "Open", "description": "What speed is", '
        '"size": "short"}, {"name": "Forces", "description": "F = ma", '
        '"size": "long"}]}',
      );
      expect(outline.map((s) => s.name), <String>['Open', 'Forces']);
      expect(outline.last.size, SegmentSize.long);
    });

    test('an outline in its own words, in a fence', () {
      final outline = PodcastMaker.readOutline(
        'Here it is:\n```json\n{"episode": {"outline": [{"title": "Start", '
        '"summary": "hello", "length": "Medium"}]}}\n```',
      );
      expect(outline.single.name, 'Start');
      expect(outline.single.description, 'hello');
      expect(outline.single.size, SegmentSize.medium);
    });

    test('a transcript, its speakers matched and Markdown taken out', () {
      final lines = PodcastMaker.readTranscript(
        '{"transcript": [{"speaker": "anna", "dialogue": "**Welcome** '
        '[laughs] back."}, {"speaker": "Ben Smith", "dialogue": "Hi."}, '
        '{"speaker": "Narrator", "dialogue": "And so on."}]}',
        speakers: pair,
        segment: 2,
      );
      expect(lines.map((l) => l.speaker), <String>['Anna', 'Ben', 'Anna']);
      expect(lines.first.text, 'Welcome back.');
      expect(lines.first.segment, 2);
    });

    test('a transcript written as a play', () {
      final lines = PodcastMaker.readTranscript(
        '**Anna:** What is speed?\nBen: Distance over time.\nNot a line.',
        speakers: pair,
      );
      expect(lines.map((l) => l.text), <String>[
        'What is speed?',
        'Distance over time.',
      ]);
    });
  });

  test('settings keep voices and podcast profiles', () {
    final settings = const AiSettings()
        .withVoice(VoiceConfig.of(SpeechPreset.kokoro, id: 'v'))
        .withEpisode(
          EpisodeProfile.originals.first.copyWith(
            segments: 6,
            language: 'German',
            outline: const ModelChoice(providerId: 'p', model: 'big'),
          ),
        )
        .withoutCast('lecturer');
    final read = AiSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
    expect(read.voices.single.preset, SpeechPreset.kokoro);
    expect(read.voices.single.local, isTrue);
    final episode = read.episodes.first;
    expect(episode.segments, 6);
    expect(episode.language, 'German');
    expect(episode.outline, const ModelChoice(providerId: 'p', model: 'big'));
    expect(episode.transcript.isInUse, isTrue);
    expect(read.casts.map((c) => c.id), isNot(contains('lecturer')));
    // Nothing changed, the app's own are offered.
    expect(const AiSettings().episodes, EpisodeProfile.originals);
    expect(
      AiSettings.fromJson(const AiSettings().toJson()).casts,
      SpeakerProfile.originals,
    );
  });

  test('an episode is kept, and only an episode reads as one', () {
    const episode = PodcastEpisode(
      title: 'Mechanics',
      profile: 'Study conversation',
      outline: <PodcastSegment>[PodcastSegment(name: 'Open')],
      lines: <PodcastLine>[PodcastLine(speaker: 'Anna', text: 'Hello.')],
      speakers: pair,
      audio: 'x.wav',
      duration: Duration(seconds: 3),
      starts: <Duration>[Duration.zero],
      models: <String>['a', 'b'],
    );
    final read = PodcastEpisode.fromJson(
      jsonDecode(jsonEncode(episode.toJson())),
    )!;
    expect(read.lines.single.text, 'Hello.');
    expect(read.speakers.last.voice, 'onyx');
    expect(read.duration, const Duration(seconds: 3));
    expect(read.lineAt(const Duration(seconds: 1)), 0);
    expect(read.lineAt(Duration.zero), 0);
    expect(read.spoken, isTrue);
    expect(PodcastEpisode.fromJson(const AiAnswer().toJson()), isNull);
    expect(StudySet.fromJson(episode.toJson()), isNull);
  });

  test('speakers without a voice are given the provider’s, in turn', () {
    final voiced = SpeakerProfile.originals.first.voiced(
      VoiceConfig.of(SpeechPreset.openAi, id: 'v').voiceFor,
    );
    expect(voiced.map((s) => s.voice), <String>['alloy', 'ash']);
  });

  group('making a podcast', () {
    const scope = ScopeInfo(
      link: NoteLink.section('s'),
      title: 'Mechanics',
      path: <String>['Physics'],
    );
    final profile = EpisodeProfile.originals.first.copyWith(
      segments: 2,
      language: 'German',
    );

    test(
      'plans it with one model and writes each segment with another',
      () async {
        final planner = ScriptedProvider(<List<ChatEvent>>[
          says(
            '{"segments": [{"name": "Speed", "description": "s over t", '
            '"size": "short"}, {"name": "Force", "description": "F = ma", '
            '"size": "medium"}]}',
          ),
        ]);
        final writer = ScriptedProvider(<List<ChatEvent>>[
          says(
            '{"transcript": [{"speaker": "Anna", "dialogue": "Speed first."}, '
            '{"speaker": "Ben", "dialogue": "Distance over time."}]}',
          ),
          // Not readable the first time: asked again.
          says('Sorry, I cannot.'),
          says('{"transcript": [{"speaker": "Ben", "dialogue": "Bye."}]}'),
        ]);
        final maker = PodcastMaker(
          reader: notes,
          outliner: (provider: planner, model: 'planner'),
          writer: (provider: writer, model: 'writer'),
          about: 'I am in Q13.',
        );
        final progress = await maker
            .write(profile, speakers: pair, scope: scope)
            .toList();
        final last = progress.last;
        expect(last.done, isTrue);
        expect(last.outline.map((s) => s.name), <String>['Speed', 'Force']);
        expect(last.lines.map((l) => (l.speaker, l.segment)), <(String, int)>[
          ('Anna', 0),
          ('Ben', 0),
          ('Ben', 1),
        ]);
        expect(
          progress.map((p) => p.stage),
          containsAllInOrder(<PodcastStage>[
            PodcastStage.gathering,
            PodcastStage.outlining,
            PodcastStage.writing,
            PodcastStage.done,
          ]),
        );

        expect(planner.asked.single.model, 'planner');
        expect(planner.asked.single.answerSchema, PodcastMaker.outlineSchema);
        String text(ChatRequest request) => <String>[
          for (final part in request.messages.single.parts)
            if (part is TextPart) part.text,
        ].join('\n');
        final plan = text(planner.asked.single);
        expect(plan, contains('Speed is distance over time.'));
        expect(plan, contains('exactly 2 segments'));
        expect(plan, contains('German'));
        expect(planner.asked.single.system, contains('I am in Q13.'));
        expect(planner.asked.single.system, contains('in words'));

        expect(writer.asked, hasLength(3));
        expect(writer.asked.every((r) => r.model == 'writer'), isTrue);
        final second = text(writer.asked.last);
        expect(second, contains('Write segment 2 alone, "Force"'));
        expect(second, contains('Anna: Speed first.'));
        expect(second, contains('last segment'));
      },
    );

    test(
      'a request that fails as may pass is tried again, and said so',
      () async {
        PodcastMaker.wait = (_) => Duration.zero;
        addTearDown(
          () => PodcastMaker.wait = (a) => Duration(seconds: 3 * a * a),
        );
        final planner = Flaky(
          ScriptedProvider(<List<ChatEvent>>[
            says('{"segments": [{"name": "Speed", "description": "s/t"}]}'),
          ]),
          failures: 2,
        );
        final writer = Flaky(
          ScriptedProvider(<List<ChatEvent>>[
            says('{"transcript": [{"speaker": "Anna", "dialogue": "Hi."}]}'),
          ]),
          failures: 1,
        );
        final progress = await PodcastMaker(
          reader: notes,
          outliner: (provider: planner, model: 'p'),
          writer: (provider: writer, model: 'w'),
        ).write(profile, speakers: pair, scope: scope).toList();
        expect(progress.last.lines.single.text, 'Hi.');
        expect(
          progress.map((p) => p.activity),
          containsAllInOrder(<String>[
            'Requesty had a problem — trying again (2 of 3)',
            'Requesty had a problem — trying again (3 of 3)',
          ]),
        );
      },
    );

    test(
      'gives up after three tries, and at once on what will not pass',
      () async {
        PodcastMaker.wait = (_) => Duration.zero;
        addTearDown(
          () => PodcastMaker.wait = (a) => Duration(seconds: 3 * a * a),
        );
        final down = Flaky(ScriptedProvider(const []), failures: 9);
        await expectLater(
          PodcastMaker(
            reader: notes,
            outliner: (provider: down, model: 'p'),
            writer: (provider: down, model: 'w'),
          ).write(profile, speakers: pair, scope: scope).toList(),
          throwsA(isA<AiException>()),
        );
        expect(down.tried, 3);
        final refused = Flaky(
          ScriptedProvider(const []),
          failures: 9,
          retryable: false,
        );
        await expectLater(
          PodcastMaker(
            reader: notes,
            outliner: (provider: refused, model: 'p'),
            writer: (provider: refused, model: 'w'),
          ).write(profile, speakers: pair, scope: scope).toList(),
          throwsA(isA<AiException>()),
        );
        expect(refused.tried, 1);
      },
    );

    test('says so when there are no notes', () async {
      const empty = ScopeInfo(
        link: NoteLink.page('none'),
        title: 'Empty',
        path: <String>[],
      );
      final maker = PodcastMaker(
        reader: notes,
        outliner: (provider: ScriptedProvider(const []), model: 'm'),
        writer: (provider: ScriptedProvider(const []), model: 'm'),
      );
      await expectLater(
        maker.write(profile, speakers: pair, scope: empty).toList(),
        throwsA(isA<AiException>()),
      );
    });

    test('speaks each line in its speaker’s voice, in order', () async {
      final speech = CountingSpeech();
      final lines = <PodcastLine>[
        const PodcastLine(speaker: 'Anna', text: 'Hello.'),
        const PodcastLine(speaker: 'Anna', text: 'Speed is distance.'),
        const PodcastLine(
          speaker: 'Ben',
          text: 'That is a very long line. It is spoken in two parts.',
        ),
      ];
      final progress = await PodcastMaker.speak(
        lines,
        speakers: pair,
        speech: speech,
        parallel: 2,
      ).toList();
      expect(speech.spoken.map((s) => s.$1), <String>[
        'nova',
        'nova',
        'onyx',
        'onyx',
      ]);
      final sound = progress.last.sound!;
      // 6 + 18 + 25 + 26 samples spoken; 200 ms within Anna, 350 ms to Ben.
      expect(sound.samples.length, 6 + 18 + 25 + 26 + 4800 + 8400);
      expect(progress.last.steps, 3);
      // Each line begins after the one before and its breath.
      expect(progress.last.starts.map((s) => s.inMicroseconds), <int>[
        0,
        (6 + 4800) * 1000000 ~/ 24000,
        (6 + 18 + 4800 + 8400) * 1000000 ~/ 24000,
      ]);
    });
  });

  group('voice providers', () {
    test(
      'Requesty is told how to speak by its own name of the model',
      () async {
        late Map<String, Object?> body;
        final client = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://router.requesty.ai/v1/audio/speech',
          );
          body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response.bytes(Sound(Int16List(2)).toWav(), 200);
        });
        await VoiceConfig.of(SpeechPreset.requesty, id: 'v')
            .create(apiKey: 'k', client: client)
            .speak('Hi', voice: 'nova', instructions: 'Warm.');
        expect(body['model'], 'openai/gpt-4o-mini-tts');
        expect(body['instructions'], 'Warm.');
      },
    );

    test('OpenAI is asked for WAV, told how to speak', () async {
      late Map<String, Object?> body;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/audio/speech');
        expect(request.headers['Authorization'], 'Bearer k');
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response.bytes(
          Sound(Int16List.fromList(<int>[5, 6])).toWav(),
          200,
        );
      });
      final speech = VoiceConfig.of(
        SpeechPreset.openAi,
        id: 'v',
      ).create(apiKey: 'k', client: client);
      final sound = await speech.speak(
        'Hi',
        voice: 'nova',
        instructions: 'Warm.',
      );
      expect(sound.samples, <int>[5, 6]);
      expect(body['model'], 'gpt-4o-mini-tts');
      expect(body['voice'], 'nova');
      expect(body['response_format'], 'wav');
      expect(body['instructions'], 'Warm.');
    });

    test(
      'a speech server of one’s own lists its voices, or offers the known',
      () async {
        final listing = MockClient(
          (request) async =>
              http.Response('{"voices": ["af_sky", "am_echo"]}', 200),
        );
        final kokoro = VoiceConfig.of(SpeechPreset.kokoro, id: 'v');
        expect(
          (await kokoro.create(client: listing).listVoices()).map((v) => v.id),
          <String>['af_sky', 'am_echo'],
        );
        final none = MockClient((request) async => http.Response('', 404));
        expect(
          (await kokoro.create(client: none).listVoices()).first.id,
          'af_heart',
        );
      },
    );

    test('Gemini’s sound is read from its rate', () async {
      final pcm = ByteData(4)
        ..setInt16(0, 3, Endian.little)
        ..setInt16(2, 4, Endian.little);
      final client = MockClient((request) async {
        expect(request.headers['x-goog-api-key'], 'k');
        expect(
          request.url.path,
          endsWith('gemini-2.5-flash-preview-tts:generateContent'),
        );
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(jsonEncode(body), contains('"voiceName":"Kore"'));
        return http.Response(
          jsonEncode(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{
                      'inlineData': <String, Object?>{
                        'mimeType': 'audio/L16;codec=pcm;rate=16000',
                        'data': base64Encode(pcm.buffer.asUint8List()),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final sound = await VoiceConfig.of(
        SpeechPreset.gemini,
        id: 'v',
      ).create(apiKey: 'k', client: client).speak('Hi', voice: 'Kore');
      expect(sound.samples, <int>[3, 4]);
      expect(sound.rate, 16000);
    });

    test('ElevenLabs is asked for PCM, and says why it refused', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['output_format'], 'pcm_24000');
        expect(request.headers['xi-api-key'], 'k');
        return http.Response(
          '{"detail": {"status": "quota", "message": "Out of credits"}}',
          401,
        );
      });
      final speech = VoiceConfig.of(
        SpeechPreset.elevenLabs,
        id: 'v',
      ).create(apiKey: 'k', client: client);
      await expectLater(
        speech.speak('Hi', voice: 'x'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('Out of credits'),
          ),
        ),
      );
    });
  });
}

/// A WAV file of [data], as [format], [channels], [bits] and [rate] say,
/// its data said to be [dataSize] long.
Uint8List _wav(
  ByteData data, {
  int format = 1,
  int channels = 1,
  int bits = 16,
  int rate = 24000,
  int? dataSize,
}) {
  final out = BytesBuilder();
  void u32(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => out.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );
  out.add(ascii.encode('RIFF'));
  u32(0);
  out.add(ascii.encode('WAVEfmt '));
  u32(16);
  u16(format);
  u16(channels);
  u32(rate);
  u32(rate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  out.add(ascii.encode('data'));
  u32(dataSize ?? data.lengthInBytes);
  out.add(data.buffer.asUint8List());
  return out.toBytes();
}

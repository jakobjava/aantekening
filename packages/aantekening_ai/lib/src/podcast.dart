/// Podcasts made from the notes, as Open Notebook makes them: an episode
/// profile says what to make and which models write it, a speaker profile
/// who speaks and with which voices; a model plans the episode in
/// segments, writes what is said in each, and a voice provider speaks it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'conversation.dart';
import 'loose_json.dart';
import 'note_context.dart';
import 'note_reader.dart';
import 'provider.dart';
import 'speech.dart';

/// A model to write with: a provider set up in the settings and a model of
/// it — or, with [providerId] empty, the model in use for questions.
@immutable
class ModelChoice {
  const ModelChoice({this.providerId = '', this.model = ''});

  /// The model in use for questions.
  static const ModelChoice inUse = ModelChoice();

  final String providerId;

  /// The model's id, or empty for the one the provider is set to.
  final String model;

  bool get isInUse => providerId.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    if (providerId.isNotEmpty) 'provider': providerId,
    if (model.isNotEmpty) 'model': model,
  };

  static ModelChoice fromJson(Object? json) => json is Map
      ? ModelChoice(
          providerId: json['provider'] as String? ?? '',
          model: json['model'] as String? ?? '',
        )
      : inUse;

  @override
  bool operator ==(Object other) =>
      other is ModelChoice &&
      other.providerId == providerId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(providerId, model);
}

/// Someone who speaks in a podcast: their name, the voice they speak with
/// — empty for one the voice provider gives them — and who they are.
class PodcastSpeaker {
  const PodcastSpeaker({
    required this.name,
    this.voice = '',
    this.backstory = '',
    this.personality = '',
  });

  final String name;
  final String voice;

  /// Who they are: what they know, what they do.
  final String backstory;

  /// How they speak and think.
  final String personality;

  PodcastSpeaker copyWith({
    String? name,
    String? voice,
    String? backstory,
    String? personality,
  }) => PodcastSpeaker(
    name: name ?? this.name,
    voice: voice ?? this.voice,
    backstory: backstory ?? this.backstory,
    personality: personality ?? this.personality,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (voice.isNotEmpty) 'voice': voice,
    if (backstory.isNotEmpty) 'backstory': backstory,
    if (personality.isNotEmpty) 'personality': personality,
  };

  static PodcastSpeaker? fromJson(Object? json) {
    if (json is! Map || json['name'] is! String) return null;
    return PodcastSpeaker(
      name: json['name'] as String,
      voice: json['voice'] as String? ?? '',
      backstory: json['backstory'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
    );
  }
}

/// Who speaks in a podcast, and how they sound: one to four speakers, the
/// voice provider they speak through and its model.
class SpeakerProfile {
  const SpeakerProfile({
    required this.id,
    required this.name,
    required this.speakers,
    this.voiceId = '',
    this.voiceModel = '',
  });

  /// The most speakers a podcast has.
  static const int maxSpeakers = 4;

  /// The app's own, to start from.
  static const List<SpeakerProfile> originals = <SpeakerProfile>[
    SpeakerProfile(
      id: 'teacher-and-student',
      name: 'Teacher and student',
      speakers: <PodcastSpeaker>[
        PodcastSpeaker(
          name: 'Anna',
          backstory:
              'A teacher who knows the subject inside out and has taught it '
              'for years.',
          personality:
              'Warm and clear; explains with everyday examples, and checks '
              'that each step is understood before going on.',
        ),
        PodcastSpeaker(
          name: 'Ben',
          backstory:
              'A student revising these notes for a test, bright but meeting '
              'some of it for the first time.',
          personality:
              'Curious and honest about what confuses him; asks the questions '
              'a learner would, and sums up in his own words.',
        ),
      ],
    ),
    SpeakerProfile(
      id: 'two-classmates',
      name: 'Two classmates',
      speakers: <PodcastSpeaker>[
        PodcastSpeaker(
          name: 'Lena',
          backstory:
              'A student who took careful notes and likes to get to '
              'the bottom of things.',
          personality: 'Precise and patient; corrects mistakes kindly.',
        ),
        PodcastSpeaker(
          name: 'Max',
          backstory:
              'Her classmate, revising with her the night before the '
              'test.',
          personality:
              'Quick, funny and a little overconfident; remembers by '
              'stories and tricks.',
        ),
      ],
    ),
    SpeakerProfile(
      id: 'lecturer',
      name: 'Lecturer',
      speakers: <PodcastSpeaker>[
        PodcastSpeaker(
          name: 'Dr Hart',
          backstory:
              'A lecturer giving a short, well-built talk on the subject.',
          personality:
              'Calm and engaging; signposts where the talk is going, and '
              'ends each part with what to remember.',
        ),
      ],
    ),
  ];

  final String id;
  final String name;
  final List<PodcastSpeaker> speakers;

  /// The voice provider they speak through, or empty for the first set up.
  final String voiceId;

  /// The voice provider's model, or empty for the one it is set to.
  final String voiceModel;

  /// [speakers], each with a voice: theirs, or the [index]th of the voice
  /// provider's [voiceFor].
  List<PodcastSpeaker> voiced(
    String Function(int index) voiceFor,
  ) => <PodcastSpeaker>[
    for (final (i, speaker) in speakers.indexed)
      speaker.voice.isEmpty ? speaker.copyWith(voice: voiceFor(i)) : speaker,
  ];

  SpeakerProfile copyWith({
    String? name,
    List<PodcastSpeaker>? speakers,
    String? voiceId,
    String? voiceModel,
  }) => SpeakerProfile(
    id: id,
    name: name ?? this.name,
    speakers: speakers ?? this.speakers,
    voiceId: voiceId ?? this.voiceId,
    voiceModel: voiceModel ?? this.voiceModel,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'speakers': <Object?>[for (final s in speakers) s.toJson()],
    if (voiceId.isNotEmpty) 'voice': voiceId,
    if (voiceModel.isNotEmpty) 'voiceModel': voiceModel,
  };

  static SpeakerProfile? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final speakers = <PodcastSpeaker>[
      for (final entry in (json['speakers'] as List<Object?>?) ?? const [])
        ?PodcastSpeaker.fromJson(entry),
    ];
    if (speakers.isEmpty) return null;
    return SpeakerProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Speakers',
      speakers: speakers.take(maxSpeakers).toList(),
      voiceId: json['voice'] as String? ?? '',
      voiceModel: json['voiceModel'] as String? ?? '',
    );
  }
}

/// What kind of podcast to make: what it is about and how it goes (the
/// briefing), how many segments, in what language, who speaks, and the
/// models that plan it and write it.
class EpisodeProfile {
  const EpisodeProfile({
    required this.id,
    required this.name,
    required this.briefing,
    required this.speakersId,
    this.segments = 4,
    this.language = '',
    this.outline = ModelChoice.inUse,
    this.transcript = ModelChoice.inUse,
  });

  /// How many segments an episode can have.
  static const int fewestSegments = 2;
  static const int mostSegments = 12;

  /// The app's own, to start from.
  static const List<EpisodeProfile> originals = <EpisodeProfile>[
    EpisodeProfile(
      id: 'study-conversation',
      name: 'Study conversation',
      speakersId: 'teacher-and-student',
      briefing:
          'A conversation to revise these notes by ear. The student asks '
          'what a learner would ask; the teacher explains the ideas in the '
          'order the subject is best understood, with an example for each, '
          'and checks understanding. Every key definition, law and formula '
          'comes up, said in words. End with what to remember.',
    ),
    EpisodeProfile(
      id: 'exam-drill',
      name: 'Exam drill',
      speakersId: 'two-classmates',
      segments: 5,
      briefing:
          'Two classmates quiz each other on these notes before a test: '
          'one asks a question a test would ask, the other answers aloud, '
          'and they put right what was wrong or missing. Cover everything '
          'likely to be asked, the hard parts longest.',
    ),
    EpisodeProfile(
      id: 'short-lecture',
      name: 'Short lecture',
      speakersId: 'lecturer',
      segments: 3,
      briefing:
          'A short lecture that teaches what these notes cover, from the '
          'ground up, for someone hearing it on the way to school.',
    ),
  ];

  final String id;
  final String name;

  /// What the episode is to be, in the person's words.
  final String briefing;

  /// The speaker profile.
  final String speakersId;
  final int segments;

  /// The language to speak, or empty for the notes' own.
  final String language;

  /// The model that plans the episode.
  final ModelChoice outline;

  /// The model that writes what is said.
  final ModelChoice transcript;

  EpisodeProfile copyWith({
    String? name,
    String? briefing,
    String? speakersId,
    int? segments,
    String? language,
    ModelChoice? outline,
    ModelChoice? transcript,
  }) => EpisodeProfile(
    id: id,
    name: name ?? this.name,
    briefing: briefing ?? this.briefing,
    speakersId: speakersId ?? this.speakersId,
    segments: segments ?? this.segments,
    language: language ?? this.language,
    outline: outline ?? this.outline,
    transcript: transcript ?? this.transcript,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'briefing': briefing,
    'speakers': speakersId,
    'segments': segments,
    if (language.isNotEmpty) 'language': language,
    if (!outline.isInUse) 'outline': outline.toJson(),
    if (!transcript.isInUse) 'transcript': transcript.toJson(),
  };

  static EpisodeProfile? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return EpisodeProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Podcast',
      briefing: json['briefing'] as String? ?? '',
      speakersId: json['speakers'] as String? ?? '',
      segments: ((json['segments'] as int?) ?? 4).clamp(
        fewestSegments,
        mostSegments,
      ),
      language: json['language'] as String? ?? '',
      outline: ModelChoice.fromJson(json['outline']),
      transcript: ModelChoice.fromJson(json['transcript']),
    );
  }
}

/// How long a segment runs.
enum SegmentSize {
  short(3),
  medium(6),
  long(10);

  const SegmentSize(this.turns);

  /// How many times, at least, the speakers speak in it.
  final int turns;

  static SegmentSize read(Object? value) =>
      values.asNameMap()['$value'.trim().toLowerCase()] ?? medium;
}

/// A part of an episode, as planned: what it is called, what it goes
/// through, and how long it runs.
class PodcastSegment {
  const PodcastSegment({
    required this.name,
    this.description = '',
    this.size = SegmentSize.medium,
  });

  final String name;
  final String description;
  final SegmentSize size;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'size': size.name,
  };

  static PodcastSegment? fromJson(Object? json) => json is Map
      ? PodcastSegment(
          name: '${json['name'] ?? ''}',
          description: '${json['description'] ?? ''}',
          size: SegmentSize.read(json['size']),
        )
      : null;
}

/// What one speaker says, at once.
class PodcastLine {
  const PodcastLine({
    required this.speaker,
    required this.text,
    this.segment = 0,
  });

  final String speaker;
  final String text;

  /// The segment it is said in, from naught.
  final int segment;

  Map<String, Object?> toJson() => <String, Object?>{
    'speaker': speaker,
    'text': text,
    'segment': segment,
  };

  static PodcastLine? fromJson(Object? json) =>
      json is Map && json['speaker'] is String && json['text'] is String
      ? PodcastLine(
          speaker: json['speaker'] as String,
          text: json['text'] as String,
          segment: json['segment'] as int? ?? 0,
        )
      : null;
}

/// A podcast made: its plan, what is said, who said it in which voice, and
/// the sound file it was spoken into — kept apart from the notes, as every
/// thing the AI makes is.
class PodcastEpisode {
  const PodcastEpisode({
    required this.title,
    required this.profile,
    required this.outline,
    required this.lines,
    required this.speakers,
    this.audio = '',
    this.duration = Duration.zero,
    this.starts = const <Duration>[],
    this.voice = '',
    this.voiceId = '',
    this.models = const <String>[],
  });

  /// What marks a kept item as a podcast.
  static const String kindKey = 'podcast';

  final String title;

  /// The name of the episode profile it was made by.
  final String profile;
  final List<PodcastSegment> outline;
  final List<PodcastLine> lines;

  /// Who speaks, with the voices they were given.
  final List<PodcastSpeaker> speakers;

  /// The name of its sound file, or empty while it has none.
  final String audio;
  final Duration duration;

  /// Where in the sound each of [lines] begins.
  final List<Duration> starts;

  /// The voice provider and model it was spoken by, in words, and the id
  /// of that provider.
  final String voice;
  final String voiceId;

  /// The models that planned and wrote it, the planner first.
  final List<String> models;

  bool get spoken => audio.isNotEmpty;

  /// The line being said at [position], or null before the first.
  int? lineAt(Duration position) {
    int? at;
    for (final (i, start) in starts.indexed) {
      if (start > position) break;
      at = i;
    }
    return at;
  }

  PodcastEpisode copyWith({
    String? title,
    String? audio,
    Duration? duration,
    List<Duration>? starts,
    String? voice,
    String? voiceId,
    List<PodcastSpeaker>? speakers,
  }) => PodcastEpisode(
    title: title ?? this.title,
    profile: profile,
    outline: outline,
    lines: lines,
    speakers: speakers ?? this.speakers,
    audio: audio ?? this.audio,
    duration: duration ?? this.duration,
    starts: starts ?? this.starts,
    voice: voice ?? this.voice,
    voiceId: voiceId ?? this.voiceId,
    models: models,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    kindKey: 1,
    'title': title,
    'profile': profile,
    'outline': <Object?>[for (final s in outline) s.toJson()],
    'lines': <Object?>[for (final l in lines) l.toJson()],
    'speakers': <Object?>[for (final s in speakers) s.toJson()],
    if (audio.isNotEmpty) 'audio': audio,
    if (duration > Duration.zero) 'milliseconds': duration.inMilliseconds,
    if (starts.isNotEmpty)
      'starts': <int>[for (final start in starts) start.inMilliseconds],
    if (voice.isNotEmpty) 'voice': voice,
    if (voiceId.isNotEmpty) 'voiceId': voiceId,
    if (models.isNotEmpty) 'models': models,
  };

  /// The podcast kept as [json], or null if it is something else.
  static PodcastEpisode? fromJson(Object? json) {
    if (json is! Map || !json.containsKey(kindKey)) return null;
    List<T> list<T>(String key, T? Function(Object?) read) => <T>[
      for (final entry in (json[key] as List<Object?>?) ?? const [])
        ?read(entry),
    ];
    return PodcastEpisode(
      title: json['title'] as String? ?? 'Podcast',
      profile: json['profile'] as String? ?? '',
      outline: list('outline', PodcastSegment.fromJson),
      lines: list('lines', PodcastLine.fromJson),
      speakers: list('speakers', PodcastSpeaker.fromJson),
      audio: json['audio'] as String? ?? '',
      duration: Duration(milliseconds: json['milliseconds'] as int? ?? 0),
      starts: <Duration>[
        for (final start in (json['starts'] as List<Object?>?) ?? const [])
          if (start is int) Duration(milliseconds: start),
      ],
      voice: json['voice'] as String? ?? '',
      voiceId: json['voiceId'] as String? ?? '',
      models: <String>[
        for (final model in (json['models'] as List<Object?>?) ?? const [])
          if (model is String) model,
      ],
    );
  }
}

/// Where making a podcast has got to.
enum PodcastStage { gathering, outlining, writing, speaking, done }

/// How making a podcast is coming along.
class PodcastProgress {
  const PodcastProgress({
    required this.stage,
    this.activity = '',
    this.outline = const <PodcastSegment>[],
    this.lines = const <PodcastLine>[],
    this.step = 0,
    this.steps = 0,
    this.usage = const Usage(),
    this.cost,
    this.sound,
    this.starts = const <Duration>[],
  });

  final PodcastStage stage;

  /// What is being done, in words.
  final String activity;
  final List<PodcastSegment> outline;
  final List<PodcastLine> lines;

  /// How far through the stage it is, of [steps]: the segment being
  /// written, the line being spoken.
  final int step;
  final int steps;

  final Usage usage;

  /// What writing it cost, in US dollars, where it is known.
  final double? cost;

  /// Once spoken, the episode's sound, and where in it each line begins.
  final Sound? sound;
  final List<Duration> starts;

  bool get done => stage == PodcastStage.done;

  PodcastProgress copyWith({
    PodcastStage? stage,
    String? activity,
    List<PodcastSegment>? outline,
    List<PodcastLine>? lines,
    int? step,
    int? steps,
    Sound? sound,
  }) => PodcastProgress(
    stage: stage ?? this.stage,
    activity: activity ?? this.activity,
    outline: outline ?? this.outline,
    lines: lines ?? this.lines,
    step: step ?? this.step,
    steps: steps ?? this.steps,
    usage: usage,
    cost: cost,
    sound: sound ?? this.sound,
    starts: starts,
  );
}

/// A model to write with: who runs it, and its id.
typedef PodcastWriter = ({ChatProvider provider, String model});

/// Makes podcasts of the notes: plans them with [outliner], writes what is
/// said with [writer], and speaks it.
class PodcastMaker {
  PodcastMaker({
    required this.reader,
    required this.outliner,
    required this.writer,
    this.notesTokens = ContextBudget.defaultNotesTokens,
    this.about = '',
  });

  final NoteReader reader;
  final PodcastWriter outliner;
  final PodcastWriter writer;

  /// How many tokens of the notes go with each request, at most.
  final int notesTokens;

  /// What the person says of themselves.
  final String about;

  /// The most characters of what was said before that go with a segment
  /// to write: enough to go on from, not the whole episode again.
  static const int _transcriptSoFar = 12000;

  /// Plans an episode of [profile] about [scope], spoken by [speakers],
  /// and writes what is said, segment by segment.
  Stream<PodcastProgress> write(
    EpisodeProfile profile, {
    required List<PodcastSpeaker> speakers,
    required ScopeInfo scope,
  }) => stoppable(
    (stop) => _write(profile, speakers: speakers, scope: scope, stop: stop),
  );

  Stream<PodcastProgress> _write(
    EpisodeProfile profile, {
    required List<PodcastSpeaker> speakers,
    required ScopeInfo scope,
    required Future<void> stop,
  }) async* {
    var progress = const PodcastProgress(
      stage: PodcastStage.gathering,
      activity: 'Gathering your notes',
    );
    yield progress;
    final outlining = await outliner.provider.capabilitiesOf(outliner.model);
    final writing = await writer.provider.capabilitiesOf(writer.model);
    // What both can take.
    final budget = ContextBudget.forModel(
      ModelCapabilities(
        vision: outlining.vision && writing.vision,
        contextTokens: math.min(outlining.contextTokens, writing.contextTokens),
      ),
      notesTokens: notesTokens,
    );
    final given = await NoteContext(reader).build(scope, budget: budget);
    if (given.sources.isEmpty) {
      throw AiException(
        'There is nothing in this ${scope.kindName} to make a podcast of yet.',
      );
    }
    final notes = <ChatPart>[
      TextPart('<notes>\n${notesText(given.sources)}</notes>'),
      ...given.images,
    ];
    final system = systemPrompt(scope, about: about);
    var usage = const Usage();
    double? cost = 0;
    void spent(Usage used, ModelPrice? price) {
      usage = usage + used;
      final costs = used.costAt(price);
      cost = cost == null || costs == null ? null : cost! + costs;
    }

    PodcastProgress moved(PodcastProgress next) => PodcastProgress(
      stage: next.stage,
      activity: next.activity,
      outline: next.outline,
      lines: next.lines,
      step: next.step,
      steps: next.steps,
      usage: usage,
      cost: cost,
    );

    // The plan.
    progress = moved(
      progress.copyWith(
        stage: PodcastStage.outlining,
        activity: '${outliner.model} is planning the episode',
      ),
    );
    yield progress;
    List<PodcastSegment> outline = const <PodcastSegment>[];
    for (var attempt = 0; attempt < 2 && outline.isEmpty; attempt++) {
      late (String, Usage) answer;
      yield* _retrying(
        () async => answer = await _complete(
          outliner,
          ChatRequest(
            model: outliner.model,
            system: system,
            messages: <ChatMessage>[
              ChatMessage.user(<ChatPart>[
                ...notes,
                TextPart(outlinePrompt(profile, speakers: speakers)),
              ]),
            ],
            answerSchema: outlineSchema,
            stop: stop,
          ),
        ),
        stop: stop,
        moved: (activity) => moved(progress.copyWith(activity: activity)),
      );
      final (text, used) = answer;
      spent(used, outlining.price);
      outline = readOutline(text);
    }
    if (outline.isEmpty) {
      throw const AiException(
        'The model did not plan the episode in a form the app can read. '
        'Try again, or choose another model to plan it.',
      );
    }
    progress = moved(progress.copyWith(outline: outline));
    yield progress;

    // What is said, a segment at a time, each knowing what came before.
    final lines = <PodcastLine>[];
    for (final (index, segment) in outline.indexed) {
      progress = moved(
        progress.copyWith(
          stage: PodcastStage.writing,
          activity:
              '${writer.model} is writing “${segment.name}”, '
              '${index + 1} of ${outline.length}',
          step: index,
          steps: outline.length,
          lines: List<PodcastLine>.unmodifiable(lines),
        ),
      );
      yield progress;
      var said = const <PodcastLine>[];
      for (var attempt = 0; attempt < 2 && said.isEmpty; attempt++) {
        late (String, Usage) answer;
        yield* _retrying(
          () async => answer = await _complete(
            writer,
            ChatRequest(
              model: writer.model,
              system: system,
              messages: <ChatMessage>[
                ChatMessage.user(<ChatPart>[
                  ...notes,
                  TextPart(
                    transcriptPrompt(
                      profile,
                      speakers: speakers,
                      outline: outline,
                      segment: index,
                      soFar: lines,
                    ),
                  ),
                ]),
              ],
              answerSchema: transcriptSchema,
              stop: stop,
            ),
          ),
          stop: stop,
          moved: (activity) => moved(progress.copyWith(activity: activity)),
        );
        final (text, used) = answer;
        spent(used, writing.price);
        said = readTranscript(text, speakers: speakers, segment: index);
      }
      if (said.isEmpty) {
        throw AiException(
          'The model did not write “${segment.name}” in a form the app can '
          'read. Try again, or choose another model to write it.',
        );
      }
      lines.addAll(said);
    }
    yield moved(
      progress.copyWith(
        stage: PodcastStage.done,
        activity: 'Written',
        step: outline.length,
        lines: List<PodcastLine>.unmodifiable(lines),
      ),
    );
  }

  /// How many times a request is made before what went wrong is said:
  /// a router or a busy provider often fails once, and a podcast is many
  /// requests, any of which failing would lose the rest.
  static const int tries = 3;

  /// How long to wait before trying again after the [attempt]th try.
  static Duration Function(int attempt) wait = (attempt) =>
      Duration(seconds: 3 * attempt * attempt);

  /// Waits [delay], or until [stop], whichever comes first; whether it
  /// was stopped.
  static Future<bool> _pause(Duration delay, Future<void> stop) async {
    var stopped = false;
    await Future.any(<Future<void>>[
      Future<void>.delayed(delay),
      stop.then((_) => stopped = true),
    ]);
    return stopped;
  }

  /// Runs [request], trying again where what went wrong may pass — saying
  /// so with [moved] — up to [tries] times.
  static Stream<PodcastProgress> _retrying(
    Future<void> Function() request, {
    required Future<void> stop,
    required PodcastProgress Function(String activity) moved,
  }) async* {
    for (var attempt = 1; ; attempt++) {
      try {
        await request();
        return;
      } on AiException catch (error) {
        if (!error.retryable || attempt >= tries) rethrow;
        yield moved(
          '${error.message.replaceFirst(RegExp(r'[.\s]+$'), '')} — trying '
          'again (${attempt + 1} of $tries)',
        );
        if (await _pause(wait(attempt), stop)) rethrow;
      }
    }
  }

  /// What [request] gives, tried again as [_retrying] does, without saying
  /// so: for lines spoken many at once.
  static Future<T> _again<T>(
    Future<T> Function() request, {
    required Future<void> stop,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await request();
      } on AiException catch (error) {
        if (!error.retryable || attempt >= tries) rethrow;
        if (await _pause(wait(attempt), stop)) rethrow;
      }
    }
  }

  /// What [writer] answers to [request], in text, and what it used. Its
  /// reasoning is passed over: a model whose runtime does not tell it
  /// apart has it read from among the JSON.
  static Future<(String, Usage)> _complete(
    PodcastWriter writer,
    ChatRequest request,
  ) async {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    MessageDone? done;
    await for (final event in writer.provider.chat(request)) {
      switch (event) {
        case TextDelta(text: final delta):
          text.write(delta);
        case Reasoning(text: final delta):
          reasoning.write(delta);
        case MessageDone():
          done = event;
        case CitedSpan() || Activity():
          break;
      }
    }
    if (done == null) {
      throw const AiException('The model broke off. Try again.');
    }
    final written = text.toString().trim().isEmpty
        ? reasoning.toString()
        : text.toString();
    final counted = done.usage ?? const Usage();
    return (
      written,
      counted.isEmpty
          ? Usage(
              input: PromptSize.of(
                request.messages,
                system: request.system,
              ).tokens,
              output: written.length ~/ 4,
            )
          : counted,
    );
  }

  /// [lines] spoken through [speech], the voice of each speaker as
  /// [speakers] gives it, joined into one sound with a breath between
  /// speakers. [parallel] lines are spoken at once.
  static Stream<PodcastProgress> speak(
    List<PodcastLine> lines, {
    required List<PodcastSpeaker> speakers,
    required SpeechProvider speech,
    int parallel = 1,
  }) => stoppable(
    (stop) => _speak(
      lines,
      speakers: speakers,
      speech: speech,
      parallel: parallel,
      stop: stop,
    ),
  );

  static Stream<PodcastProgress> _speak(
    List<PodcastLine> lines, {
    required List<PodcastSpeaker> speakers,
    required SpeechProvider speech,
    required int parallel,
    required Future<void> stop,
  }) async* {
    if (lines.isEmpty) throw const AiException('There is nothing to speak.');
    var stopped = false;
    unawaited(stop.then((_) => stopped = true));
    PodcastSpeaker speakerOf(String name) =>
        speakers.where((s) => s.name == name).firstOrNull ?? speakers.first;
    final sounds = List<Sound?>.filled(lines.length, null);
    var spoken = 0;
    PodcastProgress at(int done) => PodcastProgress(
      stage: PodcastStage.speaking,
      activity:
          'Speaking line ${math.min(done + 1, lines.length)} of '
          '${lines.length}',
      lines: lines,
      step: done,
      steps: lines.length,
    );
    yield at(0);
    for (var from = 0; from < lines.length; from += parallel) {
      if (stopped) return;
      final batch = <Future<void>>[
        for (var i = from; i < math.min(from + parallel, lines.length); i++)
          () async {
            final line = lines[i];
            final speaker = speakerOf(line.speaker);
            final parts = <Sound>[
              for (final part in speechParts(line.text, speech.maxCharacters))
                await _again(
                  () => speech.speak(
                    part,
                    voice: speaker.voice,
                    instructions: speaker.personality,
                  ),
                  stop: stop,
                ),
            ];
            sounds[i] = Sound.join(parts);
          }(),
      ];
      await Future.wait(batch);
      spoken = math.min(from + parallel, lines.length);
      yield at(spoken);
    }
    // A breath between speakers; less within what one says.
    final joined = <Sound>[];
    final starts = <Duration>[];
    var length = Duration.zero;
    for (final (i, sound) in sounds.indexed) {
      final said = sound!.at(Sound.podcastRate);
      if (i > 0) {
        final turn = lines[i].speaker != lines[i - 1].speaker;
        final breath = Sound.silence(Duration(milliseconds: turn ? 350 : 200));
        joined.add(breath);
        length += breath.duration;
      }
      starts.add(length);
      joined.add(said);
      length += said.duration;
    }
    yield PodcastProgress(
      stage: PodcastStage.done,
      activity: 'Spoken',
      lines: lines,
      step: lines.length,
      steps: lines.length,
      sound: Sound.join(joined),
      starts: starts,
    );
  }

  /// [sources] as text to talk about: each page's title and where it is,
  /// then its paragraphs.
  static String notesText(List<Source> sources) {
    final out = StringBuffer();
    for (final source in sources) {
      out.writeln(
        '<page title="${source.title}"'
        '${source.context == null ? '' : ' where="${source.context}"'}>',
      );
      for (final (i, passage) in source.passages.indexed) {
        if (i > 0) out.write(passage.follows ? ' ' : '\n');
        out.write(passage.text);
      }
      out.writeln('\n</page>');
    }
    return out.toString();
  }

  /// The standing instructions for writing a podcast about [scope].
  static String systemPrompt(ScopeInfo scope, {String about = ''}) {
    final where = scope.path.isEmpty ? '' : ' (in ${scope.path.join(' › ')})';
    return '''
You write podcasts made from a student's own notes, in aantekening, a note-taking app, for the student to learn from by listening. The notes of the ${scope.kindName} "${scope.title}"$where are given; the pictures show their handwriting and drawings over printouts.

- Teach what the notes teach, correctly: follow the logic of the subject rather than the order of the notes, and reuse the student's own terms and phrases, which are easier for them to remember. Where the notes seem mistaken, say so.
- Everything you write is read aloud by a speech engine. Write only the words spoken: no Markdown, no lists, no headings, no stage directions, no sound effects, no emojis, no LaTeX or symbols. Say formulas and units in words, as a teacher reads them out — "v equals s over t", "nine point eight one metres per second squared".
- Answer with the JSON asked for and nothing else: no Markdown fence, no words before or after it.${about.trim().isEmpty ? '' : '\n\nWhat the student says about themselves — bear it in mind, as a teacher who knows them would:\n${about.trim()}'}''';
  }

  static String _speakersText(List<PodcastSpeaker> speakers) => <String>[
    for (final speaker in speakers)
      '- ${speaker.name}: ${speaker.backstory.trim()}'
          '${speaker.personality.trim().isEmpty ? '' : ' Personality: ${speaker.personality.trim()}'}',
  ].join('\n');

  static String _language(EpisodeProfile profile) =>
      profile.language.trim().isEmpty
      ? 'Write in the language the notes are written in.'
      : 'Write everything in ${profile.language.trim()}, but keep the JSON '
            'keys as they are.';

  /// What the planner is asked: [profile]'s episode in its segments.
  static String outlinePrompt(
    EpisodeProfile profile, {
    required List<PodcastSpeaker> speakers,
  }) {
    final n = profile.segments;
    return '''
Plan a podcast episode about these notes.

<briefing>
${profile.briefing.trim()}
</briefing>

<speakers>
${_speakersText(speakers)}
</speakers>

Divide the episode into exactly $n segments that together cover the briefing and the notes, flowing from one to the next: the first opens the episode, the last wraps it up. Segments only mark where the topic changes; nobody is introduced again in each. For each, give a short, clear name; a description of what is discussed in it — the ideas, examples and questions from the notes the writer is to cover; and its size, "short", "medium" or "long", by how much it holds and how much it matters. Match the content to the speakers' backgrounds.

${_language(profile)}

Answer with JSON alone, in this form, with all $n segments written out in full:
{"segments": [{"name": "…", "description": "…", "size": "medium"}]}''';
  }

  /// What the writer is asked: what is said in segment [segment] of
  /// [outline], going on from [soFar].
  static String transcriptPrompt(
    EpisodeProfile profile, {
    required List<PodcastSpeaker> speakers,
    required List<PodcastSegment> outline,
    required int segment,
    required List<PodcastLine> soFar,
  }) {
    final part = outline[segment];
    final names = <String>[for (final s in speakers) s.name];
    final solo = speakers.length == 1;
    final last = segment == outline.length - 1;
    var before = <String>[
      for (final line in soFar) '${line.speaker}: ${line.text}',
    ].join('\n');
    if (before.length > _transcriptSoFar) {
      before = '…${before.substring(before.length - _transcriptSoFar)}';
    }
    final plan = <String>[
      for (final (i, s) in outline.indexed)
        '${i + 1}. ${s.name} (${s.size.name}): ${s.description}',
    ].join('\n');
    return '''
Write what is said in one segment of a podcast episode about these notes.

<briefing>
${profile.briefing.trim()}
</briefing>

<speakers>
${_speakersText(speakers)}
</speakers>

<outline>
$plan
</outline>
${before.isEmpty ? '' : '\n<transcript_so_far>\n$before\n</transcript_so_far>\n'}
Write segment ${segment + 1} alone, "${part.name}": ${part.description}
${segment == 0 ? 'It opens the episode: greet the listener and say what it is about. ' : 'Go on from where the transcript so far stops, without greeting or introducing anyone again. '}${last ? 'It is the last segment: wrap up with what to remember, and say goodbye.' : 'Stop where the segment ends; the next is written after.'}

${solo ? 'Only ${names.first} speaks: present it alone, engagingly, and invent nobody else.' : 'Only ${names.join(', ')} speak; choose who says what by who they are, keep the exchanges balanced and natural, and avoid long monologues.'} Write at least ${part.size.turns} ${solo ? 'paragraphs' : 'turns'}. ${_language(profile)}

Answer with JSON alone, in this form, every "speaker" one of ${names.map((n) => '"$n"').join(', ')} exactly, every "dialogue" the finished words spoken:
{"transcript": [{"speaker": "${names.first}", "dialogue": "…"}]}''';
  }

  /// The JSON Schema of a plan.
  static const Map<String, Object?> outlineSchema = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'segments': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
            'description': <String, Object?>{'type': 'string'},
            'size': <String, Object?>{
              'type': 'string',
              'enum': <String>['short', 'medium', 'long'],
            },
          },
          'required': <String>['name', 'description', 'size'],
        },
      },
    },
    'required': <String>['segments'],
  };

  /// The JSON Schema of what is said in a segment.
  static const Map<String, Object?> transcriptSchema = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'transcript': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'speaker': <String, Object?>{'type': 'string'},
            'dialogue': <String, Object?>{'type': 'string'},
          },
          'required': <String>['speaker', 'dialogue'],
        },
      },
    },
    'required': <String>['transcript'],
  };

  /// The first list of maps in what a model [written], under one of
  /// [keys] a level or two down, or at the top.
  static List<Map<Object?, Object?>> _listIn(
    String written,
    List<String> keys,
  ) {
    List<Map<Object?, Object?>>? within(Object? value, int depth) {
      if (value is List &&
          value.whereType<Map<Object?, Object?>>().isNotEmpty) {
        return value.whereType<Map<Object?, Object?>>().toList();
      }
      if (value is! Map || depth > 2) return null;
      for (final entry in value.entries) {
        if (keys.contains('${entry.key}'.toLowerCase())) {
          if (within(entry.value, 3) case final found?) return found;
        }
      }
      for (final inner in value.values) {
        if (within(inner, depth + 1) case final found?) return found;
      }
      return null;
    }

    for (final read in LooseJson.valuesIn(written)) {
      if (within(read.value, 0) case final found? when found.isNotEmpty) {
        return found;
      }
    }
    return const <Map<Object?, Object?>>[];
  }

  static String _field(Map<Object?, Object?> map, List<String> names) {
    for (final entry in map.entries) {
      if (names.contains('${entry.key}'.toLowerCase()) && entry.value != null) {
        final value = entry.value;
        return (value is List ? value.join(' ') : '$value').trim();
      }
    }
    return '';
  }

  /// The plan a model [written], however it wrote it.
  static List<PodcastSegment> readOutline(String written) => <PodcastSegment>[
    for (final map in _listIn(written, const <String>[
      'segments',
      'outline',
      'parts',
      'sections',
    ]))
      if (_field(map, const <String>['name', 'title', 'heading', 'topic'])
          case final name when name.isNotEmpty)
        PodcastSegment(
          name: name,
          description: _field(map, const <String>[
            'description',
            'summary',
            'content',
            'points',
          ]),
          size: SegmentSize.read(
            _field(map, const <String>['size', 'length', 'duration']),
          ),
        ),
  ];

  /// What a model [written] is said in segment [segment], however it
  /// wrote it: each line given to the speaker of [speakers] it names, or
  /// the next in turn where it names none of them.
  static List<PodcastLine> readTranscript(
    String written, {
    required List<PodcastSpeaker> speakers,
    int segment = 0,
  }) {
    final names = <String>[for (final s in speakers) s.name];
    String? speakerOf(String said) {
      final name = said.trim().toLowerCase();
      if (name.isEmpty) return null;
      return names.where((n) => n.toLowerCase() == name).firstOrNull ??
          names
              .where(
                (n) =>
                    name.startsWith(n.toLowerCase()) ||
                    n.toLowerCase().startsWith(name),
              )
              .firstOrNull;
    }

    final lines = <PodcastLine>[];
    void add(String said, String text) {
      final words = _spoken(text);
      if (words.isEmpty) return;
      final previous = lines.lastOrNull?.speaker;
      final speaker =
          speakerOf(said) ??
          names[previous == null
              ? 0
              : (names.indexOf(previous) + 1) % names.length];
      lines.add(PodcastLine(speaker: speaker, text: words, segment: segment));
    }

    for (final map in _listIn(written, const <String>[
      'transcript',
      'dialogue',
      'dialog',
      'lines',
      'turns',
      'script',
    ])) {
      add(
        _field(map, const <String>['speaker', 'name', 'host', 'role', 'who']),
        _field(map, const <String>[
          'dialogue',
          'dialog',
          'text',
          'line',
          'content',
          'says',
          'speech',
        ]),
      );
    }
    if (lines.isNotEmpty) return lines;
    // Written as a play: "Name: words", a line each.
    final pattern = RegExp(r'^\s*\**([^:*\n]{1,40})\**\s*:\s*(.+)$');
    for (final line in written.split('\n')) {
      if (pattern.firstMatch(line) case final match?
          when speakerOf(match.group(1)!) != null) {
        add(match.group(1)!, match.group(2)!);
      }
    }
    return lines;
  }

  /// [text] as it is to be spoken: what is not words taken out.
  static String _spoken(String text) => text
      .replaceAll(RegExp(r'\*\*|__|`|#+ '), '')
      .replaceAll(RegExp(r'\[(?:[^\]]{0,40})\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

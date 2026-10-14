/// Turning words into speech, whoever speaks them: a service on the web, or
/// a speech server on this machine — and the sound they make, as samples a
/// podcast is put together from.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'provider.dart' show AiException;

/// The kinds of speech API a voice provider speaks.
enum SpeechKind {
  /// `POST /audio/speech`, as OpenAI has it, and with it the speech
  /// servers one runs oneself: Kokoro-FastAPI, Speaches, openedai-speech,
  /// LocalAI.
  openAi,

  /// Gemini's `generateContent`, asked for audio.
  gemini,

  /// ElevenLabs' `text-to-speech`.
  elevenLabs,
}

/// A voice provider the settings know how to set up: where it is, whether
/// it wants a key, the model to start with and the voices it is known to
/// have.
enum SpeechPreset {
  openAi(
    'OpenAI',
    SpeechKind.openAi,
    'https://api.openai.com/v1',
    needsKey: true,
    model: 'gpt-4o-mini-tts',
    voices: <String>[
      'alloy',
      'ash',
      'ballad',
      'coral',
      'echo',
      'fable',
      'nova',
      'onyx',
      'sage',
      'shimmer',
      'verse',
    ],
  ),
  requesty(
    'Requesty',
    SpeechKind.openAi,
    'https://router.requesty.ai/v1',
    needsKey: true,
    model: 'openai/gpt-4o-mini-tts',
    voices: <String>[
      'alloy',
      'ash',
      'ballad',
      'coral',
      'echo',
      'fable',
      'nova',
      'onyx',
      'sage',
      'shimmer',
      'verse',
    ],
  ),
  gemini(
    'Google Gemini',
    SpeechKind.gemini,
    'https://generativelanguage.googleapis.com/v1beta',
    needsKey: true,
    model: 'gemini-2.5-flash-preview-tts',
    voices: <String>[
      'Kore',
      'Puck',
      'Charon',
      'Aoede',
      'Fenrir',
      'Leda',
      'Orus',
      'Zephyr',
    ],
  ),
  elevenLabs(
    'ElevenLabs',
    SpeechKind.elevenLabs,
    'https://api.elevenlabs.io/v1',
    needsKey: true,
    model: 'eleven_multilingual_v2',
    // Voices every account has; their names come with the list of voices.
    voices: <String>[
      '21m00Tcm4TlvDq8ikWAM',
      'pNInz6obpgDQGcFmaJgB',
      'EXAVITQu4vr4xnJCMtqR',
      'TxGEqnHWrfWFTfGW9XjX',
    ],
  ),
  kokoro(
    'Kokoro',
    SpeechKind.openAi,
    'http://127.0.0.1:8880/v1',
    local: true,
    model: 'kokoro',
    voices: <String>[
      'af_heart',
      'am_michael',
      'af_bella',
      'am_adam',
      'bf_emma',
      'bm_george',
    ],
  ),
  custom(
    'Another OpenAI-compatible speech server',
    SpeechKind.openAi,
    'http://127.0.0.1:8000/v1',
    model: 'tts-1',
    voices: <String>['alloy', 'nova', 'onyx', 'echo'],
  );

  const SpeechPreset(
    this.label,
    this.kind,
    this.baseUrl, {
    required this.model,
    required this.voices,
    this.needsKey = false,
    this.local = false,
  });

  final String label;
  final SpeechKind kind;
  final String baseUrl;
  final bool needsKey;

  /// Whether it runs on this machine, so what is spoken stays on it.
  final bool local;

  /// The model to start with.
  final String model;

  /// The voices it is known to have, the first two different enough for
  /// two speakers to be told apart.
  final List<String> voices;

  /// Whether it is a server of one's own.
  bool get ownServer => local || this == custom;
}

/// A voice provider the person has set up, and the model of it they use.
class VoiceConfig {
  const VoiceConfig({
    required this.id,
    required this.preset,
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  /// A new configuration of [preset], identified by [id].
  factory VoiceConfig.of(SpeechPreset preset, {required String id}) =>
      VoiceConfig(
        id: id,
        preset: preset,
        name: preset.label,
        baseUrl: preset.baseUrl,
        model: preset.model,
      );

  final String id;
  final SpeechPreset preset;
  final String name;
  final String baseUrl;
  final String model;

  SpeechKind get kind => preset.kind;

  /// Whether what is spoken stays on this machine.
  bool get local {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return preset.local ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1';
  }

  /// The voice the [index]th speaker of a podcast gets where they were
  /// given none.
  String voiceFor(int index) =>
      preset.voices.isEmpty ? '' : preset.voices[index % preset.voices.length];

  /// A provider that speaks with [model] — or this one's — with [apiKey].
  SpeechProvider create({String? apiKey, String? model, http.Client? client}) {
    final use = (model ?? '').trim().isEmpty ? this.model : model!.trim();
    return switch (kind) {
      SpeechKind.openAi => OpenAiSpeech(
        baseUrl: baseUrl,
        model: use,
        apiKey: apiKey,
        knownVoices: preset.voices,
        client: client,
      ),
      SpeechKind.gemini => GeminiSpeech(
        baseUrl: baseUrl,
        model: use,
        apiKey: apiKey ?? '',
        knownVoices: preset.voices,
        client: client,
      ),
      SpeechKind.elevenLabs => ElevenLabsSpeech(
        baseUrl: baseUrl,
        model: use,
        apiKey: apiKey ?? '',
        client: client,
      ),
    };
  }

  VoiceConfig copyWith({String? name, String? baseUrl, String? model}) =>
      VoiceConfig(
        id: id,
        preset: preset,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'preset': preset.name,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
  };

  static VoiceConfig? fromJson(Map<String, Object?> json) {
    final preset = SpeechPreset.values.asNameMap()[json['preset']];
    final id = json['id'];
    if (preset == null || id is! String) return null;
    return VoiceConfig(
      id: id,
      preset: preset,
      name: json['name'] as String? ?? preset.label,
      baseUrl: json['baseUrl'] as String? ?? preset.baseUrl,
      model: json['model'] as String? ?? preset.model,
    );
  }
}

/// A voice to speak with: what the provider calls it, and what to show.
class VoiceInfo {
  const VoiceInfo(this.id, {String? name}) : name = name ?? id;

  final String id;
  final String name;

  @override
  String toString() => name;
}

/// Sound, as a podcast is put together from it: one channel of 16-bit
/// samples at [rate] a second.
class Sound {
  const Sound(this.samples, {this.rate = Sound.podcastRate});

  /// Silence lasting [duration].
  factory Sound.silence(Duration duration, {int rate = podcastRate}) => Sound(
    Int16List(duration.inMicroseconds * rate ~/ Duration.microsecondsPerSecond),
    rate: rate,
  );

  /// The rate every voice provider can speak at, and a podcast is kept at.
  static const int podcastRate = 24000;

  final Int16List samples;
  final int rate;

  Duration get duration => Duration(
    microseconds: samples.length * Duration.microsecondsPerSecond ~/ rate,
  );

  /// The same sound at [rate] a second.
  Sound at(int rate) {
    if (rate == this.rate || samples.isEmpty) return this;
    final length = (samples.length * rate / this.rate).round();
    final out = Int16List(length);
    final step = this.rate / rate;
    for (var i = 0; i < length; i++) {
      final at = i * step;
      final before = at.floor();
      final after = math.min(before + 1, samples.length - 1);
      final part = at - before;
      out[i] = (samples[before] * (1 - part) + samples[after] * part).round();
    }
    return Sound(out, rate: rate);
  }

  /// [sounds] one after another, at the rate of the first, [gap] between
  /// each.
  static Sound join(List<Sound> sounds, {Duration gap = Duration.zero}) {
    if (sounds.isEmpty) return Sound(Int16List(0));
    final rate = sounds.first.rate;
    final pause = Sound.silence(gap, rate: rate).samples.length;
    final parts = <Int16List>[
      for (final sound in sounds) sound.at(rate).samples,
    ];
    final out = Int16List(
      parts.fold<int>(0, (sum, part) => sum + part.length) +
          pause * (parts.length - 1),
    );
    var at = 0;
    for (final (i, part) in parts.indexed) {
      if (i > 0) at += pause;
      out.setAll(at, part);
      at += part.length;
    }
    return Sound(out, rate: rate);
  }

  /// Samples of 16-bit little-endian [pcm], one channel, at [rate].
  factory Sound.pcm(Uint8List pcm, {int rate = podcastRate}) {
    final data = ByteData.sublistView(pcm);
    final samples = Int16List(pcm.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little);
    }
    return Sound(samples, rate: rate);
  }

  /// The sound of a WAV file: 8-, 16-, 24- or 32-bit integer samples or
  /// 32-bit floating ones, its channels mixed to one. A server that
  /// streams its WAV may say its data runs on for ever; it is read to the
  /// end of what came.
  static Sound wav(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String tag(int at) => ascii.decode(bytes.sublist(at, at + 4));
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const AiException('The voice provider did not send a WAV file.');
    }
    var format = 1;
    var channels = 1;
    var rate = podcastRate;
    var bits = 16;
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = tag(at);
      var size = data.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ') {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        rate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 26) {
          // WAVE_FORMAT_EXTENSIBLE: the format is the sub-format's first
          // two bytes.
          format = data.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        if (size == 0 || size == 0xFFFFFFFF || body + size > bytes.length) {
          size = bytes.length - body;
        }
        return _samples(
          ByteData.sublistView(bytes, body, body + size),
          format: format,
          channels: math.max(channels, 1),
          bits: bits,
          rate: rate,
        );
      }
      at = body + size + (size.isOdd ? 1 : 0);
    }
    throw const AiException('The WAV file the voice provider sent is empty.');
  }

  static Sound _samples(
    ByteData data, {
    required int format,
    required int channels,
    required int bits,
    required int rate,
  }) {
    final width = bits ~/ 8;
    if (width == 0) {
      throw const AiException('The voice provider sent a WAV file of no bits.');
    }
    final frames = data.lengthInBytes ~/ (width * channels);
    final out = Int16List(frames);
    double sample(int at) => switch ((format, bits)) {
      (3, 32) => data.getFloat32(at, Endian.little),
      (_, 8) => (data.getUint8(at) - 128) / 128,
      (_, 16) => data.getInt16(at, Endian.little) / 32768,
      (_, 24) =>
        ((data.getUint8(at) |
                    data.getUint8(at + 1) << 8 |
                    data.getInt8(at + 2) << 16) /
                8388608)
            .toDouble(),
      (_, 32) => data.getInt32(at, Endian.little) / 2147483648,
      _ => throw AiException(
        'The voice provider sent WAV samples the app cannot read ($bits-bit, '
        'format $format).',
      ),
    };
    for (var frame = 0; frame < frames; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        sum += sample((frame * channels + channel) * width);
      }
      out[frame] = (sum / channels * 32768).round().clamp(-32768, 32767);
    }
    return Sound(out, rate: rate);
  }

  /// This sound as a WAV file.
  Uint8List toWav() {
    final bytes = samples.length * 2;
    final out = ByteData(44 + bytes);
    void tag(int at, String text) {
      for (var i = 0; i < 4; i++) {
        out.setUint8(at + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    out.setUint32(4, 36 + bytes, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 1, Endian.little);
    out.setUint32(24, rate, Endian.little);
    out.setUint32(28, rate * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    out.setUint32(40, bytes, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      out.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return out.buffer.asUint8List();
  }
}

/// Something that speaks: words in, [Sound] out.
abstract interface class SpeechProvider {
  /// The voices it has: as the provider lists them, or as they are known.
  Future<List<VoiceInfo>> listVoices();

  /// [text] spoken by [voice]. Where the provider takes them,
  /// [instructions] say how — the speaker's manner.
  Future<Sound> speak(
    String text, {
    required String voice,
    String instructions = '',
  });

  /// The most characters it takes at once; longer text is spoken in parts.
  int get maxCharacters;

  void close();
}

/// Splits [text] into parts of at most [max] characters, between
/// sentences where it can, else between words.
List<String> speechParts(String text, int max) {
  final parts = <String>[];
  var rest = text.trim();
  while (rest.length > max) {
    var cut = -1;
    for (final match in RegExp(r'[.!?…;:]\s').allMatches(rest)) {
      if (match.end > max) break;
      cut = match.end;
    }
    if (cut <= 0) cut = rest.lastIndexOf(' ', max);
    if (cut <= 0) cut = max;
    parts.add(rest.substring(0, cut).trim());
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) parts.add(rest);
  return parts;
}

/// What went wrong asking a voice provider, in words.
AiException _failed(String who, http.Response response) {
  var detail = response.body.trim();
  try {
    final json = jsonDecode(detail);
    if (json is Map) {
      final error = json['error'] ?? json['detail'];
      detail = switch (error) {
        {'message': final String message} => message,
        final String message => message,
        _ => detail,
      };
    }
  } on FormatException {
    // Not JSON: said as it came.
  }
  if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
  return AiException(
    '$who answered ${response.statusCode}${detail.isEmpty ? '' : ': $detail'}',
    status: response.statusCode,
    // A provider busy or down may answer the next time.
    retryable: response.statusCode == 429 || response.statusCode >= 500,
  );
}

Future<http.Response> _send(
  http.Client client,
  String who,
  Future<http.Response> Function() request,
) async {
  try {
    return await request();
  } on http.ClientException catch (error) {
    throw AiException(
      '$who could not be reached: ${error.message}',
      retryable: true,
    );
  }
}

/// The OpenAI speech API, and the servers that speak it.
class OpenAiSpeech implements SpeechProvider {
  OpenAiSpeech({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.knownVoices = const <String>[],
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String model;
  final String? apiKey;
  final List<String> knownVoices;
  final http.Client _client;

  Map<String, String> get _headers => <String, String>{
    'Content-Type': 'application/json',
    if ((apiKey ?? '').isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  String get _who => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  @override
  int get maxCharacters => 4000;

  @override
  Future<List<VoiceInfo>> listVoices() async {
    // Kokoro-FastAPI and others list theirs; OpenAI does not.
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/audio/voices'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final list = switch (json) {
          {'voices': final List<Object?> voices} => voices,
          {'data': final List<Object?> voices} => voices,
          final List<Object?> voices => voices,
          _ => const <Object?>[],
        };
        final voices = <VoiceInfo?>[
          for (final voice in list)
            switch (voice) {
              final String id => VoiceInfo(id),
              {'id': final String id} => VoiceInfo(
                id,
                name: (voice as Map)['name'] as String?,
              ),
              {'voice_id': final String id} => VoiceInfo(
                id,
                name: (voice as Map)['name'] as String?,
              ),
              _ => null,
            },
        ].nonNulls.toList();
        if (voices.isNotEmpty) return voices;
      }
    } on Object {
      // Not listed: the voices known are offered.
    }
    return <VoiceInfo>[for (final voice in knownVoices) VoiceInfo(voice)];
  }

  @override
  Future<Sound> speak(
    String text, {
    required String voice,
    String instructions = '',
  }) async {
    final response = await _send(
      _client,
      _who,
      () => _client.post(
        Uri.parse('$baseUrl/audio/speech'),
        headers: _headers,
        body: jsonEncode(<String, Object?>{
          'model': model,
          'input': text,
          'voice': voice,
          'response_format': 'wav',
          // Only OpenAI's newer models are told how to speak — by their
          // own name, or a router's (`openai/gpt-4o-mini-tts`); others may
          // refuse what they do not know.
          if (instructions.trim().isNotEmpty &&
              RegExp('(^|/)gpt-').hasMatch(model))
            'instructions': instructions.trim(),
        }),
      ),
    );
    if (response.statusCode != 200) throw _failed(_who, response);
    return Sound.wav(response.bodyBytes);
  }

  @override
  void close() => _client.close();
}

/// Gemini, asked to answer in sound.
class GeminiSpeech implements SpeechProvider {
  GeminiSpeech({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.knownVoices = const <String>[],
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String model;
  final String apiKey;
  final List<String> knownVoices;
  final http.Client _client;

  @override
  int get maxCharacters => 4000;

  @override
  Future<List<VoiceInfo>> listVoices() async => <VoiceInfo>[
    for (final voice in knownVoices) VoiceInfo(voice),
  ];

  @override
  Future<Sound> speak(
    String text, {
    required String voice,
    String instructions = '',
  }) async {
    final say = instructions.trim().isEmpty
        ? text
        : '${instructions.trim()}:\n$text';
    final response = await _send(
      _client,
      'Gemini',
      () => _client.post(
        Uri.parse('$baseUrl/models/$model:generateContent'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: jsonEncode(<String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': say},
              ],
            },
          ],
          'generationConfig': <String, Object?>{
            'responseModalities': <String>['AUDIO'],
            'speechConfig': <String, Object?>{
              'voiceConfig': <String, Object?>{
                'prebuiltVoiceConfig': <String, Object?>{'voiceName': voice},
              },
            },
          },
        }),
      ),
    );
    if (response.statusCode != 200) throw _failed('Gemini', response);
    final json = jsonDecode(response.body);
    final parts = switch (json) {
      {
        'candidates': [{'content': {'parts': final List<Object?> parts}}, ...],
      } =>
        parts,
      _ => const <Object?>[],
    };
    for (final part in parts) {
      if (part case {
        'inlineData': {
          'data': final String data,
          'mimeType': final String type,
        },
      }) {
        final bytes = base64Decode(data);
        if (type.contains('wav')) return Sound.wav(bytes);
        final rate = int.tryParse(
          RegExp(r'rate=(\d+)').firstMatch(type)?.group(1) ?? '',
        );
        return Sound.pcm(bytes, rate: rate ?? Sound.podcastRate);
      }
    }
    throw const AiException('Gemini answered without sound.');
  }

  @override
  void close() => _client.close();
}

/// ElevenLabs.
class ElevenLabsSpeech implements SpeechProvider {
  ElevenLabsSpeech({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String model;
  final String apiKey;
  final http.Client _client;

  Map<String, String> get _headers => <String, String>{
    'Content-Type': 'application/json',
    'xi-api-key': apiKey,
  };

  @override
  int get maxCharacters => 4500;

  @override
  Future<List<VoiceInfo>> listVoices() async {
    final response = await _send(
      _client,
      'ElevenLabs',
      () => _client.get(Uri.parse('$baseUrl/voices'), headers: _headers),
    );
    if (response.statusCode != 200) throw _failed('ElevenLabs', response);
    return switch (jsonDecode(response.body)) {
      {'voices': final List<Object?> voices} => <VoiceInfo>[
        for (final voice in voices)
          if (voice case {'voice_id': final String id})
            VoiceInfo(id, name: (voice as Map)['name'] as String?),
      ],
      _ => const <VoiceInfo>[],
    };
  }

  @override
  Future<Sound> speak(
    String text, {
    required String voice,
    String instructions = '',
  }) async {
    final response = await _send(
      _client,
      'ElevenLabs',
      () => _client.post(
        Uri.parse(
          '$baseUrl/text-to-speech/$voice'
          '?output_format=pcm_${Sound.podcastRate}',
        ),
        headers: _headers,
        body: jsonEncode(<String, Object?>{'text': text, 'model_id': model}),
      ),
    );
    if (response.statusCode != 200) throw _failed('ElevenLabs', response);
    return Sound.pcm(response.bodyBytes);
  }

  @override
  void close() => _client.close();
}

/// An [LocalModelClient] backed by a local Ollama server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_settings.dart';
import 'model_client.dart';

/// Talks to Ollama over its HTTP API.
///
/// Ollama is used as the first backend because it is open source, installs as a
/// single binary on Linux, Windows and Android-adjacent hosts, and exposes a
/// stable HTTP interface — so the app needs no native bindings and no bundled
/// model weights.
class OllamaClient implements LocalModelClient {
  OllamaClient({required this.settings, http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  final AiSettings settings;
  final http.Client _http;
  final bool _ownsClient;

  @override
  String get backendName => 'Ollama';

  Uri _uri(String path) => Uri.parse('${settings.baseUrl}$path');

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _http
          .get(_uri('/api/tags'))
          // A short timeout: this runs on app start to decide whether to offer
          // the AI features, and must never delay the first frame.
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<ModelInfo>> listModels() async {
    final response = await _get('/api/tags');
    final models = response['models'];
    if (models is! List) return const <ModelInfo>[];

    return <ModelInfo>[
      for (final entry in models)
        if (entry is Map<String, Object?>)
          ModelInfo(
            name: _string(entry['name']) ?? _string(entry['model']) ?? '?',
            parameterSize: _string(
              (entry['details'] as Map<String, Object?>?)?['parameter_size'],
            ),
            quantization: _string(
              (entry['details']
                  as Map<String, Object?>?)?['quantization_level'],
            ),
            sizeInBytes: entry['size'] is num
                ? (entry['size']! as num).toInt()
                : null,
          ),
    ];
  }

  @override
  Stream<String> generate(GenerationRequest request) async* {
    final httpRequest = http.Request('POST', _uri('/api/generate'))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(_generateBody(request, stream: true));

    final http.StreamedResponse response;
    try {
      response = await _http.send(httpRequest).timeout(settings.requestTimeout);
    } on Object catch (error) {
      throw LocalModelException('Could not reach Ollama', cause: error);
    }

    if (response.statusCode != 200) {
      throw LocalModelException(
        'Ollama refused the request (HTTP ${response.statusCode})',
      );
    }

    // Responses arrive as newline-delimited JSON, one object per token batch.
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        // A partial line is not worth aborting a long generation for.
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;

      final error = _string(decoded['error']);
      if (error != null) throw LocalModelException(error);

      final chunk = _string(decoded['response']);
      if (chunk != null && chunk.isNotEmpty) yield chunk;
      if (decoded['done'] == true) return;
    }
  }

  @override
  Future<String> complete(GenerationRequest request) async {
    final buffer = StringBuffer();
    await for (final chunk in generate(request)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  @override
  Future<List<Float32List>> embed(
    List<String> texts, {
    required String model,
  }) async {
    if (texts.isEmpty) return const <Float32List>[];

    final response = await _post('/api/embed', <String, Object?>{
      'model': model,
      'input': texts,
    });

    final embeddings = response['embeddings'];
    if (embeddings is! List) {
      throw const LocalModelException('Ollama returned no embeddings');
    }
    return <Float32List>[for (final vector in embeddings) _toFloat32(vector)];
  }

  Map<String, Object?> _generateBody(
    GenerationRequest request, {
    required bool stream,
  }) {
    final options = <String, Object?>{'temperature': request.temperature};
    if (request.maxTokens != null) options['num_predict'] = request.maxTokens;
    if (request.stop.isNotEmpty) options['stop'] = request.stop;

    return <String, Object?>{
      'model': request.model,
      'prompt': request.prompt,
      if (request.system != null) 'system': request.system,
      'stream': stream,
      'options': options,
    };
  }

  Future<Map<String, Object?>> _get(String path) async {
    final http.Response response;
    try {
      response = await _http.get(_uri(path)).timeout(settings.requestTimeout);
    } on Object catch (error) {
      throw LocalModelException('Could not reach Ollama', cause: error);
    }
    return _decode(response);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _uri(path),
            headers: <String, String>{'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(settings.requestTimeout);
    } on Object catch (error) {
      throw LocalModelException('Could not reach Ollama', cause: error);
    }
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw LocalModelException(
        'Ollama returned HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const LocalModelException('Ollama returned an unexpected payload');
    }
    return decoded;
  }

  static Float32List _toFloat32(Object? value) {
    if (value is! List) {
      throw const LocalModelException('Embedding was not a list of numbers');
    }
    final vector = Float32List(value.length);
    for (var i = 0; i < value.length; i++) {
      final component = value[i];
      vector[i] = component is num ? component.toDouble() : 0;
    }
    return vector;
  }

  static String? _string(Object? value) => value is String ? value : null;

  @override
  void close() {
    if (_ownsClient) _http.close();
  }
}

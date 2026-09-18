/// The contract every local model backend implements.
library;

import 'dart:typed_data';

/// A model the local runtime has available.
class ModelInfo {
  const ModelInfo({
    required this.name,
    this.parameterSize,
    this.quantization,
    this.sizeInBytes,
  });

  /// The identifier used when requesting this model.
  final String name;

  /// Human-readable parameter count, such as `7B`.
  final String? parameterSize;

  /// Quantisation scheme, such as `Q4_K_M`.
  final String? quantization;

  final int? sizeInBytes;

  @override
  String toString() => name;
}

/// A request for text generation.
class GenerationRequest {
  const GenerationRequest({
    required this.model,
    required this.prompt,
    this.system,
    this.temperature = 0.2,
    this.maxTokens,
    this.stop = const <String>[],
  });

  final String model;
  final String prompt;

  /// Instructions that frame the request, kept separate from the user's text.
  final String? system;

  /// Lower values keep the model close to the note's own wording, which is
  /// what most note-taking tasks want.
  final double temperature;

  final int? maxTokens;
  final List<String> stop;
}

/// Raised when a local model backend cannot be reached or refuses a request.
class LocalModelException implements Exception {
  const LocalModelException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'LocalModelException: $message'
      : 'LocalModelException: $message ($cause)';
}

/// A locally running language-model runtime.
///
/// Everything goes through this interface so that no part of the app talks to
/// a specific runtime. Notes are private by default: the only implementations
/// shipped are ones that run on the user's own machine, and adding another
/// backend — llama.cpp over FFI, or a self-hosted server — means writing one
/// class, not touching the features that use it.
abstract interface class LocalModelClient {
  /// A short name for the backend, shown in settings.
  String get backendName;

  /// Whether the runtime is reachable right now.
  ///
  /// Never throws: a missing runtime is an ordinary state for a feature that is
  /// optional by design, not an error to surface to the user.
  Future<bool> isAvailable();

  /// The models the runtime has locally.
  Future<List<ModelInfo>> listModels();

  /// Generates a completion, streaming it token by token.
  Stream<String> generate(GenerationRequest request);

  /// Generates a completion and returns it whole.
  Future<String> complete(GenerationRequest request);

  /// Embeds [texts] with [model], returning one vector each.
  Future<List<Float32List>> embed(List<String> texts, {required String model});

  /// Releases any held connections.
  void close();
}

/// Interfaces to language models running on the user's own machine.
///
/// Nothing in this package talks to a hosted service. Notes are private, so the
/// AI features are opt-in, are off until a model is configured, and degrade to
/// simply being absent when no local runtime is installed.
library;

export 'src/ai_settings.dart';
export 'src/model_client.dart';
export 'src/note_assistant.dart';
export 'src/ollama_client.dart';
export 'src/text_chunker.dart';

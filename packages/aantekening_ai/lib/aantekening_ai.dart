/// Models answering questions about notes, whoever runs them: a runtime on
/// this machine, or a service on the web the person chooses.
///
/// Everything goes through [ChatProvider]: one class for each kind of API,
/// and the features written once over them. The notes go to a model only
/// when the person asks it something, and only to the model they chose.
library;

export 'src/ai_settings.dart';
export 'src/answer.dart';
export 'src/anthropic_provider.dart';
export 'src/citation_markers.dart';
export 'src/conversation.dart';
export 'src/note_agent.dart';
export 'src/note_context.dart';
export 'src/note_reader.dart';
export 'src/note_tools.dart';
export 'src/ollama_provider.dart';
export 'src/openai_compatible_provider.dart';
export 'src/provider.dart';
export 'src/review.dart';
export 'src/streamed_answer.dart';
export 'src/study.dart';
export 'src/web_search.dart';

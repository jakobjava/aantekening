/// Note-specific tasks built on top of a local model.
library;

import 'dart:typed_data';

import 'ai_settings.dart';
import 'model_client.dart';
import 'text_chunker.dart';

/// Runs the assistant features against a local model.
///
/// Prompts are built here, as pure functions, so they can be reviewed and
/// tested without a model running. Every one of them instructs the model to
/// work only from the supplied notes: an assistant that invents plausible
/// content is worse than no assistant at all when the output will be read back
/// later as if it were the user's own notes.
class NoteAssistant {
  const NoteAssistant({
    required this.client,
    required this.settings,
    this.chunker = const TextChunker(),
  });

  final LocalModelClient client;
  final AiSettings settings;
  final TextChunker chunker;

  /// Summarises a page, streaming the answer as it is produced.
  Stream<String> summarize(String pageText, {int bulletPoints = 5}) {
    _requireChatModel();
    return client.generate(
      GenerationRequest(
        model: settings.chatModel,
        system: summarySystemPrompt,
        prompt: buildSummaryPrompt(pageText, bulletPoints: bulletPoints),
        temperature: 0.1,
      ),
    );
  }

  /// Answers [question] using [passages] retrieved from the workspace.
  Stream<String> ask(String question, List<RetrievedPassage> passages) {
    _requireChatModel();
    return client.generate(
      GenerationRequest(
        model: settings.chatModel,
        system: answerSystemPrompt,
        prompt: buildAnswerPrompt(question, passages),
        temperature: 0.1,
      ),
    );
  }

  /// Suggests a title for a page from its text.
  Future<String> suggestTitle(String pageText) async {
    _requireChatModel();
    final title = await client.complete(
      GenerationRequest(
        model: settings.chatModel,
        system: 'You write short, specific titles. Reply with the title only.',
        prompt:
            'Give this page a title of at most six words.\n\n'
            '---\n${_clip(pageText, 2000)}\n---',
        temperature: 0.3,
        maxTokens: 24,
      ),
    );
    return title.trim().replaceAll('"', '');
  }

  /// Splits [pageText] into passages and embeds each one.
  Future<List<({TextChunk chunk, Float32List vector})>> embedPage(
    String pageText,
  ) async {
    if (!settings.canEmbed) {
      throw const LocalModelException('No embedding model is configured');
    }
    final chunks = chunker.split(pageText);
    if (chunks.isEmpty) {
      return const <({TextChunk chunk, Float32List vector})>[];
    }

    final vectors = await client.embed(<String>[
      for (final chunk in chunks) chunk.text,
    ], model: settings.embeddingModel);
    if (vectors.length != chunks.length) {
      throw const LocalModelException(
        'The embedding model returned a different number of vectors '
        'than passages sent',
      );
    }
    return <({TextChunk chunk, Float32List vector})>[
      for (var i = 0; i < chunks.length; i++)
        (chunk: chunks[i], vector: vectors[i]),
    ];
  }

  /// Embeds a search query.
  Future<Float32List> embedQuery(String query) async {
    if (!settings.canEmbed) {
      throw const LocalModelException('No embedding model is configured');
    }
    final vectors = await client.embed(<String>[
      query,
    ], model: settings.embeddingModel);
    if (vectors.isEmpty) {
      throw const LocalModelException('The embedding model returned nothing');
    }
    return vectors.first;
  }

  void _requireChatModel() {
    if (!settings.canChat) {
      throw const LocalModelException('No chat model is configured');
    }
  }

  // ----------------------------------------------------------------- prompts

  /// Instructions for summarising.
  static const String summarySystemPrompt =
      'You summarise a person\'s own study notes. Use only what the notes '
      'contain. Never add facts, examples or conclusions that are not there. '
      'If the notes are too fragmentary to summarise, say so in one line. '
      'Keep the author\'s terminology and notation.';

  /// Instructions for answering questions over retrieved notes.
  static const String answerSystemPrompt =
      'You answer questions using only the supplied excerpts from the '
      'person\'s notes. Cite the page titles you drew on. If the excerpts do '
      'not contain the answer, say exactly that rather than guessing.';

  /// Builds the summarisation prompt.
  static String buildSummaryPrompt(String pageText, {int bulletPoints = 5}) =>
      'Summarise the following page in at most $bulletPoints bullet points.\n\n'
      '---\n${_clip(pageText, 12000)}\n---';

  /// Builds a retrieval-augmented question prompt.
  static String buildAnswerPrompt(
    String question,
    List<RetrievedPassage> passages,
  ) {
    final buffer = StringBuffer();
    if (passages.isEmpty) {
      buffer.writeln('No excerpts from the notes matched this question.');
    } else {
      buffer.writeln('Excerpts from the notes:');
      for (var i = 0; i < passages.length; i++) {
        final passage = passages[i];
        buffer
          ..writeln()
          ..writeln('[${i + 1}] from "${passage.pageTitle}":')
          ..writeln(_clip(passage.text, 2000));
      }
    }
    buffer
      ..writeln()
      ..writeln('Question: $question');
    return buffer.toString();
  }

  /// Truncates at a word boundary so a prompt cannot blow past the context
  /// window on a long page.
  static String _clip(String text, int limit) {
    if (text.length <= limit) return text;
    final cut = text.lastIndexOf(' ', limit);
    return '${text.substring(0, cut > 0 ? cut : limit)}…';
  }
}

/// A passage retrieved from the workspace to ground an answer.
class RetrievedPassage {
  const RetrievedPassage({
    required this.pageId,
    required this.pageTitle,
    required this.text,
    this.similarity = 0,
  });

  final String pageId;
  final String pageTitle;
  final String text;
  final double similarity;
}

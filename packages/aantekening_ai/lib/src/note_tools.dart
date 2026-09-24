/// The tools a model uses to read the notes: search them, read a page,
/// look at what is drawn on one, and search the web where its provider
/// cannot.
library;

import 'dart:convert';

import 'package:aantekening_core/aantekening_core.dart';

import 'anthropic_provider.dart';
import 'conversation.dart';
import 'note_context.dart';
import 'note_reader.dart';
import 'openai_compatible_provider.dart';
import 'provider.dart';
import 'web_search.dart';

/// The tools for a conversation about [scope], and running them.
class NoteTools {
  NoteTools({
    required this.reader,
    required this.scope,
    this.vision = false,
    this.webSearch,
  });

  final NoteReader reader;
  final ScopeInfo scope;

  /// Whether the model can look at pictures, and so be given [lookAt].
  final bool vision;

  /// The web, searched by the app, for a model whose provider cannot.
  final WebSearch? webSearch;

  static const String searchNotes = 'search_notes';
  static const String readPage = 'read_page';
  static const String lookAt = 'look_at';
  static const String searchWeb = 'search_web';

  List<ToolSpec> get specs => <ToolSpec>[
    const ToolSpec(
      name: searchNotes,
      description:
          'Searches the person\'s notes for words and gives back the '
          'passages that contain them, with the pages they are on. Use it '
          'whenever the question may be answered somewhere in the notes '
          'that you have not been given — set everywhere to true to look '
          'beyond the notebook, section or page being asked about.',
      parameters: <String, Map<String, Object?>>{
        'query': <String, Object?>{
          'type': 'string',
          'description': 'The words to look for, as they would be written.',
        },
        'everywhere': <String, Object?>{
          'type': 'boolean',
          'description':
              'Search all notes rather than only those being asked about.',
        },
      },
      required: <String>['query', 'everywhere'],
    ),
    const ToolSpec(
      name: readPage,
      description:
          'Reads a page of the notes whole: its text, formulas, tables, the '
          'text of its PDF pages, and which visuals it has. Use it for a '
          'page named in the overview or a search that you need more of.',
      parameters: <String, Map<String, Object?>>{
        'page_id': <String, Object?>{
          'type': 'string',
          'description': 'The page\'s id, as in [page …].',
        },
      },
      required: <String>['page_id'],
    ),
    if (vision)
      const ToolSpec(
        name: lookAt,
        description:
            'Shows visuals of a page as images: handwriting, drawings, '
            'pictures, PDF pages with what was written over them. Use it '
            'before saying anything about what a visual shows — handwriting '
            'and drawings are not in the text at all.',
        parameters: <String, Map<String, Object?>>{
          'page_id': <String, Object?>{'type': 'string'},
          'visuals': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'The visuals\' ids, like v2, at most four.',
          },
        },
        required: <String>['page_id', 'visuals'],
      ),
    if (webSearch != null)
      const ToolSpec(
        name: searchWeb,
        description:
            'Searches the web. Use it for what the notes do not cover and '
            'is current, specific or checkable — never in place of the '
            'notes.',
        parameters: <String, Map<String, Object?>>{
          'query': <String, Object?>{'type': 'string'},
        },
        required: <String>['query'],
      ),
  ];

  /// What [call] is doing, said for the person watching.
  String describe(ToolCallPart call) {
    final input = call.input;
    return switch (call.name) {
      searchNotes =>
        'Searching ${input['everywhere'] == true ? 'all your notes' : 'these notes'} '
            'for “${input['query']}”',
      readPage => 'Reading a page',
      lookAt =>
        'Looking at ${(input['visuals'] as List?)?.length ?? 1} '
            'visual${(input['visuals'] as List?)?.length == 1 ? '' : 's'}',
      searchWeb => 'Searching the web for “${input['query']}”',
      _ => 'Working',
    };
  }

  /// Runs [call], answering what it asks or saying why it cannot.
  Future<ToolResultPart> run(ToolCallPart call) async {
    final input = call.input;
    final broken =
        input[AnthropicProvider.invalidInputKey] ??
        input[OpenAiCompatibleProvider.invalidInputKey];
    if (broken != null) {
      return _error(
        call,
        jsonEncode(<String, Object?>{'INVALID_JSON': '$broken'}),
      );
    }
    try {
      return switch (call.name) {
        searchNotes => await _search(call),
        readPage => await _read(call),
        lookAt when vision => await _look(call),
        searchWeb when webSearch != null => await _web(call),
        _ => _error(call, 'There is no tool called ${call.name}.'),
      };
    } on AiException catch (error) {
      return _error(call, error.message);
    }
  }

  Future<ToolResultPart> _search(ToolCallPart call) async {
    final query = '${call.input['query'] ?? ''}'.trim();
    if (query.isEmpty) return _error(call, 'Give words to look for.');
    final everywhere = call.input['everywhere'] == true;
    final ids = await reader.searchPages(
      query,
      within: everywhere ? null : scope.link,
      limit: 6,
    );
    final terms = SearchTerms.parse(query);
    final sources = <Source>[];
    for (final id in ids) {
      final digest = await reader.digest(id);
      final entry = (await reader.pagesIn(NoteLink.page(id))).firstOrNull;
      if (digest == null) continue;
      sources.add(
        NoteContext.matchingSource(digest, terms, context: entry?.context),
      );
    }
    if (sources.isEmpty) {
      return ToolResultPart(
        callId: call.id,
        content: <ChatPart>[
          TextPart(
            'Nothing in ${everywhere ? 'the notes' : 'these notes'} '
            'contains “$query”.',
          ),
        ],
      );
    }
    return ToolResultPart(
      callId: call.id,
      content: <ChatPart>[SourcesPart(sources)],
    );
  }

  Future<ToolResultPart> _read(ToolCallPart call) async {
    final id = '${call.input['page_id'] ?? ''}'.trim();
    final digest = await reader.digest(id);
    if (digest == null) return _error(call, 'There is no page $id.');
    final entry = (await reader.pagesIn(NoteLink.page(id))).firstOrNull;
    return ToolResultPart(
      callId: call.id,
      content: <ChatPart>[
        SourcesPart(<Source>[
          NoteContext.pageSource(digest, context: entry?.context, limit: 60000),
        ]),
      ],
    );
  }

  Future<ToolResultPart> _look(ToolCallPart call) async {
    final id = '${call.input['page_id'] ?? ''}'.trim();
    final digest = await reader.digest(id);
    if (digest == null) return _error(call, 'There is no page $id.');
    final wanted = <String>[
      for (final v in (call.input['visuals'] as List?) ?? const []) '$v',
    ].take(4);
    final content = <ChatPart>[];
    for (final visualId in wanted) {
      final visual = digest.visual(visualId);
      final image = visual == null ? null : await reader.render(id, visual);
      content.add(
        image ?? TextPart('There is no visual $visualId on that page to show.'),
      );
    }
    return ToolResultPart(callId: call.id, content: content);
  }

  Future<ToolResultPart> _web(ToolCallPart call) async {
    final query = '${call.input['query'] ?? ''}'.trim();
    final sources = await webSearch!.search(query);
    return ToolResultPart(
      callId: call.id,
      content: sources.isEmpty
          ? <ChatPart>[TextPart('The web had nothing for “$query”.')]
          : <ChatPart>[SourcesPart(sources)],
    );
  }

  static ToolResultPart _error(ToolCallPart call, String message) =>
      ToolResultPart(
        callId: call.id,
        content: <ChatPart>[TextPart(message)],
        isError: true,
      );
}

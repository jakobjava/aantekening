/// Searching the web for models whose provider cannot.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'conversation.dart';
import 'provider.dart';

/// Where the web is searched from, for a provider with no search of its
/// own.
enum WebSearchBackend {
  /// None: such a model answers from the notes and what it knows.
  none,

  /// A SearXNG instance, which can run on this machine or a server the
  /// person trusts.
  searxng,

  /// Brave's search API, with a key.
  brave,
}

/// Searches the web, giving back what it found as sources to cite.
abstract interface class WebSearch {
  Future<List<Source>> search(String query, {int count = 6});
}

/// Web search through a SearXNG instance's JSON API.
class SearxngSearch implements WebSearch {
  SearxngSearch(this.baseUrl, {http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  @override
  Future<List<Source>> search(String query, {int count = 6}) async {
    final uri = Uri.parse(
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/search',
    ).replace(queryParameters: <String, String>{'q': query, 'format': 'json'});
    final body = await _fetchJson(
      _http,
      uri,
      const <String, String>{},
      'SearXNG',
    );
    return <Source>[
      for (final result
          in ((body['results'] as List<Object?>?) ?? const []).take(count))
        if (result case {'url': final String url, 'title': final String title})
          _webSource(url, title, result['content'] as String?),
    ];
  }
}

/// Web search through Brave's search API.
class BraveSearch implements WebSearch {
  BraveSearch(this.apiKey, {http.Client? client})
    : _http = client ?? http.Client();

  final String apiKey;
  final http.Client _http;

  @override
  Future<List<Source>> search(String query, {int count = 6}) async {
    final uri = Uri.https('api.search.brave.com', '/res/v1/web/search', {
      'q': query,
      'count': '$count',
    });
    final body = await _fetchJson(_http, uri, <String, String>{
      'accept': 'application/json',
      'x-subscription-token': apiKey,
    }, 'Brave Search');
    final web = (body['web'] as Map?)?.cast<String, Object?>();
    return <Source>[
      for (final result in (web?['results'] as List<Object?>?) ?? const [])
        if (result case {'url': final String url, 'title': final String title})
          _webSource(url, title, result['description'] as String?),
    ];
  }
}

Source _webSource(String url, String title, String? snippet) => Source(
  uri: url,
  title: title,
  origin: SourceOrigin.web,
  context: Uri.tryParse(url)?.host,
  passages: <SourcePassage>[
    SourcePassage(
      (snippet ?? title).replaceAll(RegExp('<[^>]+>'), '').trim(),
      uri: url,
    ),
  ],
);

Future<Map<String, Object?>> _fetchJson(
  http.Client client,
  Uri uri,
  Map<String, String> headers,
  String name,
) async {
  final http.Response response;
  try {
    response = await client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
  } on Object catch (error) {
    throw AiException('$name could not be reached.', cause: error);
  }
  if (response.statusCode != 200) {
    throw AiException('$name answered ${response.statusCode}.');
  }
  return (jsonDecode(response.body) as Map).cast<String, Object?>();
}

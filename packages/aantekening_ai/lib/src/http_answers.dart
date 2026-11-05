/// What every provider over HTTP does the same: sending a request whose
/// answer streams back, saying why it was refused, and reading the answer
/// through to its end.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider.dart';

/// Posts [body] to [uri] with [headers], for the answer streamed back — the
/// request broken off as soon as [stop] completes. Failing to send it, it
/// throws what [unreachable] makes of why; refused, why [name] refused it
/// ([refusal]).
Future<http.StreamedResponse> postForStream(
  http.Client client,
  Uri uri, {
  required String name,
  required Map<String, String> headers,
  required Map<String, Object?> body,
  required AiException Function(Object error) unreachable,
  Future<void>? stop,
}) async {
  final request = http.AbortableRequest('POST', uri, abortTrigger: stop)
    ..headers.addAll(headers)
    ..body = jsonEncode(body);
  final http.StreamedResponse response;
  try {
    response = await client.send(request);
  } on Object catch (error) {
    throw unreachable(error);
  }
  if (response.statusCode != 200) {
    throw refusal(
      name,
      response.statusCode,
      await response.stream.bytesToString(),
    );
  }
  return response;
}

/// Why [name] refused a request, with [status] and [body]: in its own
/// words where its body says them, `{"error": {"message": …}}` or
/// `{"error": "…"}`.
AiException refusal(String name, int status, String body) {
  String? message;
  try {
    final error = (jsonDecode(body) as Map)['error'];
    message = error is Map ? error['message'] as String? : error?.toString();
  } on Object {
    // The status says enough.
  }
  final said = message == null ? '' : ': $message';
  return switch (status) {
    401 || 403 => AiException(
      '$name refused the API key. Check it in the AI settings.',
      status: status,
    ),
    404 => AiException('$name does not have that model$said', status: status),
    429 => AiException(
      'Too many requests to $name just now. Try again in a moment.',
      retryable: true,
      status: status,
    ),
    // Anthropic's, when it is overloaded.
    529 => AiException(
      '$name is busy just now. Try again in a moment.',
      retryable: true,
      status: status,
    ),
    >= 500 => AiException(
      '$name had a problem$said',
      retryable: true,
      status: status,
    ),
    _ => AiException(
      '$name refused the request: ${message ?? status}',
      status: status,
    ),
  };
}

/// The answer [name] streams as [events], read through to its end: what
/// breaks it off on the way — the connection lost, or what came
/// unreadable — and its ending before [ended] says it came to its end, as
/// a stream cut off by something between does, are [brokenOff].
Stream<T> wholeAnswer<T>(
  String name,
  Stream<T> events, {
  required bool Function() ended,
}) async* {
  try {
    await for (final event in events) {
      yield event;
    }
  } on AiException {
    rethrow;
  } on Object catch (error) {
    throw brokenOff(name, error);
  }
  if (!ended()) throw brokenOff(name);
}

/// That the answer [name] was streaming broke off before its end — the
/// connection lost, or cut by something between, or what came unreadable
/// ([cause]) — which another try may get whole.
AiException brokenOff(String name, [Object? cause]) => AiException(
  'The answer from $name broke off part way. Try again.',
  retryable: true,
  cause: cause,
);

/// Server-sent events, as streaming model APIs send their answers.
library;

import 'dart:async';
import 'dart:convert';

import 'provider.dart';

/// One event: its name, if it has one, and its data.
typedef ServerEvent = ({String? event, String data});

/// The events in [bytes], as they arrive. An event the stream ends in the
/// middle of, its blank line never come, is not one: it is passed over.
Stream<ServerEvent> serverEvents(Stream<List<int>> bytes) async* {
  String? event;
  final data = StringBuffer();
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield (event: event, data: data.toString());
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        if (data.isNotEmpty) data.write('\n');
        data.write(value);
    }
  }
}

/// That the answer [name] was streaming broke off before its end — the
/// connection lost, or cut by something between, or what came unreadable
/// ([cause]) — which another try may get whole.
AiException brokenOff(String name, [Object? cause]) => AiException(
  'The answer from $name broke off part way. Try again.',
  retryable: true,
  cause: cause,
);

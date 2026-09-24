/// Server-sent events, as streaming model APIs send their answers.
library;

import 'dart:async';
import 'dart:convert';

/// One event: its name, if it has one, and its data.
typedef ServerEvent = ({String? event, String data});

/// The events in [bytes], as they arrive.
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
  if (data.isNotEmpty) yield (event: event, data: data.toString());
}

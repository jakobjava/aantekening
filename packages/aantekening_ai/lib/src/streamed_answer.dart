/// The text of an answer as a model streams it: reasoning told apart from
/// it, and the sources it cites read out of it.
library;

import 'citation_markers.dart';
import 'conversation.dart';
import 'provider.dart';

/// The answer a model writes, piece by piece, as events: reasoning written
/// into its start ([ThinkTags]) as [Reasoning], the numbers it cites by
/// read ([MarkerReader]), and the text kept whole, to be handed back.
class StreamedAnswer {
  StreamedAnswer(List<Source> sources) : _markers = MarkerReader(sources);

  final ThinkTags _tags = ThinkTags();
  final MarkerReader _markers;
  final StringBuffer _text = StringBuffer();

  /// The answer's text so far, without its reasoning.
  String get text => _text.toString();

  /// The events [piece] of the answer makes.
  Iterable<ChatEvent> add(String piece) => _read(_tags.add(piece));

  /// The events of what is held back, once the answer is all there.
  Iterable<ChatEvent> close() sync* {
    yield* _read(_tags.close());
    yield* _markers.close();
  }

  Iterable<ChatEvent> _read(List<ChatEvent> events) sync* {
    for (final event in events) {
      if (event is TextDelta) {
        _text.write(event.text);
        yield* _markers.add(event.text);
      } else {
        yield event;
      }
    }
  }
}

/// [text] of a model's reasoning without the tags some runtimes leave in
/// it.
String withoutThinkTags(String text) =>
    text.replaceAll(RegExp(r'</?think>\n?'), '');

/// Reads the reasoning some models write at the start of their answer,
/// between `<think>` and `</think>`, out of it as it streams: the reasoning
/// comes out as [Reasoning], the rest as [TextDelta].
///
/// A tag split across pieces is held back until it is whole.
class ThinkTags {
  static const String _open = '<think>';
  static const String _close = '</think>';

  _Where _where = _Where.start;
  String _held = '';

  /// What [piece] of the content holds, in order.
  List<ChatEvent> add(String piece) {
    _held += piece;
    switch (_where) {
      case _Where.start:
        final text = _held.trimLeft();
        if (text.startsWith(_open)) {
          _where = _Where.thinking;
          _held = text.substring(_open.length);
          return _thinking();
        }
        // Not yet enough of it to tell.
        if (_open.startsWith(text)) return const <ChatEvent>[];
        _where = _Where.answer;
        return _answer();
      case _Where.thinking:
        return _thinking();
      case _Where.after:
        _held = _held.trimLeft();
        if (_held.isEmpty) return const <ChatEvent>[];
        _where = _Where.answer;
        return _answer();
      case _Where.answer:
        return _answer();
    }
  }

  /// What is held back, once the content is all there.
  List<ChatEvent> close() {
    final held = _held;
    _held = '';
    if (held.isEmpty) return const <ChatEvent>[];
    return <ChatEvent>[
      if (_where == _Where.thinking) Reasoning(held) else TextDelta(held),
    ];
  }

  List<ChatEvent> _thinking() {
    final end = _held.indexOf(_close);
    if (end >= 0) {
      final thought = _held.substring(0, end);
      _held = _held.substring(end + _close.length);
      _where = _Where.after;
      return <ChatEvent>[
        if (thought.isNotEmpty) Reasoning(thought),
        ...add(''),
      ];
    }
    // Keep back what could be the start of the closing tag.
    var keep = _close.length - 1;
    while (keep > 0 && !_held.endsWith(_close.substring(0, keep))) {
      keep--;
    }
    final thought = _held.substring(0, _held.length - keep);
    _held = _held.substring(_held.length - keep);
    return <ChatEvent>[if (thought.isNotEmpty) Reasoning(thought)];
  }

  List<ChatEvent> _answer() {
    final text = _held;
    _held = '';
    return <ChatEvent>[if (text.isNotEmpty) TextDelta(text)];
  }
}

enum _Where {
  /// Nothing yet but, perhaps, the start of an opening tag.
  start,

  /// Between the tags.
  thinking,

  /// Past the closing tag, before the answer's first word.
  after,

  /// In the answer.
  answer,
}

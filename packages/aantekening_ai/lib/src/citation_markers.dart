/// Citations for models whose provider has none of its own: each passage
/// given is numbered, the model writes the numbers it draws on, and the
/// numbers are read back out of what it writes.
library;

import 'conversation.dart';
import 'provider.dart';

/// Writing sources out for a model to cite by number, and reading the
/// numbers back.
abstract final class CitationMarkers {
  /// How a model is told to cite, for the system prompt.
  static const String instructions =
      'Each source passage is numbered, like [3.2]: the second passage of '
      'source 3. Right after every sentence that draws on a source, write '
      'the numbers of the passages it draws on, like [3.2] or [3.2][5.1] — '
      'or [3] for a source as a whole. Never make up a number.';

  /// [sources] as text, the [first]th numbered [first]: each a tag round
  /// its passages, each after its number, a paragraph to a line.
  static String write(List<Source> sources, {required int first}) {
    final out = StringBuffer();
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final n = first + i;
      out.writeln(
        '<source n="$n" title="${_attribute(source.title)}" '
        'from="${source.origin == SourceOrigin.notes ? 'your notes' : 'the web'}"'
        '${source.context == null ? '' : ' where="${_attribute(source.context!)}"'}'
        ' link="${source.uri}">',
      );
      // The sentences of a paragraph on its line, each numbered.
      for (var j = 0; j < source.passages.length; j++) {
        final passage = source.passages[j];
        if (j > 0) out.write(passage.follows ? ' ' : '\n');
        out.write('[$n.${j + 1}] ${passage.text}');
      }
      out
        ..writeln()
        ..writeln('</source>');
    }
    return out.toString();
  }

  static String _attribute(String text) =>
      text.replaceAll('"', "'").replaceAll('\n', ' ');

  /// A citation group, `[3.2]` or `[3.2, 5.1]` or `[3]`.
  static final RegExp _marker = RegExp(
    r'\[(\d{1,4}(?:\.\d{1,4})?(?:\s*[,;]\s*\d{1,4}(?:\.\d{1,4})?)*)\]',
  );

  /// The start of what may be a citation group, at the end of text still
  /// arriving.
  static final RegExp _partial = RegExp(r'\[[\d.,; ]{0,24}$');

  /// The citation the number [ref] makes, or null for a number that names
  /// no source given.
  static Citation? resolve(String ref, List<Source> sources) {
    final parts = ref.trim().split('.');
    final n = int.tryParse(parts.first);
    if (n == null || n < 1 || n > sources.length) return null;
    final source = sources[n - 1];
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final passage = m != null && m >= 1 && m <= source.passages.length
        ? source.passages[m - 1]
        : null;
    return Citation(
      uri: passage?.uri ?? source.uri,
      title: source.title,
      origin: source.origin,
      quote: passage?.text,
    );
  }

  /// The citations of a group's text, `3.2, 5.1`, or null if any of them
  /// names no source given — then it is not a citation at all.
  static List<Citation>? resolveGroup(String group, List<Source> sources) {
    final citations = <Citation>[];
    for (final ref in group.split(RegExp('[,;]'))) {
      final citation = resolve(ref, sources);
      if (citation == null) return null;
      if (!citations.contains(citation)) citations.add(citation);
    }
    return citations;
  }
}

/// Reads citation markers out of an answer as it streams in, turning
/// `…fast [3.2]. Next…` into the text `…fast. Next…` and a [CitedSpan]
/// after `fast`. A marker split across two pieces is held back until it is
/// whole.
class MarkerReader {
  MarkerReader(this.sources);

  final List<Source> sources;
  String _held = '';

  /// The events [text], the next piece of the answer, makes.
  List<ChatEvent> add(String text) => _read(_held + text, flush: false);

  /// The events of what is still held back, at the end of the answer.
  List<ChatEvent> close() => _read(_held, flush: true);

  List<ChatEvent> _read(String text, {required bool flush}) {
    _held = '';
    final events = <ChatEvent>[];
    var from = 0;
    for (final match in CitationMarkers._marker.allMatches(text)) {
      final citations = CitationMarkers.resolveGroup(match.group(1)!, sources);
      if (citations == null) continue;
      // A space written before the marker goes with it.
      var end = match.start;
      while (end > from && text[end - 1] == ' ') {
        end--;
      }
      if (end > from) events.add(TextDelta(text.substring(from, end)));
      events.add(CitedSpan(citations));
      from = match.end;
    }
    var rest = text.substring(from);
    if (!flush) {
      final partial = CitationMarkers._partial.firstMatch(rest);
      if (partial != null) {
        // The spaces before it are held back too, to go with the marker.
        var start = partial.start;
        while (start > 0 && rest[start - 1] == ' ') {
          start--;
        }
        _held = rest.substring(start);
        rest = rest.substring(0, start);
      }
    }
    if (rest.isNotEmpty) events.add(TextDelta(rest));
    return events;
  }
}

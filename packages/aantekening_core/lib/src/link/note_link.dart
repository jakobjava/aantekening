/// Links to notes: to a notebook, a section, a page, or a place on a page.
library;

/// What a [NoteLink] points at.
enum NoteLinkKind { notebook, section, page }

/// A link to something in the workspace, written as a URI so it can sit
/// wherever a web address can — in a text run's link, in an AI answer's
/// citations, on the clipboard:
///
/// * `aantekening://notebook/<id>`
/// * `aantekening://section/<id>`
/// * `aantekening://page/<id>`, and on a page `#element=<id>`, and in a text
///   box `&block=<n>` for its [block]th paragraph, and in that paragraph
///   `&from=<i>&to=<j>` for the words between — a sentence, say.
///
/// Identifiers are the workspace's own, so a link keeps pointing at the same
/// thing however it is renamed or moved.
class NoteLink {
  const NoteLink(
    this.kind,
    this.id, {
    this.elementId,
    this.block,
    this.from,
    this.to,
  }) : assert(
         kind == NoteLinkKind.page || (elementId == null && block == null),
         'only a page has places on it',
       );

  const NoteLink.notebook(this.id)
    : kind = NoteLinkKind.notebook,
      elementId = null,
      block = null,
      from = null,
      to = null;

  const NoteLink.section(this.id)
    : kind = NoteLinkKind.section,
      elementId = null,
      block = null,
      from = null,
      to = null;

  const NoteLink.page(this.id, {this.elementId, this.block, this.from, this.to})
    : kind = NoteLinkKind.page;

  static const String scheme = 'aantekening';

  final NoteLinkKind kind;
  final String id;

  /// The element on the page, if the link points at one.
  final String? elementId;

  /// The paragraph of a text box, counted from zero, if the link points at
  /// one.
  final int? block;

  /// Where in the paragraph the words pointed at start and end, as offsets
  /// into its text, if the link points at words rather than the paragraph.
  final int? from;
  final int? to;

  /// The words pointed at, as a range of the paragraph's text, if any.
  ({int from, int to})? get words =>
      from != null && to != null && to! > from! ? (from: from!, to: to!) : null;

  /// This link, pointing at the words from [from] to [to] of its paragraph.
  NoteLink toWords(int from, int to) => NoteLink(
    kind,
    id,
    elementId: elementId,
    block: block,
    from: from,
    to: to,
  );

  /// The page itself, or the item itself, without the place on it.
  NoteLink get whole => NoteLink(kind, id);

  /// The link read from [uri], or null for anything that is not a link to a
  /// note.
  static NoteLink? tryParse(String uri) {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null || parsed.scheme != scheme) return null;
    final kind = NoteLinkKind.values.asNameMap()[parsed.host];
    final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
    if (kind == null || segments.length != 1) return null;
    if (kind != NoteLinkKind.page) return NoteLink(kind, segments.single);
    final place = Uri.splitQueryString(parsed.fragment);
    return NoteLink.page(
      segments.single,
      elementId: place['element'],
      block: int.tryParse(place['block'] ?? ''),
      from: int.tryParse(place['from'] ?? ''),
      to: int.tryParse(place['to'] ?? ''),
    );
  }

  /// Whether [uri] is a link to a note.
  static bool isNoteLink(String uri) => tryParse(uri) != null;

  @override
  String toString() {
    final place = <String>[
      if (elementId != null) 'element=${Uri.encodeComponent(elementId!)}',
      if (block != null) 'block=$block',
      if (from != null) 'from=$from',
      if (to != null) 'to=$to',
    ];
    return '$scheme://${kind.name}/${Uri.encodeComponent(id)}'
        '${place.isEmpty ? '' : '#${place.join('&')}'}';
  }

  @override
  bool operator ==(Object other) =>
      other is NoteLink &&
      other.kind == kind &&
      other.id == id &&
      other.elementId == elementId &&
      other.block == block &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, id, elementId, block, from, to);
}

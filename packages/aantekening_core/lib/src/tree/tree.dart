/// The organisational hierarchy: notebooks, nested sections and pages.
library;

import '../util/json_read.dart';
import 'hierarchy.dart';

/// Shared fields for every node in the organisational tree.
///
/// Deletion is soft: [deletedAt] moves a node to the recycle bin. What is in
/// a deleted notebook is hidden with it, untouched; the subsections of a
/// deleted section and the subpages of a deleted page are marked deleted at
/// the same time, so that they are restored with it.
abstract class TreeNode {
  const TreeNode({
    required this.id,
    required this.title,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.deletedAt,
  });

  final String id;
  final String title;

  /// Sort key among siblings; see `FractionalIndex`.
  final double position;

  final int createdAt;
  final int updatedAt;

  /// Accent colour as 32-bit ARGB, or null to use the theme default.
  final int? color;

  /// When the node was moved to the recycle bin, or null while it is live.
  final int? deletedAt;

  bool get isDeleted => deletedAt != null;
}

/// A top-level notebook.
class Notebook extends TreeNode {
  const Notebook({
    required super.id,
    required super.title,
    required super.position,
    required super.createdAt,
    required super.updatedAt,
    super.color,
    super.deletedAt,
    this.icon,
  });

  /// Name of an icon in the app's icon set.
  final String? icon;

  Notebook copyWith({
    String? title,
    double? position,
    int? updatedAt,
    int? color,
    int? deletedAt,
    String? icon,
    bool clearDeletedAt = false,
  }) => Notebook(
    id: id,
    title: title ?? this.title,
    position: position ?? this.position,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    color: color ?? this.color,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    icon: icon ?? this.icon,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'position': position,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (color != null) 'color': color,
    if (deletedAt != null) 'deletedAt': deletedAt,
    if (icon != null) 'icon': icon,
  };

  static Notebook fromJson(Map<String, Object?> json) => Notebook(
    id: readString(json, 'id'),
    title: readString(json, 'title'),
    position: readDouble(json, 'position'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    color: readIntOrNull(json, 'color'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    icon: readStringOrNull(json, 'icon'),
  );
}

/// A section within a notebook.
///
/// Sections nest through [parentId], which is what makes subsections — and
/// sub-subsections — a single recursive table rather than one table per depth.
class Section extends TreeNode {
  const Section({
    required super.id,
    required this.notebookId,
    required super.title,
    required super.position,
    required super.createdAt,
    required super.updatedAt,
    this.parentId,
    super.color,
    super.deletedAt,
  });

  final String notebookId;

  /// The enclosing section, or null for a section directly under the notebook.
  final String? parentId;

  /// [sections], of one notebook, in their tree.
  static Hierarchy<Section> hierarchy(Iterable<Section> sections) =>
      Hierarchy<Section>.of(
        sections,
        idOf: (section) => section.id,
        parentOf: (section) => section.parentId,
      );

  Section copyWith({
    String? title,
    double? position,
    int? updatedAt,
    int? color,
    int? deletedAt,
    String? parentId,
    String? notebookId,
    bool clearParentId = false,
    bool clearDeletedAt = false,
  }) => Section(
    id: id,
    notebookId: notebookId ?? this.notebookId,
    title: title ?? this.title,
    position: position ?? this.position,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    parentId: clearParentId ? null : (parentId ?? this.parentId),
    color: color ?? this.color,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'notebookId': notebookId,
    'title': title,
    'position': position,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (parentId != null) 'parentId': parentId,
    if (color != null) 'color': color,
    if (deletedAt != null) 'deletedAt': deletedAt,
  };

  static Section fromJson(Map<String, Object?> json) => Section(
    id: readString(json, 'id'),
    notebookId: readString(json, 'notebookId'),
    title: readString(json, 'title'),
    position: readDouble(json, 'position'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    parentId: readStringOrNull(json, 'parentId'),
    color: readIntOrNull(json, 'color'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
  );
}

/// A page's metadata, without its contents.
///
/// Navigation, search results and the page list all work from this record
/// alone; the much larger [PageDocument] body is loaded only when a page is
/// actually opened.
class PageRef extends TreeNode {
  const PageRef({
    required super.id,
    required this.sectionId,
    required super.title,
    required super.position,
    required super.createdAt,
    required super.updatedAt,
    this.parentId,
    this.preview = '',
    this.revision = 0,
    super.color,
    super.deletedAt,
  });

  final String sectionId;

  /// The parent page, for OneNote-style subpages, or null for a top-level page.
  final String? parentId;

  /// [pages], of one section, in their tree of subpages.
  static Hierarchy<PageRef> hierarchy(Iterable<PageRef> pages) =>
      Hierarchy<PageRef>.of(
        pages,
        idOf: (page) => page.id,
        parentOf: (page) => page.parentId,
      );

  /// First line or so of the page's text, shown in the page list.
  final String preview;

  /// Mirrors `PageDocument.revision`, so the list can detect stale entries
  /// without loading the body.
  final int revision;

  PageRef copyWith({
    String? sectionId,
    String? title,
    double? position,
    int? updatedAt,
    String? parentId,
    String? preview,
    int? revision,
    int? color,
    int? deletedAt,
    bool clearParentId = false,
    bool clearDeletedAt = false,
  }) => PageRef(
    id: id,
    sectionId: sectionId ?? this.sectionId,
    title: title ?? this.title,
    position: position ?? this.position,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    parentId: clearParentId ? null : (parentId ?? this.parentId),
    preview: preview ?? this.preview,
    revision: revision ?? this.revision,
    color: color ?? this.color,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sectionId': sectionId,
    'title': title,
    'position': position,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (parentId != null) 'parentId': parentId,
    if (preview.isNotEmpty) 'preview': preview,
    'revision': revision,
    if (color != null) 'color': color,
    if (deletedAt != null) 'deletedAt': deletedAt,
  };

  static PageRef fromJson(Map<String, Object?> json) => PageRef(
    id: readString(json, 'id'),
    sectionId: readString(json, 'sectionId'),
    title: readString(json, 'title'),
    position: readDouble(json, 'position'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    parentId: readStringOrNull(json, 'parentId'),
    preview: readString(json, 'preview'),
    revision: readInt(json, 'revision'),
    color: readIntOrNull(json, 'color'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
  );
}

/// A binary attachment: an imported image, a PDF, or a rendered thumbnail.
///
/// Assets are content-addressed by [sha256], so importing the same PDF into ten
/// pages stores one copy.
class AssetRef {
  const AssetRef({
    required this.id,
    required this.sha256,
    required this.mimeType,
    required this.byteSize,
    required this.createdAt,
    this.originalName,
  });

  final String id;
  final String sha256;
  final String mimeType;
  final int byteSize;
  final int createdAt;

  /// The file name the asset was imported under, shown in the UI.
  final String? originalName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sha256': sha256,
    'mimeType': mimeType,
    'byteSize': byteSize,
    'createdAt': createdAt,
    if (originalName != null) 'originalName': originalName,
  };

  static AssetRef fromJson(Map<String, Object?> json) => AssetRef(
    id: readString(json, 'id'),
    sha256: readString(json, 'sha256'),
    mimeType: readString(json, 'mimeType'),
    byteSize: readInt(json, 'byteSize'),
    createdAt: readInt(json, 'createdAt'),
    originalName: readStringOrNull(json, 'originalName'),
  );
}

/// One hit from a search query.
class SearchHit {
  const SearchHit({
    required this.pageId,
    required this.title,
    required this.snippet,
    required this.score,
    this.notebookId,
    this.sectionId,
  });

  final String pageId;
  final String title;

  /// A fragment of the matching text with the matched terms marked up.
  final String snippet;

  /// Relevance, higher is better.
  final double score;

  final String? notebookId;
  final String? sectionId;
}

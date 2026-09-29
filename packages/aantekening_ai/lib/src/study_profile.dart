/// What the AI is asked to make to study from: the app's own summary,
/// flashcards, quiz and key terms, as they come or as the person changed
/// them, and profiles the person made themselves.
library;

import 'study.dart';

/// A kind of study set to make, as the person wants it: what it is called,
/// the form it takes, what it should be, and anything they add.
class StudyProfile {
  const StudyProfile({
    required this.id,
    required this.name,
    required this.form,
    required this.idea,
    this.details = '',
  });

  /// The app's own profile for [form], as it comes.
  StudyProfile.original(StudyKind form)
    : this(id: form.name, name: form.label, form: form, idea: form.idea);

  /// The app's own profiles, one for each kind of set but free text, which
  /// only the person's own profiles take.
  static final List<StudyProfile> originals = <StudyProfile>[
    for (final kind in StudyKind.values)
      if (kind.structured) StudyProfile.original(kind),
  ];

  /// What the sets it made are kept by: for the app's own, the name of
  /// their kind.
  final String id;
  final String name;
  final StudyKind form;

  /// What to make, in the person's words.
  final String idea;

  /// Anything they add: who they are, the language, how many, how hard.
  final String details;

  /// Whether it is one of the app's own, whose [form] stays as it is.
  bool get isOriginal => id == form.name && form.structured;

  /// Whether it is one of the app's own, unchanged.
  bool get isAsMade =>
      isOriginal && name == form.label && idea == form.idea && details.isEmpty;

  /// What it is for, in a sentence or two: the app's own say; the
  /// person's own are what they described.
  String get purpose => isOriginal || idea.trim().isEmpty ? form.purpose : idea;

  /// What it is called in a sentence: "the summary", or its name quoted.
  String get called => isOriginal && name == form.label
      ? 'the ${name.toLowerCase()}'
      : '“$name”';

  /// What the model is asked to make of the notes of a [scope] — "page",
  /// "section", "notebook": the idea, the form to write it in, and what
  /// the person adds, which goes before the rest where they differ.
  String instructions(String scope) {
    final idea = this.idea.trim();
    final details = this.details.trim();
    return <String>[
      if (idea.isEmpty) form.idea else idea,
      form.form(scope),
      if (details.isNotEmpty)
        'What the student asks for besides — where it differs from what is '
            'asked above, do as they ask, in the form asked for:\n$details',
    ].join('\n\n');
  }

  StudyProfile copyWith({
    String? name,
    StudyKind? form,
    String? idea,
    String? details,
  }) => StudyProfile(
    id: id,
    name: name ?? this.name,
    form: isOriginal ? this.form : form ?? this.form,
    idea: idea ?? this.idea,
    details: details ?? this.details,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'form': form.name,
    'idea': idea,
    if (details.isNotEmpty) 'details': details,
  };

  /// The profile kept as [json], or null if it is not one. One of the
  /// app's own keeps its form, whatever [json] says.
  static StudyProfile? fromJson(Map<String, Object?> json) {
    final kinds = StudyKind.values.asNameMap();
    final id = json['id'];
    final form = kinds[id] ?? kinds[json['form']];
    if (id is! String || id.isEmpty || form == null) return null;
    return StudyProfile(
      id: id,
      name: json['name'] as String? ?? form.label,
      form: form,
      idea: json['idea'] as String? ?? form.idea,
      details: json['details'] as String? ?? '',
    );
  }
}

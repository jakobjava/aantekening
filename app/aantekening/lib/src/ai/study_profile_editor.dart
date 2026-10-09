/// Changing what a study profile asks the AI to make, or making a new one.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/controls.dart';
import '../look/glass.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import 'ai_state.dart';

/// Opens the editor of [profile], or of a new profile of the person's own,
/// over [context]; what is saved goes into the AI settings.
Future<void> editStudyProfile(BuildContext context, {StudyProfile? profile}) =>
    showAppDialog<void>(
      context: context,
      builder: (context) => StudyProfileEditor(profile: profile),
    );

/// A study profile's name, the form its set takes, what it should be, and
/// anything the person adds.
class StudyProfileEditor extends ConsumerStatefulWidget {
  const StudyProfileEditor({this.profile, super.key});

  /// The profile changed, or null for a new one.
  final StudyProfile? profile;

  @override
  ConsumerState<StudyProfileEditor> createState() => _StudyProfileEditorState();
}

class _StudyProfileEditorState extends ConsumerState<StudyProfileEditor> {
  /// What the profile is kept by: a new one's made up once.
  late final String _id = widget.profile?.id ?? Ulid.generate();
  late final TextEditingController _name = TextEditingController(
    text: widget.profile?.name ?? '',
  );
  late final TextEditingController _idea = TextEditingController(
    text: widget.profile?.idea ?? '',
  );
  late final TextEditingController _details = TextEditingController(
    text: widget.profile?.details ?? '',
  );
  late StudyKind _form = widget.profile?.form ?? StudyKind.text;

  @override
  void initState() {
    super.initState();
    // Saving waits for a name, and for a new profile what to make.
    for (final field in <TextEditingController>[_name, _idea]) {
      field.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _idea.dispose();
    _details.dispose();
    super.dispose();
  }

  bool get _original => widget.profile?.isOriginal ?? false;

  /// The profile as it stands, or null while it lacks what it needs.
  StudyProfile? get _edited {
    final name = _name.text.trim();
    final idea = _idea.text.trim();
    if (name.isEmpty || (idea.isEmpty && !_original)) return null;
    return StudyProfile(
      id: _id,
      name: name,
      form: _form,
      // Emptied, one of the app's own asks what it did at first.
      idea: idea.isEmpty ? _form.idea : idea,
      details: _details.text.trim(),
    );
  }

  void _settle(AiSettings Function(AiSettings settings) change) {
    final controller = ref.read(aiSettingsProvider.notifier);
    controller.update(change(ref.read(aiSettingsProvider)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final profile = widget.profile;
    final about = ref.watch(aiSettingsProvider.select((s) => s.about)).trim();
    final note = TextStyle(fontSize: 12, height: 1.4, color: tones.muted);
    return GlassDialog(
      title: Text(profile == null ? 'New study profile' : 'Edit the profile'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: profile == null,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Abitur tasks',
                ),
              ),
              const SizedBox(height: 16),
              SmallCaps('Makes', color: tones.muted),
              const SizedBox(height: 6),
              if (_original)
                Text(_form.label)
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ChoiceRow<StudyKind>(
                    choices: StudyKind.values,
                    selected: _form,
                    labelOf: (form) => form.label,
                    onSelected: (form) => setState(() => _form = form),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                _original
                    ? '${_form.purpose} The app’s own profiles keep their '
                          'form.'
                    : _form.purpose,
                style: TextStyle(fontSize: 12, color: tones.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _idea,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'What to make',
                  alignLabelWithHint: true,
                  hintText: _original
                      ? _form.idea
                      : 'Tasks as the Abitur sets them on these notes, each '
                            'with a worked solution.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _details,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Anything else',
                  alignLabelWithHint: true,
                  hintText:
                      'Write in German. Twelve questions, the last ones as '
                      'hard as in the Abitur.',
                  helperText:
                      'Who it is for, the language, how many, how hard. '
                      'Where it differs from the rest, it is done as said '
                      'here.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                about.isEmpty
                    ? 'What you say about yourself in the AI settings goes '
                          'with every profile and question.'
                    : 'Goes with what you say about yourself in the AI '
                          'settings: “$about”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: note,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (profile != null && !profile.isOriginal)
          TextButton(
            onPressed: () => _settle((s) => s.withoutProfile(profile.id)),
            child: const Text('Delete'),
          )
        else if (profile != null && !profile.isAsMade)
          TextButton(
            onPressed: () => _settle((s) => s.withoutProfile(profile.id)),
            child: const Text('Reset to the original'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _edited == null
              ? null
              : () => _settle((s) => s.withProfile(_edited!)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

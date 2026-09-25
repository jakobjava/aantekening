/// A notebook's, section's or page's AI: asking about it, and what was
/// kept of the answers.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../links/note_links.dart';
import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import '../settings/settings_view.dart';
import 'ai_session.dart';
import 'ai_state.dart';
import 'answer_progress.dart';
import 'answer_view.dart';
import 'study_pages.dart';

/// The AI of [scope], in place of the page: what was kept about it and its
/// conversations down the side, the conversation showing, and a line at the
/// foot to ask in.
///
/// Everything here is the AI's, drawn apart from the notes — never on the
/// page, never in its text — and each answer shows where each part of it
/// comes from.
class AiView extends ConsumerWidget {
  const AiView({required this.scope, super.key});

  final NoteLink scope;

  /// How wide the window is at least for the list down the side to show.
  static const double railFrom = 760;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    return Material(
      color: tones.base,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rail = constraints.maxWidth >= railFrom;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (rail) ...<Widget>[
                SizedBox(
                  width: 236,
                  child: ColoredBox(
                    color: tones.pane,
                    child: _Rail(scope: scope),
                  ),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: _Main(scope: scope, backToOverview: !rail),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------- rail

/// The way round the scope's AI: its overview, each kind of set to study,
/// its conversations, and the answers kept.
class _Rail extends ConsumerWidget {
  const _Rail({required this.scope});

  final NoteLink scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final state = ref.watch(aiSessionProvider(scope));
    final session = ref.read(aiSessionProvider(scope).notifier);

    Widget heading(String label, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 4, 2),
      child: SizedBox(
        height: 24,
        child: Row(
          children: <Widget>[
            Expanded(child: SmallCaps(label)),
            ?action,
          ],
        ),
      ),
    );

    Widget entry({
      required String title,
      required bool selected,
      required VoidCallback? onTap,
      Widget? trailing,
      List<Widget> menu = const <Widget>[],
    }) => RowTile(
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(12, 6, menu.isEmpty ? 12 : 2, 6),
      title: Text(title),
      trailing: trailing == null && menu.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ?trailing,
                if (menu.isNotEmpty)
                  MenuAnchor(
                    menuChildren: menu,
                    builder: (context, controller, _) => MarkButton(
                      MarkShape.more,
                      tooltip: 'More',
                      size: 22,
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
              ],
            ),
    );

    Widget count(String text, {bool strong = false}) => Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: strong ? FontWeight.w700 : null,
        color: strong ? tones.emphasis : tones.muted,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      children: <Widget>[
        entry(
          title: 'Overview',
          selected: state.atOverview,
          onTap: session.newThread,
        ),
        heading('Study'),
        for (final kind in StudyKind.values)
          Builder(
            builder: (context) {
              final item = state.setOf(kind);
              final set = item == null ? null : StudySet.fromJson(item.body);
              final due = cardsToStudy(ref, item);
              return entry(
                title: kind.label,
                selected:
                    state.shownKind == kind ||
                    (item != null && state.itemId == item.id),
                onTap: () => session.openKind(kind),
                trailing: state.making.containsKey(kind)
                    ? const Busy()
                    : due > 0
                    ? count('$due', strong: true)
                    : switch (set) {
                        null => count('—'),
                        StudySummary() => Mark(
                          MarkShape.check,
                          color: tones.muted,
                        ),
                        _ => count('${set.size}'),
                      },
              );
            },
          ),
        heading(
          'Conversations',
          action: MarkButton(
            MarkShape.add,
            tooltip: 'Ask something new',
            size: 22,
            onPressed: session.newThread,
          ),
        ),
        if (state.threads.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Text(
              'Ask below — each question starts one.',
              style: TextStyle(fontSize: 12, color: tones.muted),
            ),
          ),
        for (final thread in state.threads)
          entry(
            title: thread.title.isEmpty ? 'Conversation' : thread.title,
            selected: state.itemId == null && state.threadId == thread.id,
            onTap: () => unawaited(session.openThread(thread.id)),
            menu: <Widget>[
              MenuItemButton(
                onPressed: () => session.deleteThread(thread.id),
                child: const Text('Delete'),
              ),
            ],
          ),
        if (state.savedAnswers.isNotEmpty) ...<Widget>[
          heading('Kept answers'),
          for (final item in state.savedAnswers)
            entry(
              title: item.title,
              selected: state.itemId == item.id,
              onTap: () => session.openItem(item.id),
              menu: <Widget>[
                MenuItemButton(
                  onPressed: () async {
                    final title = await _askName(context, item.title);
                    if (title != null) await session.renameItem(item.id, title);
                  },
                  child: const Text('Rename'),
                ),
                MenuItemButton(
                  onPressed: () => session.deleteItem(item.id),
                  child: const Text('Delete'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

Future<String?> _askName(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

// -------------------------------------------------------------------- main

class _Main extends ConsumerStatefulWidget {
  const _Main({required this.scope, required this.backToOverview});

  final NoteLink scope;

  /// Whether to offer a way back to the overview, where the list down the
  /// side, which has one, is not shown.
  final bool backToOverview;

  @override
  ConsumerState<_Main> createState() => _MainState();
}

class _MainState extends ConsumerState<_Main> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest of the answer in view as it arrives, unless the
  /// person has scrolled up to read.
  void _follow() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _open(Citation citation) =>
      unawaited(ref.read(noteLinksProvider).open(citation.uri, newTab: true));

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final state = ref.watch(aiSessionProvider(scope));
    final model = ref.watch(aiModelProvider);
    ref.listen(aiSessionProvider(scope), (_, _) => _follow());

    final item = state.item;
    final shownKind = state.shownKind;
    final set = item == null ? null : StudySet.fromJson(item.body);
    final Widget page;
    if (!state.loaded || model.isLoading) {
      page = const Loading();
    } else if (item != null && set != null) {
      page = StudySetPage(scope: scope, item: item, set: set, onOpen: _open);
    } else if (item != null) {
      page = _ItemReader(scope: scope, item: item, onOpen: _open);
    } else if (shownKind != null) {
      page = switch (state.making[shownKind]) {
        final making? => StudyDraftPage(
          scope: scope,
          pending: making,
          onOpen: _open,
        ),
        null => StudyKindPage(scope: scope, kind: shownKind),
      };
    } else if (model.value == null) {
      page = const _ChooseModel();
    } else if (state.atOverview) {
      page = StudyOverview(scope: scope);
    } else {
      page = _Conversation(
        scope: scope,
        state: state,
        scroll: _scroll,
        onOpen: _open,
      );
    }
    return Column(
      children: <Widget>[
        if (widget.backToOverview && !state.atOverview)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: TextButton(
                onPressed: ref
                    .read(aiSessionProvider(scope).notifier)
                    .newThread,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Mark(MarkShape.arrowLeft),
                    SizedBox(width: 8),
                    Text('Overview'),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: page),
        if (state.error != null) _ErrorLine(message: state.error!),
        _Composer(scope: scope),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: tones.text, width: 2)),
          color: tones.hover,
        ),
        child: Text(message, style: TextStyle(color: tones.text)),
      ),
    );
  }
}

/// Before a model is chosen: what the AI does, and where to choose one.
class _ChooseModel extends StatelessWidget {
  const _ChooseModel();

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Ask about your notes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a model to answer: one running on this computer, where '
                'your notes stay, or a provider you trust. Answers come from '
                'your notes first and say where each part comes from.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tones.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => showSettings(context, page: SettingsPage.ai),
                child: const Text('Choose a model'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The questions of a conversation and their answers, and the one being
/// answered.
class _Conversation extends ConsumerWidget {
  const _Conversation({
    required this.scope,
    required this.state,
    required this.scroll,
    required this.onOpen,
  });

  final NoteLink scope;
  final AiSessionState state;
  final ScrollController scroll;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(aiSessionProvider(scope).notifier);
    final pending = state.pending;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
      children: <Widget>[
        for (final turn in state.turns)
          _Exchange(
            question: turn.question,
            answer: AiAnswer.fromJson(turn.answer),
            byline: <String>[
              turn.provider,
              turn.model,
              if (AiSession.tookOf(turn) case final took?) wholeSeconds(took),
            ].join(' · '),
            onOpen: onOpen,
            kept: session.isKept(turn),
            onKeep: () => unawaited(session.keep(turn)),
            onAddCards: (cards) => unawaited(session.addCards(cards)),
          ),
        if (pending != null)
          _Exchange(
            question: pending.question,
            answer: pending.answer,
            pending: pending,
            onOpen: onOpen,
          ),
      ],
    );
  }
}

/// A question, and its answer beneath it.
class _Exchange extends StatelessWidget {
  const _Exchange({
    required this.question,
    required this.answer,
    required this.onOpen,
    this.byline,
    this.pending,
    this.kept = false,
    this.onKeep,
    this.onAddCards,
  });

  final String question;
  final AiAnswer answer;
  final void Function(Citation citation) onOpen;

  /// Who answered.
  final String? byline;

  /// How the answer is coming along, while it comes.
  final PendingTurn? pending;
  final bool kept;
  final VoidCallback? onKeep;
  final ValueChanged<List<StudyCard>>? onAddCards;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final done = byline != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The question, set off to the right in a shade of its own.
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  color: tones.hover,
                  child: SelectableText(question),
                ),
              ),
              const SizedBox(height: 14),
              SmallCaps('Answer', color: tones.emphasis),
              const SizedBox(height: 6),
              if (pending != null) AnswerProgress(pending: pending!),
              if (!answer.isEmpty)
                AnswerView(
                  answer: answer,
                  onOpen: onOpen,
                  showSources: done,
                  onAddCards: onAddCards,
                ),
              if (done)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          byline!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: tones.muted),
                        ),
                      ),
                      SmallButton(
                        'Copy',
                        tooltip: 'Copy the answer',
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: answer.plainText),
                        ),
                      ),
                      SmallButton(
                        kept ? 'Kept' : 'Keep',
                        tooltip: kept
                            ? 'Kept, under Kept answers'
                            : 'Keep the answer, under Kept answers',
                        onPressed: kept ? null : onKeep,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Something kept, read again: its answer, and what it came from.
class _ItemReader extends ConsumerWidget {
  const _ItemReader({
    required this.scope,
    required this.item,
    required this.onOpen,
  });

  final NoteLink scope;
  final AiItem item;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final session = ref.read(aiSessionProvider(scope).notifier);
    final answer = AiAnswer.fromJson(item.body);
    final made = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SmallCaps('Kept answer'),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SmallButton(
                    'Rename',
                    onPressed: () async {
                      final title = await _askName(context, item.title);
                      if (title != null) {
                        await session.renameItem(item.id, title);
                      }
                    },
                  ),
                  MarkButton(
                    MarkShape.close,
                    tooltip: 'Back to the overview',
                    onPressed: session.newThread,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 14),
                child: Text(
                  'Made by ${item.provider} · ${item.model}, '
                  '${made.year}-${made.month.toString().padLeft(2, '0')}-${made.day.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: tones.muted),
                ),
              ),
              AnswerView(answer: answer, onOpen: onOpen),
            ],
          ),
        ),
      ),
    );
  }
}

/// The line to ask in: what is asked is about the scope, and may search the
/// web where that is set up.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.scope});

  final NoteLink scope;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final TextEditingController _text = TextEditingController();
  // Its edge is marked while it has the keyboard.
  late final FocusNode _focus = FocusNode()..addListener(() => setState(() {}));
  bool? _web;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _webAvailable(AiModel? model, AsyncValue<WebSearch?> search) =>
      model != null &&
      (model.config.kind == ProviderKind.anthropic || search.value != null);

  void _send() {
    final question = _text.text.trim();
    if (question.isEmpty) return;
    final settings = ref.read(aiSettingsProvider);
    final model = ref.read(aiModelProvider).value;
    final web =
        (_web ?? settings.searchWeb) &&
        _webAvailable(model, ref.read(webSearchProvider));
    _text.clear();
    unawaited(
      ref
          .read(aiSessionProvider(widget.scope).notifier)
          .ask(question, searchWeb: web),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final pending = ref.watch(
      aiSessionProvider(widget.scope).select((s) => s.pending),
    );
    final info = ref.watch(aiScopeInfoProvider(widget.scope)).value;
    final model = ref.watch(aiModelProvider).value;
    final search = ref.watch(webSearchProvider);
    final available = _webAvailable(model, search);
    final web =
        (_web ?? ref.watch(aiSettingsProvider.select((s) => s.searchWeb))) &&
        available;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tones.base,
              border: Border.all(
                color: _focus.hasFocus ? tones.emphasis : tones.strongLine,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 6, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.enter): _send,
                    },
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 8,
                      enabled: model != null,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        hintText: model == null
                            ? 'Choose a model to ask'
                            : 'Ask about ${info == null ? 'this' : '“${info.title}”'}…',
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Tooltip(
                        message: available
                            ? 'Let this answer search the web. What it finds '
                                  'is cited as the web.'
                            : 'Set up web search in the AI settings',
                        child: _WebToggle(
                          on: web,
                          onChanged: available
                              ? (on) => setState(() => _web = on)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const _ModelButton(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          info == null
                              ? ''
                              : 'Starts from this ${info.kindName}, then all '
                                    'your notes',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: tones.muted),
                        ),
                      ),
                      if (pending != null)
                        Tooltip(
                          message: 'Stop',
                          child: OutlinedButton(
                            onPressed: () => unawaited(
                              ref
                                  .read(
                                    aiSessionProvider(widget.scope).notifier,
                                  )
                                  .stop(),
                            ),
                            child: const Text('Stop'),
                          ),
                        )
                      else
                        Tooltip(
                          message: 'Ask (Enter)',
                          child: FilledButton(
                            onPressed: model == null ? null : _send,
                            child: const Text('Ask'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether this question searches the web: a box to tick, and "Web".
class _WebToggle extends StatelessWidget {
  const _WebToggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final onChanged = this.onChanged;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged(!on),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Mark(
              on ? MarkShape.boxTicked : MarkShape.box,
              color: onChanged == null ? tones.faint : tones.text,
            ),
            const SizedBox(width: 6),
            Text(
              'Web',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: onChanged == null ? tones.faint : tones.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who answers, and where the notes go to be answered: opens the settings
/// to choose.
class _ModelButton extends ConsumerWidget {
  const _ModelButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(aiModelProvider).value;
    final local = model?.config.local ?? true;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: SmallButton(
        model == null
            ? 'Choose a model'
            : local
            ? model.config.model
            : '${model.config.model} · online',
        tooltip: model == null
            ? 'Choose which model answers'
            : local
            ? '${model.config.name}: answers come from a model on this computer'
            : 'Questions, and the notes they are about, go to '
                  '${model.config.name}',
        onPressed: () => showSettings(context, page: SettingsPage.ai),
      ),
    );
  }
}

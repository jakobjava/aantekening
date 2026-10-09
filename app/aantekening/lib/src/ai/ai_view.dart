/// A notebook's, section's or page's AI: a pane of glass over the notes,
/// to ask about them in and to study them by.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/focus_glide.dart';
import '../links/note_links.dart';
import '../look/chooser.dart';
import '../look/controls.dart';
import '../look/floating_pane.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../modes/editor_mode.dart';
import '../modes/key_guide.dart';
import '../modes/mode_keys.dart';
import '../settings/settings_view.dart';
import '../shell/tabs.dart';
import 'ai_session.dart';
import 'ai_state.dart';
import 'answer_progress.dart';
import 'answer_view.dart';
import 'money.dart';
import 'study_pages.dart';

/// The AI of [scope] floating over the notes, below what covers them
/// along [obscured]: a pane of glass down their right, the notes beside it
/// — or over all of them, where they are narrow. It settles in as it is
/// called up.
class AiPane extends StatefulWidget {
  const AiPane({
    required this.scope,
    this.obscured = EdgeInsets.zero,
    super.key,
  });

  final NoteLink scope;
  final EdgeInsets obscured;

  /// How wide the notes are at least for the AI to float beside them,
  /// rather than over them all.
  static const double besideFrom = 720;

  /// How far it floats from the edges of the notes.
  static const double margin = 8;

  @override
  State<AiPane> createState() => _AiPaneState();
}

class _AiPaneState extends State<AiPane> with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: Motion.settle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown.duration = context.motion.of(Motion.settle);
    if (_shown.value == 0 && !_shown.isAnimating) unawaited(_shown.forward());
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const margin = AiPane.margin;
    final obscured = widget.obscured;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        obscured.top + margin,
        margin,
        obscured.bottom + margin,
      ),
      child: FloatingPane(
        pane: Pane.ai,
        // Down the right of the notes, as tall as they are.
        natural: (area) => BoxConstraints.tight(
          Size(
            area.width >= AiPane.besideFrom - 2 * margin
                ? (area.width * 0.42).clamp(420.0, 580.0)
                : area.width,
            area.height,
          ),
        ),
        position: (area, size) => Offset(area.width - size.width, 0),
        minSize: const Size(320, 240),
        child: FloatingIn(
          animation: _shown,
          alignment: Alignment.centerRight,
          // A click on it is its own, not the notes' beneath.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: Glass(child: AiView(scope: widget.scope)),
          ),
        ),
      ),
    );
  }
}

/// What the AI pane holds: whose AI it is and the way back to its
/// overview along the top, what shows — the overview, a set to study, a
/// conversation — and the line to ask in at the foot.
///
/// Everything here is the AI's, drawn apart from the notes — never on the
/// page, never in its text — and each answer shows where each part of it
/// comes from.
///
/// It has keys of its own, as a mode: o its overview, the digits each set
/// to study, i the question to ask, n a new conversation, c the
/// conversations and answers kept, q a question ready to ask, h j k l
/// what it lists, Space or ? these keys, and Esc back to the notes.
class AiView extends ConsumerStatefulWidget {
  const AiView({required this.scope, super.key});

  final NoteLink scope;

  @override
  ConsumerState<AiView> createState() => _AiViewState();
}

class _AiViewState extends ConsumerState<AiView> {
  /// What has the keys while nothing is typed in: the AI mode's own.
  final FocusNode _keys = FocusNode(debugLabel: 'AI');

  /// The question asked.
  final FocusNode _ask = FocusNode(debugLabel: 'Ask');

  /// Where what the keys have moved to in the pane is, for the ring round
  /// it, in the pane's own coordinates.
  final ValueNotifier<Rect?> _ring = ValueNotifier<Rect?>(null);
  final GlobalKey _area = GlobalKey();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusMoved);
    // Called up over the page, which had them, it takes the keys.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusMoved);
    _keys.dispose();
    _ask.dispose();
    _ring.dispose();
    super.dispose();
  }

  /// Whether what has the keyboard is typed in.
  static bool _typing(FocusNode? focus) =>
      focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  /// What in the pane the keys have moved to, if anything: not the pane
  /// itself, nor a field typed in, nor a set studied, which takes keys of
  /// its own and is not gone through.
  FocusNode? get _picked {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null ||
        focus == _keys ||
        !_keys.hasFocus ||
        focus.skipTraversal ||
        _typing(focus)) {
      return null;
    }
    return focus;
  }

  /// Rings what the keys moved to, once it is laid out where it is going.
  void _focusMoved() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final box = _picked?.context?.findRenderObject() as RenderBox?;
    final area = _area.currentContext?.findRenderObject() as RenderBox?;
    _ring.value = box == null || area == null || !box.attached
        ? null
        : box.localToGlobal(Offset.zero, ancestor: area) & box.size;
  });

  /// Moves the keys [direction] among what the pane offers: from the pane
  /// itself to the first, or for up and left the last, else to the nearest
  /// that way.
  void _step(TraversalDirection direction) {
    final picked = _picked;
    if (picked != null) {
      picked.focusInDirection(direction);
      return;
    }
    // As read: top to bottom, then left to right.
    final offered =
        <FocusNode>[
          for (final node in _keys.traversalDescendants)
            if (!_typing(node)) node,
        ]..sort((a, b) {
          final across = a.rect.top.compareTo(b.rect.top);
          return across != 0 ? across : a.rect.left.compareTo(b.rect.left);
        });
    if (offered.isEmpty) return;
    final back =
        direction == TraversalDirection.up ||
        direction == TraversalDirection.left;
    (back ? offered.last : offered.first).requestFocus();
  }

  static const Map<String, TraversalDirection> _directions =
      <String, TraversalDirection>{
        'h': TraversalDirection.left,
        'j': TraversalDirection.down,
        'k': TraversalDirection.up,
        'l': TraversalDirection.right,
        ModeKey.left: TraversalDirection.left,
        ModeKey.down: TraversalDirection.down,
        ModeKey.up: TraversalDirection.up,
        ModeKey.right: TraversalDirection.right,
      };

  AiSession get _session => ref.read(aiSessionProvider(widget.scope).notifier);

  /// The AI mode's keys.
  KeyLayer _layer() {
    final state = ref.read(aiSessionProvider(widget.scope));
    final profiles = studyProfilesOf(ref, state);
    return KeyLayer('AI mode', <KeyGroup>[
      KeyGroup(<KeyAction>[
        KeyAction('o', 'Overview', run: _session.newThread),
        KeyAction(
          'i',
          'Ask',
          run: _ask.requestFocus,
          also: const <String>[ModeKey.enter],
        ),
        KeyAction(
          'n',
          'A new conversation',
          run: () {
            _session.newThread();
            _ask.requestFocus();
          },
        ),
        KeyAction(
          'c',
          'Conversations and kept answers…',
          run: _chooseKept,
          enabled: state.threads.isNotEmpty || state.savedAnswers.isNotEmpty,
        ),
        KeyAction(
          'q',
          'A question ready to ask',
          layer: _questions,
          enabled: state.pending == null,
        ),
      ]),
      KeyGroup(title: 'Study', <KeyAction>[
        for (final (index, profile) in profiles.take(9).indexed)
          KeyAction(
            '${index + 1}',
            profile.name,
            run: () => _session.openProfile(profile.id),
          ),
      ]),
      KeyGroup(<KeyAction>[
        KeyAction(
          ModeKey.escape,
          'Back to the notes',
          run: ref.read(tabsProvider.notifier).toggleAi,
        ),
        KeyAction(
          ModeKey.space,
          'These keys',
          layer: _layer,
          also: const <String>['?'],
        ),
      ]),
    ]);
  }

  /// The questions ready to ask about the scope, each a key away.
  KeyLayer _questions() {
    final keys = galleryKeys(AiAction.values.length);
    return KeyLayer.of('Ask', <KeyAction>[
      for (final (index, action) in AiAction.values.indexed)
        KeyAction(
          keys[index],
          action.label,
          run: () => askReady(ref, widget.scope, action),
        ),
    ]);
  }

  /// The conversations and the answers kept, to choose one by name.
  void _chooseKept() => unawaited(
    showChooser(
      context,
      hintFor: (_) => 'A conversation or an answer kept',
      choicesFor: (ref, typed) {
        final state = ref.watch(aiSessionProvider(widget.scope));
        final session = ref.read(aiSessionProvider(widget.scope).notifier);
        final looked = typed.trim().toLowerCase();
        bool wanted(String title) => title.toLowerCase().contains(looked);
        return <Choice>[
          for (final thread in state.threads)
            if (wanted(threadTitle(thread)))
              Choice(
                title: threadTitle(thread),
                detail: whenOf(thread.updatedAt),
                hint: 'Conversation',
                run: () => unawaited(session.openThread(thread.id)),
              ),
          for (final item in state.savedAnswers)
            if (wanted(item.title))
              Choice(
                title: item.title,
                detail: whenOf(item.createdAt),
                hint: 'Kept answer',
                run: () => session.openItem(item.id),
              ),
        ];
      },
    ),
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // What is typed is typed: Esc leaves the question for these keys.
    if (_typing(FocusManager.instance.primaryFocus)) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _keys.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final pressed = ModeKey.of(event, HardwareKeyboard.instance);
    if (pressed == null) return KeyEventResult.ignored;
    if (_directions[pressed] case final direction?) {
      _step(direction);
      return KeyEventResult.handled;
    }
    // With something in the pane taken by the keys, Enter and Space press
    // it, and Esc lets go of it before it leaves the AI.
    if (_picked != null) {
      if (pressed == ModeKey.enter || pressed == ModeKey.space) {
        return KeyEventResult.ignored;
      }
      if (pressed == ModeKey.escape) {
        _keys.requestFocus();
        return KeyEventResult.handled;
      }
    }
    final action = _layer().actionFor(pressed);
    if (action == null || !action.enabled) return KeyEventResult.ignored;
    final layer = action.layer;
    if (layer == null) {
      action.run!();
    } else {
      openKeyGuide(context, pressed: pressed, layer: layer, atOnce: true);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: Stack(
        key: _area,
        children: <Widget>[
          // Scrolled, what the ring is round moves: it follows.
          NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _focusMoved();
              return false;
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PaneDragArea(child: _Head(scope: widget.scope)),
                Divider(height: 1, color: tones.glassRim),
                Expanded(
                  child: _Main(scope: widget.scope, ask: _ask),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: FocusGlide(
              target: _ring,
              colour: EditorMode.ai.colourOn(tones),
              stays: true,
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- head

/// Whose AI it is, in the AI's colour, and the way back to its overview
/// from anywhere else in it.
class _Head extends ConsumerWidget {
  const _Head({required this.scope});

  final NoteLink scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final state = ref.watch(aiSessionProvider(scope));
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final colour = EditorMode.ai.colourOn(tones);
    // At least as tall as its words, however large they are.
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 14),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
            ),
            const SizedBox(width: 8),
            SmallCaps('AI', color: colour),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      info?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!state.atOverview) ...<Widget>[
                    const SizedBox(width: 10),
                    PillButton(
                      'Overview',
                      leading: Mark(
                        MarkShape.arrowLeft,
                        size: 9,
                        color: tones.text,
                      ),
                      tooltip: 'Back to the overview  (o)',
                      onPressed: ref
                          .read(aiSessionProvider(scope).notifier)
                          .newThread,
                    ),
                  ],
                ],
              ),
            ),
            // Only where there is room for it beside the rest.
            if (constraints.maxWidth >= _roomForKeys) ...<Widget>[
              const SizedBox(width: 10),
              const KeyHint('?  keys   Esc  notes'),
            ],
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  /// How wide the head is at least for the keys to be said in it, beside
  /// the scope and the way back to the overview.
  static const double _roomForKeys = 440;
}

// -------------------------------------------------------------------- main

class _Main extends ConsumerStatefulWidget {
  const _Main({required this.scope, required this.ask});

  final NoteLink scope;

  /// The question asked.
  final FocusNode ask;

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
    final profiles = studyProfilesOf(ref, state);
    StudyProfile? profileOf(String? id) =>
        profiles.where((profile) => profile.id == id).firstOrNull;
    final shown = profileOf(state.shownProfile);
    final set = item == null ? null : StudySet.fromJson(item.body);
    final Widget page;
    if (!state.loaded || model.isLoading) {
      page = const Loading();
    } else if (item != null && set != null) {
      page = StudySetPage(
        scope: scope,
        item: item,
        set: set,
        profile: profileOf(item.kind)!,
        onOpen: _open,
      );
    } else if (item != null) {
      page = _ItemReader(scope: scope, item: item, onOpen: _open);
    } else if (shown != null) {
      page = switch (state.making[shown.id]) {
        final making? => StudyDraftPage(
          scope: scope,
          pending: making,
          onOpen: _open,
        ),
        null => StudyProfilePage(scope: scope, profile: shown),
      };
    } else if (model.value == null) {
      page = const _ChooseModel();
    } else if (state.atOverview || state.shownProfile != null) {
      // The overview, too, where the profile shown was deleted.
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: page),
        if (state.error case final error?)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.tones.lift,
              borderRadius: Corners.controlRadius,
            ),
            child: Text(error, style: TextStyle(color: context.tones.text)),
          ),
        _AskLine(scope: scope, focus: widget.ask),
      ],
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Ask about your notes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a model to answer: one running on this computer, where '
              'your notes stay, or a provider you trust. Answers come from '
              'your notes first and say where each part comes from.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tones.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => showSettings(context, page: SettingsPage.ai),
              child: const Text('Choose a model'),
            ),
          ],
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
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      children: <Widget>[
        for (final turn in state.turns)
          _Exchange(
            question: turn.question,
            answer: AiAnswer.fromJson(turn.answer),
            byline: <String>[
              turn.provider,
              turn.model,
              if (AiSession.tookOf(turn) case final took?) wholeSeconds(took),
              ?costNote(AiSession.costOf(turn.usage)),
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

/// A question, set off to the right in the accent's tint, and its answer
/// beneath it.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.85,
              alignment: Alignment.centerRight,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: tones.lift,
                    // The corner it comes from, as a speech bubble's.
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(Corners.panel),
                      topRight: Radius.circular(Corners.panel),
                      bottomLeft: Radius.circular(Corners.panel),
                      bottomRight: Radius.circular(Corners.small),
                    ),
                  ),
                  child: SelectableText(question),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (pending != null) AnswerProgress(pending: pending!),
          if (!answer.isEmpty)
            AnswerView(
              answer: answer,
              onOpen: onOpen,
              showSources: done,
              onAddCards: onAddCards,
            ),
          if (done)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    byline!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tones.faint),
                  ),
                ),
                SmallButton(
                  'Copy',
                  tooltip: 'Copy the answer',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: answer.plainText)),
                ),
                SmallButton(
                  kept ? 'Kept' : 'Keep',
                  tooltip: kept
                      ? 'Kept, with the answers kept'
                      : 'Keep the answer, with the answers kept',
                  onPressed: kept ? null : onKeep,
                ),
              ],
            ),
        ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SmallCaps('Kept answer', color: tones.emphasis),
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              SmallButton(
                'Rename',
                onPressed: () async {
                  final title = await askName(context, item.title);
                  if (title != null) await session.renameItem(item.id, title);
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: Text(
              'Made by ${item.provider} · ${item.model}, '
              '${whenOf(item.createdAt)}',
              style: TextStyle(fontSize: 11.5, color: tones.muted),
            ),
          ),
          AnswerView(answer: answer, onOpen: onOpen),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- ask

/// The line to ask in, at the foot of the pane as the search line is at
/// the window's: what is asked is about the scope, and may search the web
/// where that is set up.
class _AskLine extends ConsumerStatefulWidget {
  const _AskLine({required this.scope, required this.focus});

  final NoteLink scope;

  /// The question's, which the AI mode's keys give the keyboard to.
  final FocusNode focus;

  @override
  ConsumerState<_AskLine> createState() => _AskLineState();
}

class _AskLineState extends ConsumerState<_AskLine> {
  final TextEditingController _text = TextEditingController();
  bool? _web;

  FocusNode get _focus => widget.focus;

  @override
  void initState() {
    super.initState();
    // Its edge is marked while it has the keyboard.
    _focus.addListener(_focused);
  }

  @override
  void dispose() {
    _focus.removeListener(_focused);
    _text.dispose();
    super.dispose();
  }

  void _focused() => setState(() {});

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
    final colour = EditorMode.ai.colourOn(tones);
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, 28)),
      padding: WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(horizontal: 14),
      ),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tones.base.withValues(alpha: 0.55),
          border: Border.all(
            color: _focus.hasFocus ? tones.emphasis : tones.glassRim,
            width: _focus.hasFocus ? 1.5 : 1,
          ),
          borderRadius: Corners.panelRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 6, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 9, right: 8),
                    child: Text(
                      '›',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                  ),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.enter): _send,
                      },
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 6,
                        enabled: model != null,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          hintText: model == null
                              ? 'Choose a model to ask'
                              : 'Ask about ${info == null ? 'this' : '“${info.title}”'}…',
                        ),
                      ),
                    ),
                  ),
                ],
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
                  const SizedBox(width: 2),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        const Flexible(child: _ModelButton()),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            info == null
                                ? ''
                                : 'Starts from this ${info.kindName}, then '
                                      'all your notes',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: tones.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (pending != null)
                    Tooltip(
                      message: 'Stop',
                      child: OutlinedButton(
                        style: compact,
                        onPressed: () => unawaited(
                          ref
                              .read(aiSessionProvider(widget.scope).notifier)
                              .stop(),
                        ),
                        child: const Text('Stop'),
                      ),
                    )
                  else
                    Tooltip(
                      message: 'Ask (Enter)',
                      child: FilledButton(
                        style: compact,
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
    );
  }
}

/// Whether this question searches the web: a pill, lit while it does.
class _WebToggle extends StatelessWidget {
  const _WebToggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return PillButton(
      'Web',
      lit: on,
      onPressed: onChanged == null ? null : () => onChanged(!on),
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
    return SmallButton(
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
    );
  }
}

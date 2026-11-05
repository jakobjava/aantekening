/// A notebook's, section's or page's AI: a pane of glass over the notes,
/// to ask about them in and to study them by.
///
/// The pane, its keys, its head and the page it shows here; a
/// conversation, and the line to ask in, each a part of its own.
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
import 'ai_common.dart';
import 'ai_session.dart';
import 'ai_state.dart';
import 'answer_progress.dart';
import 'answer_view.dart';
import 'money.dart';
import 'podcast_view.dart';
import 'study_pages.dart';

part 'ai_ask_line.dart';
part 'ai_conversation.dart';

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
    final profiles = studyProfilesOf(ref, state.items);
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
    final atOverview = ref.watch(
      aiSessionProvider(scope).select((s) => s.atOverview),
    );
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
                  if (!atOverview) ...<Widget>[
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

  /// What of [s] decides the page shown: not how far an answer has got,
  /// which the conversation follows itself, nor a set or a podcast being
  /// made while another page shows.
  static _Showing _showingOf(AiSessionState s) => (
    loaded: s.loaded,
    items: s.items,
    itemId: s.itemId,
    atOverview: s.atOverview,
    shownProfile: s.shownProfile,
    shownPodcast: s.shownPodcast,
    making: s.making[s.shownProfile],
    podcast: s.podcasts[s.shownPodcast],
    error: s.error,
  );

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final state = ref.watch(aiSessionProvider(scope).select(_showingOf));
    final model = ref.watch(aiModelProvider);
    ref.listen(aiSessionProvider(scope), (_, _) => _follow());

    final item = state.items
        .where((item) => item.id == state.itemId)
        .firstOrNull;
    final profiles = studyProfilesOf(ref, state.items);
    StudyProfile? profileOf(String? id) =>
        profiles.where((profile) => profile.id == id).firstOrNull;
    final shown = profileOf(state.shownProfile);
    final set = item?.studySet;
    final podcast = item?.episode;
    final episodeProfile = ref
        .watch(aiSettingsProvider.select((s) => s.episodes))
        .where((profile) => profile.id == state.shownPodcast)
        .firstOrNull;
    final Widget page;
    if (!state.loaded || model.isLoading) {
      page = const Loading();
    } else if (item != null && podcast != null) {
      page = PodcastPage(
        key: ValueKey<String>(item.id),
        scope: scope,
        item: item,
      );
    } else if (episodeProfile != null && state.podcast != null) {
      page = PodcastDraftPage(
        scope: scope,
        profile: episodeProfile,
        progress: state.podcast!,
      );
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
      page = switch (state.making) {
        final making? => StudyDraftPage(
          scope: scope,
          pending: making,
          onOpen: _open,
        ),
        null => StudyProfilePage(scope: scope, profile: shown),
      };
    } else if (model.value == null) {
      page = _ChooseModel(trouble: model.error);
    } else if (state.atOverview ||
        state.shownProfile != null ||
        state.shownPodcast != null) {
      // The overview, too, where the profile shown was deleted.
      page = StudyOverview(scope: scope);
    } else {
      page = _Conversation(scope: scope, scroll: _scroll, onOpen: _open);
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

/// What of an AI session [_Main] shows by: what is kept, and which of it,
/// or of the profiles, is open; and how far the set or the podcast open is
/// along, if it is being made.
typedef _Showing = ({
  bool loaded,
  List<AiItem> items,
  String? itemId,
  bool atOverview,
  String? shownProfile,
  String? shownPodcast,
  PendingTurn? making,
  PodcastProgress? podcast,
  String? error,
});

/// Before a model is chosen: what the AI does, and where to choose one.
class _ChooseModel extends StatelessWidget {
  const _ChooseModel({this.trouble});

  /// Why the model chosen could not be set up, if one is chosen: its key
  /// not read from the keychain, say.
  final Object? trouble;

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
            if (trouble case final trouble?) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'The model chosen could not be set up: '
                '${trouble is AiException ? trouble.message : trouble}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: tones.text,
                  height: 1.4,
                ),
              ),
            ],
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

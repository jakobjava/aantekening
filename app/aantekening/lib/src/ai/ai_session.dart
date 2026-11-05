/// A notebook's, section's or page's AI: its conversations, what was kept,
/// and the question being answered.
///
/// One session, in parts by what it does: asking in its conversations, the
/// study sets it makes and the flashcards among them, and its podcasts,
/// each a part of its own beside what they share here.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'ai_state.dart';
import 'workspace_reader.dart';

part 'ai_session_conversations.dart';
part 'ai_session_podcasts.dart';
part 'ai_session_study_sets.dart';

/// Reads the workspace for the AI, one reader for the workspace open.
final workspaceReaderProvider = FutureProvider<WorkspaceReader>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return WorkspaceReader(store);
});

/// What a notebook, section or page is called and where it is, for the AI
/// view to say what it is about.
final aiScopeInfoProvider = FutureProvider.family<ScopeInfo?, NoteLink>((
  ref,
  link,
) async {
  ref.watch(libraryRevisionProvider);
  final reader = await ref.watch(workspaceReaderProvider.future);
  return reader.scope(link);
});

@immutable
class AiSessionState {
  const AiSessionState({
    this.loaded = false,
    this.threads = const <AiThread>[],
    this.items = const <AiItem>[],
    this.threadId,
    this.itemId,
    this.turns = const <AiTurn>[],
    this.pending,
    this.making = const <String, PendingTurn>{},
    this.shownProfile,
    this.podcasts = const <String, PodcastProgress>{},
    this.shownPodcast,
    this.error,
  });

  final bool loaded;

  /// The conversations about it, the latest first.
  final List<AiThread> threads;

  /// What was kept about it.
  final List<AiItem> items;

  /// The conversation showing, or null for a new one.
  final String? threadId;

  /// The kept thing showing in place of a conversation, if one is.
  final String? itemId;

  /// The questions of the conversation showing.
  final List<AiTurn> turns;

  /// The question being answered, if one is.
  final PendingTurn? pending;

  /// The study sets being made, by the id of their profile, each as far as
  /// it has got. They are made alongside each other and the question, while
  /// anything else is looked at.
  final Map<String, PendingTurn> making;

  /// The id of the profile whose page shows, where its set is being made
  /// or not made yet; once made, its kept set shows as [itemId].
  final String? shownProfile;

  /// The podcasts being made, by the id of their episode profile, and
  /// those kept being spoken again, by the id of what keeps them.
  final Map<String, PodcastProgress> podcasts;

  /// The id of the episode profile whose podcast shows being made.
  final String? shownPodcast;

  /// Why the last question went unanswered.
  final String? error;

  AiItem? get item => items.where((item) => item.id == itemId).firstOrNull;

  /// Whether the overview shows: nothing opened, nothing under way.
  bool get atOverview =>
      itemId == null &&
      threadId == null &&
      shownProfile == null &&
      shownPodcast == null &&
      pending == null;

  /// The kept set of profile [id], if one was made.
  AiItem? setOf(String id) => items.setOf(id);

  /// The answers kept from conversations.
  List<AiItem> get savedAnswers => items.savedAnswers;

  /// The podcasts kept, the latest first.
  List<AiItem> get episodes => items.episodes;

  AiSessionState copyWith({
    bool? loaded,
    List<AiThread>? threads,
    List<AiItem>? items,
    String? Function()? threadId,
    String? Function()? itemId,
    List<AiTurn>? turns,
    PendingTurn? Function()? pending,
    Map<String, PendingTurn>? making,
    String? Function()? shownProfile,
    Map<String, PodcastProgress>? podcasts,
    String? Function()? shownPodcast,
    String? Function()? error,
  }) => AiSessionState(
    loaded: loaded ?? this.loaded,
    threads: threads ?? this.threads,
    items: items ?? this.items,
    threadId: threadId == null ? this.threadId : threadId(),
    itemId: itemId == null ? this.itemId : itemId(),
    turns: turns ?? this.turns,
    pending: pending == null ? this.pending : pending(),
    making: making ?? this.making,
    shownProfile: shownProfile == null ? this.shownProfile : shownProfile(),
    podcasts: podcasts ?? this.podcasts,
    shownPodcast: shownPodcast == null ? this.shownPodcast : shownPodcast(),
    error: error == null ? this.error : error(),
  );
}

/// What a thing kept holds, read from its JSON once however often it is
/// asked for: a study set, a podcast, or else an answer.
extension KeptItem on AiItem {
  static final Expando<(StudySet?, PodcastEpisode?)> _read =
      Expando<(StudySet?, PodcastEpisode?)>('kept');

  (StudySet?, PodcastEpisode?) get _held =>
      _read[this] ??= (StudySet.fromJson(body), PodcastEpisode.fromJson(body));

  /// The study set it holds, if it holds one.
  StudySet? get studySet => _held.$1;

  /// The podcast it holds, if it holds one.
  PodcastEpisode? get episode => _held.$2;
}

/// The things kept about a scope, sorted by what they hold.
extension KeptItems on List<AiItem> {
  /// The kept set of profile [id], if one was made.
  AiItem? setOf(String id) =>
      where((item) => item.kind == id && item.studySet != null).firstOrNull;

  /// The profiles to study by: [configured], then one for each set kept
  /// whose own profile is gone, to see it and make it again by.
  List<StudyProfile> profilesWith(List<StudyProfile> configured) {
    final ids = <String>{for (final profile in configured) profile.id};
    return <StudyProfile>[
      ...configured,
      for (final item in this)
        if (item.studySet case final set? when ids.add(item.kind))
          StudyProfile(
            id: item.kind,
            name: item.title,
            form: set.kind,
            idea: set.kind.idea,
          ),
    ];
  }

  /// The answers kept from conversations.
  List<AiItem> get savedAnswers => <AiItem>[
    for (final item in this)
      if (item.studySet == null && item.episode == null) item,
  ];

  /// The podcasts kept, the latest first.
  List<AiItem> get episodes => <AiItem>[
    for (final item in this)
      if (item.episode != null) item,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// The AI of the notebook, section or page [scope].
///
/// Kept while the app runs, so an answer goes on arriving while another
/// tab is showing.
class AiSession extends _AiSessionCore
    with _Conversations, _StudySets, _Podcasts {
  AiSession(super.scope);

  @override
  AiSessionState build() {
    // Other notes opened, from another folder: begun afresh, nothing of
    // these kept in those.
    ref.watch(storeProvider.select((store) => store.value));
    ref.onDispose(() {
      unawaited(_answering?.cancel());
      for (final maker in <StreamSubscription<Object?>>{
        ..._makers.values,
        ..._podcasters.values,
      }) {
        unawaited(maker.cancel());
      }
      _answering = null;
      _makers.clear();
      _podcasters.clear();
    });
    unawaited(_load());
    return const AiSessionState();
  }

  /// Shows conversation [id].
  Future<void> openThread(String id) async {
    final store = await _store;
    final turns = await store.ai.turnsOf(id);
    state = state.copyWith(
      threadId: () => id,
      itemId: () => null,
      turns: turns,
      shownProfile: () => null,
      shownPodcast: () => null,
      error: () => null,
    );
  }

  /// Shows the overview, where a new conversation starts.
  void newThread() => state = state.copyWith(
    threadId: () => null,
    itemId: () => null,
    shownProfile: () => null,
    shownPodcast: () => null,
    turns: const <AiTurn>[],
    error: () => null,
  );

  /// Shows kept thing [id].
  @override
  void openItem(String id) => state = state.copyWith(
    itemId: () => id,
    shownProfile: () => null,
    shownPodcast: () => null,
  );

  /// How long [turn] took to answer, if that was kept.
  static Duration? tookOf(AiTurn turn) => switch (turn.usage?[_tookKey]) {
    final int ms => Duration(milliseconds: ms),
    _ => null,
  };

  /// What a turn or a kept set with [usage] cost, in US dollars, if that
  /// was kept.
  static double? costOf(Map<String, Object?>? usage) =>
      (usage?[_costKey] as num?)?.toDouble();

  Future<void> renameItem(String id, String title) async {
    await (await _store).ai.renameItem(id, title);
    await _load();
  }

  Future<void> deleteItem(String id) async {
    // A podcast being spoken is stopped first; its sound goes as the
    // speaking left it.
    if (state.podcasts.containsKey(id)) await stopPodcast(id);
    final item = state.items.where((item) => item.id == id).firstOrNull;
    if (item?.episode case final episode? when episode.spoken) {
      await deletePodcastAudio(ref, episode.audio);
    }
    await (await _store).ai.deleteItem(id);
    if (state.itemId == id) state = state.copyWith(itemId: () => null);
    await _load();
  }

  Future<void> deleteThread(String id) async {
    await (await _store).ai.deleteThread(id);
    if (state.threadId == id) newThread();
    await _load();
  }
}

/// What the parts of an [AiSession] share: where it keeps what it is
/// answered, the model it asks and the notes it reads, and following an
/// answer or a set as it comes.
abstract class _AiSessionCore extends Notifier<AiSessionState> {
  _AiSessionCore(this.scope);

  final NoteLink scope;

  /// The sets and podcasts being started, as `set <id>` and `podcast <id>`
  /// by the id of their profile, from the click that makes one until it
  /// shows as being made: marked before anything is awaited, so a second
  /// click meanwhile starts no second one, paid for twice.
  final Set<String> _starting = <String>{};

  Future<AantekeningStore> get _store => ref.read(storeProvider.future);

  Future<void> _load({String? threadId}) async {
    final store = await _store;
    final threads = await store.ai.threadsAbout(scope);
    final items = await store.ai.itemsAbout(scope);
    final open = threadId ?? state.threadId;
    final turns = open == null
        ? const <AiTurn>[]
        : await store.ai.turnsOf(open);
    // The state taken once they are read: an answer or a set may have
    // moved on, or ended, meanwhile.
    state = state.copyWith(
      loaded: true,
      threads: threads,
      items: items,
      threadId: () => open,
      turns: turns,
    );
  }

  /// The model in use, the notes, and what the scope is, to answer or make
  /// something with — or null, said why where no model is chosen.
  Future<_Ready?> _ready(String noModel) async {
    final model = await ref.read(aiModelProvider.future);
    if (model == null) {
      state = state.copyWith(error: () => noModel);
      return null;
    }
    final reader = await ref.read(workspaceReaderProvider.future);
    final info = await reader.scope(scope);
    if (info == null) return null;
    return (model: model, reader: reader, info: info);
  }

  /// A model to answer with, as the settings have it: what it is asked
  /// bears in mind what the person says of themselves.
  NoteAgent _agent(AiModel model, WorkspaceReader reader, {WebSearch? web}) =>
      NoteAgent(
        provider: model.provider,
        model: model.config.model,
        reader: reader,
        webSearch: web,
        notesTokens: model.config.notesTokens,
        about: ref.read(aiSettingsProvider).about,
      );

  /// Follows [answer] into what [read] and [write] keep of it — the
  /// question's pending turn, or a set's — handing its subscription to
  /// [started], telling [ended] once it has come to an end, and [onDone]
  /// with how it ended, to keep it.
  Future<void> _follow(
    Stream<AgentProgress> answer, {
    required PendingTurn? Function() read,
    required void Function(PendingTurn? pending) write,
    required void Function(StreamSubscription<AgentProgress>) started,
    required Future<void> Function(AgentProgress last) onDone,
    void Function()? ended,
  }) {
    final done = Completer<void>();
    AgentProgress? last;
    started(
      answer.listen(
        (progress) {
          last = progress;
          final pending = read();
          if (pending != null) write(pending.moved(progress, DateTime.now()));
        },
        onError: (Object error) {
          ended?.call();
          final profile = read()?.profile;
          write(null);
          final why = error is AiException
              ? error.message
              : 'it broke off: $error';
          state = state.copyWith(
            error: () => switch (profile?.called) {
              null =>
                error is AiException ? why : 'The answer broke off: $error',
              final called =>
                '${called[0].toUpperCase()}${called.substring(1)} could not '
                    'be made: $why',
            },
          );
          if (!done.isCompleted) done.complete();
        },
        onDone: () async {
          ended?.call();
          final progress = last;
          final called = read()?.profile?.called;
          try {
            if (progress != null && progress.done) await onDone(progress);
          } on Object catch (error) {
            // Not kept — the conversation deleted meanwhile, say — and
            // said so, rather than left being answered for good.
            state = state.copyWith(
              error: () => switch (called) {
                null => 'The answer could not be kept: $error',
                final called =>
                  '${called[0].toUpperCase()}${called.substring(1)} could '
                      'not be kept: $error',
              },
            );
          } finally {
            if (read() != null) write(null);
            if (!done.isCompleted) done.complete();
          }
        },
        cancelOnError: true,
      ),
    );
    return done.future;
  }
}

/// What [progress] took, done — and what it cost, and how long it
/// [took], where that is known — as a turn or a kept set keeps it.
Map<String, Object?> _usageOf(AgentProgress progress, {Duration? took}) =>
    <String, Object?>{
      'input': progress.usage.input,
      'output': progress.usage.output,
      'cacheRead': progress.usage.cacheRead,
      'cacheWrite': progress.usage.cacheWrite,
      'webSearches': progress.usage.webSearches,
      _costKey: ?progress.cost,
      if (took != null) _tookKey: took.inMilliseconds,
    };

const String _tookKey = 'milliseconds';
const String _costKey = 'dollars';

/// What [AiSession] answers or makes with, read.
typedef _Ready = ({AiModel model, WorkspaceReader reader, ScopeInfo info});

final aiSessionProvider =
    NotifierProvider.family<AiSession, AiSessionState, NoteLink>(AiSession.new);

/// The profiles to study a scope by whose kept things are [items], as
/// [KeptItems.profilesWith] has them.
List<StudyProfile> studyProfilesOf(WidgetRef ref, List<AiItem> items) {
  // Built again as the profiles change, not as anything else set does:
  // what one says of oneself, typed in, say.
  ref.watch(aiSettingsProvider.select((s) => s.profiles));
  return items.profilesWith(ref.read(aiSettingsProvider).studyProfiles);
}

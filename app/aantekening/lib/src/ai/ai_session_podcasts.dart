part of 'ai_session.dart';

/// The podcasts of an [AiSession]: made alongside anything else, and
/// those kept spoken again.
mixin _Podcasts on _AiSessionCore {
  /// What makes or speaks each podcast under way, by the key of
  /// [AiSessionState.podcasts].
  final Map<String, StreamSubscription<PodcastProgress>> _podcasters =
      <String, StreamSubscription<PodcastProgress>>{};

  /// Shows the podcast of episode profile [id] being made, or the latest
  /// made by it.
  void showPodcast(String id) => state = state.copyWith(
    itemId: () => null,
    threadId: () => null,
    turns: const <AiTurn>[],
    shownProfile: () => null,
    shownPodcast: () => id,
  );

  /// A model to write a podcast with, as [choice] names it, with its key,
  /// and whether it is the podcast's own to close once written, else the
  /// model in use's to let go of — or null where it names none that is
  /// set up.
  Future<({PodcastWriter writer, bool own})?> _writerOf(
    ModelChoice choice,
  ) async {
    if (choice.isInUse) {
      final model = await ref.read(aiModelProvider.future);
      if (model == null) return null;
      // Held open, though the settings change, until it is written.
      holdProvider(model.provider);
      return (
        writer: (provider: model.provider, model: model.config.model),
        own: false,
      );
    }
    final config = ref.read(aiSettingsProvider).providerOf(choice);
    if (config == null) return null;
    final model = choice.model.isEmpty ? config.model : choice.model;
    if (model.isEmpty) return null;
    final key = await ref
        .read(aiSecretsProvider)
        .read(providerKeyName(config.id));
    return (
      writer: (provider: config.create(apiKey: key), model: model),
      own: true,
    );
  }

  /// What speaks podcasts through [voice], in [model] or its own.
  Future<SpeechProvider> _speechOf(VoiceConfig voice, String model) async =>
      ref.read(speechMakerProvider)(
        voice,
        await ref.read(aiSecretsProvider).read(voiceKeyName(voice.id)),
        model,
      );

  /// Keeps how far the podcast under [key] has got, under every key it
  /// goes by, or with null that it is no longer under way.
  void _setPodcast(String key, PodcastProgress? progress) {
    final keys = _keysOf(key);
    state = state.copyWith(
      podcasts: <String, PodcastProgress>{
        for (final entry in state.podcasts.entries)
          if (!keys.contains(entry.key)) entry.key: entry.value,
        for (final key in keys) key: ?progress,
      },
    );
  }

  /// The keys the podcast under way under [key] goes by: the id of its
  /// episode profile and, once it is kept, that of what keeps it.
  Set<String> _keysOf(String key) {
    final run = _podcasters[key];
    return <String>{
      key,
      if (run != null)
        for (final MapEntry(key: other, value: each) in _podcasters.entries)
          if (identical(each, run)) other,
    };
  }

  /// Has the podcast under way under [key] go by [also] too: one made,
  /// once kept, by what keeps it — so its page shows it being spoken, and
  /// it is not spoken a second time from there, and stops if deleted.
  void _podcastAlsoAs(String key, String also) {
    if (!_podcasters.containsKey(key)) return;
    _podcasters[also] = _podcasters[key]!;
    _setPodcast(key, state.podcasts[key]);
  }

  /// Follows [run] into [AiSessionState.podcasts] under [key], saying
  /// what went wrong as [failed] puts it.
  Future<void> _followPodcast(
    String key,
    Stream<PodcastProgress> run, {
    required String Function(String why) failed,
  }) {
    final done = Completer<void>();
    final subscription = run.listen(
      (progress) => _setPodcast(key, progress),
      onError: (Object error) {
        _setPodcast(key, null);
        final why = error is AiException ? error.message : '$error';
        state = state.copyWith(error: () => failed(why));
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        _setPodcast(key, null);
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    _podcasters[key] = subscription;
    return done.future.whenComplete(
      () => _podcasters.removeWhere((_, run) => identical(run, subscription)),
    );
  }

  /// Makes a podcast of the scope as episode profile [profile] says: plans
  /// it and writes what is said with the models it names, keeps the
  /// transcript, then speaks it with the voices of its speaker profile.
  /// Made alongside anything else; its page shows it coming.
  Future<void> makePodcast(EpisodeProfile profile) async {
    final id = profile.id;
    if (state.podcasts.containsKey(id)) {
      showPodcast(id);
      return;
    }
    final starting = 'podcast $id';
    if (!_starting.add(starting)) return;
    final settings = ref.read(aiSettingsProvider);
    final cast = settings.castOf(profile.speakersId);
    final voice = settings.voiceOf(cast?.voiceId ?? '');
    String? missing;
    if (cast == null) {
      missing = 'Set up who speaks in the AI settings first.';
    } else if (voice == null) {
      missing =
          'Add a voice provider in the AI settings first: it speaks the '
          'podcast.';
    }
    final ({PodcastWriter writer, bool own})? outlining;
    final ({PodcastWriter writer, bool own})? writing;
    final WorkspaceReader reader;
    final ScopeInfo? scoped;
    try {
      outlining = await _writerOf(profile.outline);
      writing = await _writerOf(profile.transcript);
      reader = await ref.read(workspaceReaderProvider.future);
      scoped = await reader.scope(scope);
    } on Object catch (error) {
      // A key the keychain would not give, say.
      state = state.copyWith(
        error: () => 'The podcast could not be made: $error',
      );
      return;
    } finally {
      _starting.remove(starting);
    }
    void close() {
      for (final used in <({PodcastWriter writer, bool own})?>[
        outlining,
        writing,
      ]) {
        switch (used) {
          case (:final writer, own: true):
            writer.provider.close();
          case (:final writer, own: false):
            releaseProvider(writer.provider);
          case null:
        }
      }
    }

    if (outlining == null || writing == null) {
      missing ??=
          'Choose the models that write “${profile.name}” in the podcast '
          'settings first.';
    }
    if (missing != null || scoped == null) {
      close();
      if (missing != null) state = state.copyWith(error: () => missing);
      return;
    }
    final info = scoped;
    final outliner = outlining!.writer;
    final writer = writing!.writer;
    final speakers = cast!.voiced(voice!.voiceFor);
    _setPodcast(
      id,
      const PodcastProgress(
        stage: PodcastStage.gathering,
        activity: 'Gathering your notes',
      ),
    );
    showPodcast(id);
    state = state.copyWith(error: () => null);
    final maker = PodcastMaker(
      reader: reader,
      outliner: outliner,
      writer: writer,
      notesTokens:
          settings.active?.notesTokens ?? ContextBudget.defaultNotesTokens,
      about: settings.about,
    );
    final models = <String>{outliner.model, writer.model}.toList();
    String? kept;
    Stream<PodcastProgress> run() async* {
      PodcastProgress? written;
      try {
        await for (final progress in maker.write(
          profile,
          speakers: speakers,
          scope: info,
        )) {
          written = progress;
          yield progress;
        }
      } finally {
        close();
      }
      if (written == null || !written.done) return;
      // The transcript is kept first: if speaking fails, it stays.
      final episode = PodcastEpisode(
        title: profile.name,
        profile: profile.name,
        outline: written.outline,
        lines: written.lines,
        speakers: speakers,
        models: models,
      );
      final store = await _store;
      final item = await store.ai.addItem(
        scope,
        kind: PodcastEpisode.kindKey,
        title: '${profile.name} · ${info.title}',
        body: episode.toJson(),
        provider: profile.transcript.isInUse
            ? (await ref.read(aiModelProvider.future))?.config.name ?? ''
            : settings.providerOf(profile.transcript)?.name ?? '',
        model: writer.model,
        usage: <String, Object?>{
          'input': written.usage.input,
          'output': written.usage.output,
          _costKey: ?written.cost,
        },
      );
      kept = item.id;
      _podcastAlsoAs(id, item.id);
      await _load();
      yield* _spoken(
        item.id,
        episode,
        voice: voice,
        model: cast.voiceModel,
        written: written,
      );
    }

    await _followPodcast(
      id,
      run(),
      failed: (why) => 'The podcast could not be made: $why',
    );
    if (state.shownPodcast == id) {
      state = state.copyWith(shownPodcast: () => null, itemId: () => kept);
    }
  }

  /// [episode], kept as item [itemId], spoken through [voice] — its sound
  /// saved and the item told where — showing [written] while it is.
  Stream<PodcastProgress> _spoken(
    String itemId,
    PodcastEpisode episode, {
    required VoiceConfig voice,
    required String model,
    PodcastProgress? written,
  }) async* {
    final speech = await _speechOf(voice, model);
    try {
      await for (final progress in PodcastMaker.speak(
        episode.lines,
        speakers: episode.speakers,
        speech: speech,
        parallel: voice.local ? 1 : 4,
      )) {
        if (progress.sound case final sound?) {
          final audio = await savePodcastAudio(ref, sound);
          final store = await _store;
          await store.ai.updateItem(
            itemId,
            body: episode
                .copyWith(
                  audio: audio,
                  duration: sound.duration,
                  starts: progress.starts,
                  voice:
                      '${voice.name} · '
                      '${model.trim().isEmpty ? voice.model : model.trim()}',
                  voiceId: voice.id,
                )
                .toJson(),
          );
          await _load();
        }
        yield written == null
            ? progress
            : progress.copyWith(outline: written.outline);
      }
    } on AiException catch (error) {
      throw AiException(
        'it was written, but could not be spoken: ${error.message} Its '
        'transcript is kept; speak it again from its page.',
      );
    } finally {
      speech.close();
    }
  }

  /// Speaks kept podcast [itemId] again: one made on another computer, or
  /// one whose speaking failed — with the voices it was made with where
  /// their provider is still set up, else with the first voice provider's.
  Future<void> speakPodcast(String itemId) async {
    if (state.podcasts.containsKey(itemId)) return;
    final item = state.items.where((item) => item.id == itemId).firstOrNull;
    final episode = item?.episode;
    if (episode == null) return;
    final settings = ref.read(aiSettingsProvider);
    final voice = settings.voiceOf(episode.voiceId);
    if (voice == null) {
      state = state.copyWith(
        error: () =>
            'Add a voice provider in the AI settings first: it speaks the '
            'podcast.',
      );
      return;
    }
    final same = voice.id == episode.voiceId;
    final speakers = same
        ? episode.speakers
        : <PodcastSpeaker>[
            for (final (i, speaker) in episode.speakers.indexed)
              speaker.copyWith(voice: voice.voiceFor(i)),
          ];
    _setPodcast(
      itemId,
      PodcastProgress(stage: PodcastStage.speaking, lines: episode.lines),
    );
    state = state.copyWith(error: () => null);
    await _followPodcast(
      itemId,
      _spoken(
        itemId,
        episode.copyWith(speakers: speakers),
        voice: voice,
        model: '',
      ),
      failed: (why) => 'The podcast could not be spoken: $why',
    );
  }

  /// Stops making or speaking the podcast under [key].
  Future<void> stopPodcast(String key) async {
    final keys = _keysOf(key);
    final run = _podcasters[key];
    _setPodcast(key, null);
    keys.forEach(_podcasters.remove);
    await run?.cancel();
    if (keys.contains(state.shownPodcast)) {
      state = state.copyWith(shownPodcast: () => null);
    }
  }
}

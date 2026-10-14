/// Podcasts of the notes, heard and read: a kept episode with a player and
/// its transcript following along, and an episode shown as it is made.
library;

import 'dart:async';
import 'dart:io';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../look/controls.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import 'ai_session.dart';
import 'ai_state.dart';
import 'money.dart';
import 'study_pages.dart';
import 'study_style.dart';

/// How long [duration] runs, as a player shows it: "4:07", "1:02:30".
String clockOf(Duration duration) {
  final seconds = duration.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = seconds ~/ 3600;
  final m = seconds ~/ 60 % 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Why sound could not be played, from [error], and what to do about it:
/// on Linux, a WAV is read by GStreamer's good plugins, which not every
/// system has.
String playbackTrouble(Object error) =>
    'The sound could not be played'
    '${Platform.isLinux ? ' — on Linux it needs GStreamer’s good plugins: '
              'install gst-plugins-good (Arch) or '
              'gstreamer1.0-plugins-good (Debian, Ubuntu)' : ''}. ($error)';

/// The speaking speeds to choose from.
const List<double> _rates = <double>[1, 1.25, 1.5, 2];

/// Kept podcast [item] on a page of its own: its head, a player while it
/// has its sound here, and its transcript, the line being said marked.
class PodcastPage extends ConsumerStatefulWidget {
  const PodcastPage({required this.scope, required this.item, super.key});

  final NoteLink scope;
  final AiItem item;

  @override
  ConsumerState<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends ConsumerState<PodcastPage> {
  /// Made when first played, so a page only looked at opens no player.
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _listening =
      <StreamSubscription<Object?>>[];
  String? _source;
  Duration _position = Duration.zero;
  bool _playing = false;
  double _rate = 1;

  PodcastEpisode? get _episode => PodcastEpisode.fromJson(widget.item.body);

  @override
  void didUpdateWidget(PodcastPage old) {
    super.didUpdateWidget(old);
    // Spoken again, it is another sound.
    if (_episode?.audio != PodcastEpisode.fromJson(old.item.body)?.audio) {
      unawaited(_release());
    }
  }

  @override
  void dispose() {
    unawaited(_release(gone: true));
    super.dispose();
  }

  /// Lets the player go — and, unless the page is [gone], shows it at the
  /// start again.
  Future<void> _release({bool gone = false}) async {
    for (final listening in _listening) {
      await listening.cancel();
    }
    _listening.clear();
    final player = _player;
    _player = null;
    _source = null;
    if (!gone && mounted) {
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    }
    await player?.dispose();
  }

  Future<AudioPlayer> _ready(String path) async {
    final player = _player ??= () {
      final player = AudioPlayer();
      _listening.addAll(<StreamSubscription<Object?>>[
        player.onPositionChanged.listen((position) {
          if (mounted) setState(() => _position = position);
        }),
        player.onPlayerStateChanged.listen((state) {
          if (mounted) setState(() => _playing = state == PlayerState.playing);
        }),
        player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _position = Duration.zero);
        }),
      ]);
      return player;
    }();
    if (_source != path) {
      await player.setSource(DeviceFileSource(path));
      await player.setPlaybackRate(_rate);
      _source = path;
    }
    return player;
  }

  /// Why the sound would not play, if it would not.
  String? _trouble;

  /// Does [work] with the player, saying why if it fails.
  Future<void> _withPlayer(Future<void> Function() work) async {
    try {
      await work();
      if (_trouble != null && mounted) setState(() => _trouble = null);
    } on Object catch (error) {
      if (mounted) setState(() => _trouble = playbackTrouble(error));
    }
  }

  Future<void> _toggle(String path) => _withPlayer(() async {
    final player = await _ready(path);
    if (_playing) {
      await player.pause();
    } else {
      await player.resume();
    }
  });

  Future<void> _seek(String path, Duration to, {bool play = false}) =>
      _withPlayer(() async {
        final player = await _ready(path);
        setState(() => _position = to);
        await player.seek(to);
        if (play && !_playing) await player.resume();
      });

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await _player?.setPlaybackRate(rate);
  }

  Future<void> _save(String path, String title) async {
    final location = await getSaveLocation(
      suggestedName: '${title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}.wav',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'WAV', extensions: <String>['wav']),
      ],
    );
    if (location == null) return;
    final to = location.path.toLowerCase().endsWith('.wav')
        ? location.path
        : '${location.path}.wav';
    await File(path).copy(to);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showMessage('Saved to $to');
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final item = widget.item;
    final episode = _episode;
    if (episode == null) return const SizedBox.shrink();
    final session = ref.read(aiSessionProvider(widget.scope).notifier);
    final speaking = ref.watch(
      aiSessionProvider(widget.scope).select((s) => s.podcasts[item.id]),
    );
    final folder = ref.watch(podcastFolderProvider).value;
    final path = folder == null || !episode.spoken
        ? null
        : p.join(folder, episode.audio);
    final here = path != null && File(path).existsSync();
    final current = here && (_playing || _position > Duration.zero)
        ? episode.lineAt(_position)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudyHeader(
          label: 'Podcast',
          title: item.title,
          subtitle: <String>[
            if (episode.duration > Duration.zero) clockOf(episode.duration),
            'made ${whenOf(item.createdAt)}',
            if (episode.models.isNotEmpty) 'by ${episode.models.join(' and ')}',
            if (episode.voice.isNotEmpty) 'voiced by ${episode.voice}',
            ?costNote(AiSession.costOf(item.usage)),
          ].join('  ·  '),
          actions: <Widget>[
            if (here)
              SmallButton(
                'Save audio…',
                tooltip: 'Save it as a WAV file, to hear anywhere',
                onPressed: () => unawaited(_save(path, item.title)),
              ),
            SmallButton(
              'Rename',
              onPressed: () async {
                final title = await askName(context, item.title);
                if (title != null) await session.renameItem(item.id, title);
              },
            ),
            SmallButton(
              'Delete',
              onPressed: () async {
                if (await confirmStep(
                  context,
                  'Delete this podcast?',
                  'Its sound and transcript go with it. You can make '
                      'another at any time.',
                )) {
                  await _release();
                  await session.deleteItem(item.id);
                }
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: switch ((speaking, here)) {
            (final PodcastProgress progress, _) => _Under(
              progress: progress,
              onStop: () => unawaited(session.stopPodcast(item.id)),
            ),
            (null, true) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PlayerBar(
                  playing: _playing,
                  position: _position,
                  duration: episode.duration,
                  rate: _rate,
                  onToggle: () => unawaited(_toggle(path!)),
                  onSeek: (to) => unawaited(_seek(path!, to)),
                  onRate: (rate) => unawaited(_setRate(rate)),
                ),
                if (_trouble case final trouble?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      trouble,
                      style: TextStyle(fontSize: 12, color: tones.text),
                    ),
                  ),
              ],
            ),
            (null, false) => Callout(
              colour: tones.emphasis,
              fill: tones.lift,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      episode.spoken
                          ? 'Its sound is not on this computer. Speak it again '
                                'from its transcript.'
                          : 'It is written, but not spoken yet.',
                      style: TextStyle(fontSize: 12.5, color: tones.text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PillButton(
                    'Speak it',
                    lit: true,
                    onPressed: () => unawaited(session.speakPodcast(item.id)),
                  ),
                ],
              ),
            ),
          },
        ),
        Expanded(
          child: _Transcript(
            episode: episode,
            lines: episode.lines,
            current: current,
            onLine: here && speaking == null
                ? (i) => unawaited(_seek(path, episode.starts[i], play: true))
                : null,
          ),
        ),
      ],
    );
  }
}

/// A podcast being made: how far it has got, and as much of it as is
/// planned and written, laid out as it will be.
class PodcastDraftPage extends ConsumerWidget {
  const PodcastDraftPage({
    required this.scope,
    required this.profile,
    required this.progress,
    super.key,
  });

  final NoteLink scope;
  final EpisodeProfile profile;
  final PodcastProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final settings = ref.watch(aiSettingsProvider);
    final cast = settings.castOf(profile.speakersId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudyHeader(
          label: 'Podcast',
          title: 'Making “${profile.name}”',
          subtitle: <String>[
            'from “${info?.title ?? ''}”',
            if (cast != null)
              'with ${cast.speakers.map((s) => s.name).join(' and ')}',
            '— look at anything else meanwhile',
          ].join('  '),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _Under(
            progress: progress,
            onStop: () => unawaited(
              ref
                  .read(aiSessionProvider(scope).notifier)
                  .stopPodcast(profile.id),
            ),
          ),
        ),
        Expanded(
          child: _Transcript(outline: progress.outline, lines: progress.lines),
        ),
      ],
    );
  }
}

/// How making or speaking a podcast is coming along, and a way to stop it.
class _Under extends StatelessWidget {
  const _Under({required this.progress, required this.onStop});

  final PodcastProgress progress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final steps = progress.steps;
    // Writing takes about as long as speaking: half the way each.
    final share = switch (progress.stage) {
      PodcastStage.gathering || PodcastStage.outlining => 0.0,
      PodcastStage.writing => 0.05 + 0.45 * progress.step / steps,
      PodcastStage.speaking =>
        steps == 0 ? 0.5 : 0.5 + 0.5 * progress.step / steps,
      PodcastStage.done => 1.0,
    };
    final cost = costNote(progress.cost);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                <String>[
                  if (progress.activity.isEmpty)
                    'Speaking'
                  else
                    progress.activity,
                  ?cost,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: tones.text),
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) => Busy(
                  width: constraints.maxWidth,
                  value: share == 0 ? null : share,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: onStop, child: const Text('Stop')),
      ],
    );
  }
}

/// Play and pause, where in the episode it is, and how fast it speaks.
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.playing,
    required this.position,
    required this.duration,
    required this.rate,
    required this.onToggle,
    required this.onSeek,
    required this.onRate,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final double rate;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onRate;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final total = duration.inMilliseconds;
    final time = TextStyle(
      fontSize: 11.5,
      color: tones.muted,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
      decoration: BoxDecoration(
        color: tones.lift,
        borderRadius: Corners.controlRadius,
      ),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: playing ? 'Pause' : 'Play',
            child: TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                shape: const StadiumBorder(),
                minimumSize: const Size(64, 28),
                backgroundColor: tones.emphasis,
                foregroundColor: tones.onEmphasis,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                playing ? 'Pause' : 'Play',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(clockOf(position), style: time),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => LevelSlider(
                label: 'Where in the podcast',
                width: constraints.maxWidth,
                value: total == 0
                    ? 0
                    : (position.inMilliseconds / total).clamp(0.0, 1.0),
                onChanged: (level) =>
                    onSeek(Duration(milliseconds: (level * total).round())),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(clockOf(duration), style: time),
          const SizedBox(width: 8),
          ChoiceRow<double>(
            choices: _rates,
            selected: rate,
            labelOf: (rate) =>
                '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2).replaceAll(RegExp(r'0$'), '')}×',
            onSelected: onRate,
          ),
        ],
      ),
    );
  }
}

/// What is said, segment by segment under each one's name, each line under
/// its speaker's: [current] marked, and a line pressed [onLine].
class _Transcript extends StatefulWidget {
  const _Transcript({
    required this.lines,
    this.episode,
    this.outline,
    this.current,
    this.onLine,
  });

  final PodcastEpisode? episode;
  final List<PodcastSegment>? outline;
  final List<PodcastLine> lines;
  final int? current;
  final void Function(int line)? onLine;

  @override
  State<_Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<_Transcript> {
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(_Transcript old) {
    super.didUpdateWidget(old);
    // The line being said is kept in view as it moves on.
    final current = widget.current;
    if (current != null && current != old.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final line = _keys[current]?.currentContext;
        if (line != null && line.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              line,
              alignment: 0.3,
              duration: context.motion.of(Motion.settle),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final outline = widget.episode?.outline ?? widget.outline ?? const [];
    final lines = widget.lines;
    final speakers = <String>{
      for (final speaker
          in widget.episode?.speakers ?? const <PodcastSpeaker>[])
        speaker.name,
      for (final line in lines) line.speaker,
    }.toList();
    Color colourOf(String speaker) =>
        speakers.indexOf(speaker).isEven ? tones.emphasis : tones.muted;

    final children = <Widget>[];
    for (final (s, segment) in outline.indexed) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: s == 0 ? 0 : 18, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SmallCaps('Part ${s + 1}', color: tones.muted),
              const SizedBox(height: 2),
              Text(
                segment.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (segment.description.isNotEmpty &&
                  lines.every((l) => l.segment != s))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    segment.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: tones.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      for (final (i, line) in lines.indexed) {
        if (line.segment != s) continue;
        children.add(
          _Line(
            key: _keys[i] ??= GlobalKey(),
            line: line,
            colour: colourOf(line.speaker),
            current: widget.current == i,
            onTap: widget.onLine == null ? null : () => widget.onLine!(i),
          ),
        );
      }
    }
    if (outline.isEmpty) {
      for (final (i, line) in lines.indexed) {
        children.add(
          _Line(
            key: _keys[i] ??= GlobalKey(),
            line: line,
            colour: colourOf(line.speaker),
            current: widget.current == i,
            onTap: widget.onLine == null ? null : () => widget.onLine!(i),
          ),
        );
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: tones.base,
              border: Border.all(color: tones.line),
              borderRadius: Corners.panelRadius,
            ),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of a transcript: who says it, and what — marked while it is
/// said, and pressed to hear it from there.
class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.colour,
    required this.current,
    required this.onTap,
    super.key,
  });

  final PodcastLine line;
  final Color colour;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final body = Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: current ? tones.selection : null,
        borderRadius: Corners.controlRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: current
                ? const Drop()
                : const SizedBox(width: 3, height: 14),
          ),
          SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                line.speaker,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colour,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: tones.text),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Tooltip(
      message: 'Hear it from here',
      waitDuration: const Duration(milliseconds: 900),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: body),
      ),
    );
  }
}

/// The overview's lines for podcasts: each episode profile, to make one
/// by, and the episodes made.
class PodcastRows extends ConsumerWidget {
  const PodcastRows({required this.scope, super.key});

  final NoteLink scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final state = ref.watch(aiSessionProvider(scope));
    final session = ref.read(aiSessionProvider(scope).notifier);
    final settings = ref.watch(aiSettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (settings.voices.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: Text(
              'Add a voice provider under Podcasts in the AI settings to '
              'hear your notes as a conversation.',
              style: TextStyle(fontSize: 12, height: 1.4, color: tones.muted),
            ),
          ),
        for (final profile in settings.episodes)
          _ProfileRow(
            key: ValueKey<String>('podcast ${profile.id}'),
            profile: profile,
            cast: settings.castOf(profile.speakersId),
            making: state.podcasts[profile.id],
            onShow: () => session.showPodcast(profile.id),
            onMake: settings.voices.isEmpty
                ? null
                : () => unawaited(session.makePodcast(profile)),
          ),
        for (final item in state.episodes)
          if (PodcastEpisode.fromJson(item.body) case final episode?)
            _EpisodeRow(
              key: ValueKey<String>(item.id),
              title: item.title,
              trailing: <String>[
                if (state.podcasts.containsKey(item.id))
                  'Being spoken…'
                else if (episode.duration > Duration.zero)
                  clockOf(episode.duration)
                else
                  'Not spoken',
                whenOf(item.createdAt),
              ].join('  ·  '),
              onTap: () => session.openItem(item.id),
            ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.cast,
    required this.making,
    required this.onShow,
    required this.onMake,
    super.key,
  });

  final EpisodeProfile profile;
  final SpeakerProfile? cast;
  final PodcastProgress? making;
  final VoidCallback onShow;
  final VoidCallback? onMake;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final making = this.making;
    final who = cast?.speakers.map((s) => s.name).join(' and ') ?? '';
    return Tooltip(
      message: profile.briefing,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: making == null ? onMake : onShow,
        borderRadius: Corners.controlRadius,
        hoverColor: tones.veil,
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: <Widget>[
                Mark(MarkShape.chevronRight, size: 10, color: tones.faint),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    making != null
                        ? making.activity
                        : who.isEmpty
                        ? '${profile.segments} parts'
                        : '$who  ·  ${profile.segments} parts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tones.muted),
                  ),
                ),
                if (making != null)
                  const Busy(width: 32)
                else
                  PillButton('Make', lit: onMake != null, onPressed: onMake),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.title,
    required this.trailing,
    required this.onTap,
    super.key,
  });

  final String title;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return InkWell(
      onTap: onTap,
      borderRadius: Corners.controlRadius,
      hoverColor: tones.veil,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 7, 6, 7),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Text(trailing, style: TextStyle(fontSize: 12, color: tones.muted)),
          ],
        ),
      ),
    );
  }
}

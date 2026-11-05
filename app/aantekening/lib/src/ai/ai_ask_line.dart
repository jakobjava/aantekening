part of 'ai_view.dart';

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

  void _send() {
    final question = _text.text.trim();
    if (question.isEmpty) return;
    final web = searchesWeb(ref, widget.scope);
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
    final answering = ref.watch(
      aiSessionProvider(widget.scope).select((s) => s.pending != null),
    );
    final info = ref.watch(aiScopeInfoProvider(widget.scope)).value;
    final model = ref.watch(aiModelProvider).value;
    final search = ref.watch(webSearchProvider);
    final available = webAvailable(model, search);
    final web =
        (ref.watch(webChoiceProvider(widget.scope)) ??
            ref.watch(aiSettingsProvider.select((s) => s.searchWeb))) &&
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
                          ? ref
                                .read(webChoiceProvider(widget.scope).notifier)
                                .choose
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
                  if (answering)
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

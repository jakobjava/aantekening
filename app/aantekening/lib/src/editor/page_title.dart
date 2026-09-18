/// The top of a page: its title, and the date and time beneath it.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../shell/library_actions.dart';
import 'text/text_styles.dart';

/// A page's title with its date and time beneath, at the top-left of the
/// page as in OneNote, drawn on the canvas so it moves and scales with it.
///
/// The title is the page's name, the one in the page list: renaming the page
/// there changes it here, and typing here renames the page. The date and
/// time are when the page was created until they are changed: each opens a
/// picker.
class PageTitle extends ConsumerStatefulWidget {
  const PageTitle({
    required this.pageId,
    this.highlight,
    this.onFinished,
    super.key,
  });

  final String pageId;

  /// Words to mark in the title, as a search found them.
  final SearchTerms? highlight;

  /// Called when the title is left with Enter or Escape, to give the
  /// keyboard to the page beneath it.
  final VoidCallback? onFinished;

  /// Where the title sits on the page, in page units.
  static const Frame frame = Frame(x: 40, y: 24, width: 560, height: 70);

  /// How long typing pauses before the page is renamed.
  static const Duration typingPause = Duration(milliseconds: 400);

  static const double titleSize = 20 * RichTextStyles.unitsPerPoint;

  @override
  ConsumerState<PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends ConsumerState<PageTitle> {
  final _MatchingController _title = _MatchingController();
  final FocusNode _focus = FocusNode(debugLabel: 'Page title');

  /// Held, not read through `ref`, so the last rename can be made from
  /// [dispose].
  late final LibraryActions _actions = ref.read(libraryActionsProvider);

  PageRef? _page;

  /// A title typed but not yet saved.
  String? _typed;
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
    _page = ref.read(pageProvider(widget.pageId)).value;
    _title.text = _page?.title ?? '';
    ref.listenManual<AsyncValue<PageRef?>>(
      pageProvider(widget.pageId),
      (_, next) => _showPage(next.value),
    );
    // A page just created is named first, as in OneNote.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(titleFocusProvider.notifier).take(widget.pageId)) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _save();
    _focus.dispose();
    _title.dispose();
    super.dispose();
  }

  /// Takes in the page as stored, keeping what is being typed.
  void _showPage(PageRef? page) {
    if (page == null) return;
    if (_typed == null && !_focus.hasFocus && _title.text != page.title) {
      _title.text = page.title;
    }
    setState(() => _page = page);
  }

  void _changed(String text) {
    _typed = text;
    _typing?.cancel();
    _typing = Timer(PageTitle.typingPause, _save);
  }

  void _save() {
    _typing?.cancel();
    final typed = _typed;
    if (typed == null) return;
    _typed = null;
    unawaited(_actions.renamePage(widget.pageId, typed.trim()));
  }

  void _leave() {
    final finished = widget.onFinished;
    if (finished == null) {
      _focus.unfocus();
    } else {
      finished();
    }
  }

  Future<void> _pickDate(DateTime date) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    await _actions.setPageDate(
      widget.pageId,
      DateTime(picked.year, picked.month, picked.day, date.hour, date.minute),
    );
  }

  Future<void> _pickTime(DateTime date) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
    );
    if (picked == null) return;
    await _actions.setPageDate(
      widget.pageId,
      DateTime(date.year, date.month, date.day, picked.hour, picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final localizations = MaterialLocalizations.of(context);
    final date = page == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(page.createdAt);
    _title.terms = widget.highlight;

    const muted = TextStyle(fontSize: 12.5, color: RichTextStyles.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: RichTextStyles.titleRule)),
          ),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            // Keys typed into the title are the title's: none of them reach
            // the page, where a letter picks a tool and Delete removes what
            // is selected. Editing keys are handled just below.
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _leave();
                return KeyEventResult.handled;
              }
              return KeyEventResult.skipRemainingHandlers;
            },
            child: DefaultTextEditingShortcuts(
              child: TextField(
                controller: _title,
                focusNode: _focus,
                style: const TextStyle(
                  fontSize: PageTitle.titleSize,
                  fontWeight: FontWeight.w300,
                  color: RichTextStyles.ink,
                  height: 1.3,
                ),
                cursorColor: RichTextStyles.ink,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Title',
                  hintStyle: TextStyle(color: RichTextStyles.inkMuted),
                ),
                onChanged: _changed,
                onSubmitted: (_) => _leave(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (date != null)
          // Transparent, so the pickers' buttons show their ink on the paper.
          Material(
            type: MaterialType.transparency,
            child: Row(
              children: <Widget>[
                _DateButton(
                  label: localizations.formatFullDate(date),
                  tooltip: 'Change the date',
                  style: muted,
                  onPressed: () => _pickDate(date),
                ),
                const SizedBox(width: 12),
                _DateButton(
                  label: localizations.formatTimeOfDay(
                    TimeOfDay.fromDateTime(date),
                    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                      context,
                    ),
                  ),
                  tooltip: 'Change the time',
                  style: muted,
                  onPressed: () => _pickTime(date),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.tooltip,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final TextStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text(label, style: style),
      ),
    ),
  );
}

/// A title field that marks the words a search found, except while the
/// input method is composing.
class _MatchingController extends TextEditingController {
  SearchTerms? terms;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final matches = terms?.matchesIn(text) ?? const <TextMatch>[];
    if (matches.isEmpty || (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    const found = TextStyle(backgroundColor: RichTextStyles.searchMatch);
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in matches) {
      spans
        ..add(TextSpan(text: text.substring(at, match.start)))
        ..add(
          TextSpan(text: text.substring(match.start, match.end), style: found),
        );
      at = match.end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

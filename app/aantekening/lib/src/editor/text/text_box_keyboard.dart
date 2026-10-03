part of 'text_box_editor.dart';

/// The keys the box answers itself, before the input method sees them.
extension _Keyboard on TextBoxEditorState {
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.isEditing) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return _isTextKey(event)
          ? KeyEventResult.skipRemainingHandlers
          : KeyEventResult.ignored;
    }
    // While the input method is composing — a dead key, an accent, an East
    // Asian candidate — every key belongs to it.
    if (_input.composing.isValid && !_input.composing.isCollapsed) {
      return KeyEventResult.skipRemainingHandlers;
    }

    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    final control = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    // AltGr arrives as Ctrl+Alt on Windows. On layouts where it types
    // characters — {, }, [, ], \ and @ on German keyboards, all of which LaTeX
    // needs — the character must win over any shortcut.
    if (control && alt && _producesCharacter(event)) {
      return KeyEventResult.skipRemainingHandlers;
    }

    final handled = _handleKey(
      key,
      event,
      shift: shift,
      alt: alt,
      control: control,
    );
    if (handled != null) return handled;

    if (control || (alt && !_producesCharacter(event))) {
      // Unclaimed shortcuts — Ctrl+S, Ctrl+Z — belong to the page.
      _undoSteps.breakStep();
      return KeyEventResult.ignored;
    }
    // Anything else is text, delivered through the input method. Stopping it
    // here keeps the canvas's single-letter tool shortcuts from seeing it.
    return KeyEventResult.skipRemainingHandlers;
  }

  static bool _producesCharacter(KeyEvent event) {
    final character = event.character;
    return character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 0x20 &&
        character.codeUnitAt(0) != 0x7F;
  }

  static bool _isTextKey(KeyEvent event) => _producesCharacter(event);

  static bool _isFormulaToggle(
    LogicalKeyboardKey key,
    KeyEvent event,
    bool alt,
    bool control,
  ) =>
      (alt &&
          !control &&
          (key == LogicalKeyboardKey.equal || event.character == '=')) ||
      (control && key == LogicalKeyboardKey.keyM);

  KeyEventResult? _handleKey(
    LogicalKeyboardKey key,
    KeyEvent event, {
    required bool shift,
    required bool alt,
    required bool control,
  }) {
    const handled = KeyEventResult.handled;

    // Ctrl+Shift+M switches the syntax formulas are typed in, translating
    // the one being edited.
    if (control && shift && key == LogicalKeyboardKey.keyM) {
      _chooseSyntax(
        _preferredSyntax == MathMode.latex ? MathMode.linear : MathMode.latex,
      );
      return handled;
    }

    // Formula toggles: Alt+= as in OneNote (Alt+Shift+0 on a German
    // keyboard, which is why the character is checked too), or Ctrl+M on any
    // layout.
    if (_isFormulaToggle(key, event, alt, control)) {
      toggleFormula();
      return handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_formula != null) {
        _closeFormula(emit: true, onwards: true);
      } else {
        widget.onExit?.call();
      }
      return handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_formula != null) {
        _closeFormula(emit: true, onwards: true);
      } else if (control) {
        _toggleChecked(_selection.extent.block);
      } else {
        _paragraphBreak();
      }
      return handled;
    }

    // Ctrl+Tab goes on to the window, to change tabs.
    if (key == LogicalKeyboardKey.tab && !control) {
      if (_formula != null) {
        _moveToSlot(forward: !shift);
      } else {
        _tab(backward: shift);
      }
      return handled;
    }

    if (key == LogicalKeyboardKey.backspace) {
      _delete(forward: false, word: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _delete(forward: true, word: control);
      return handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveHorizontally(-1, extend: shift, word: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveHorizontally(1, extend: shift, word: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveVertically(-1, extend: shift);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveVertically(1, extend: shift);
      return handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveToLineEdge(start: true, extend: shift, wholeBox: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveToLineEdge(start: false, extend: shift, wholeBox: control);
      return handled;
    }

    if (!control) return null;

    switch (key) {
      case LogicalKeyboardKey.keyA:
        // With nothing left to select in the box, the page takes Ctrl+A and
        // selects everything on it.
        return _selectAll() ? handled : null;
      case LogicalKeyboardKey.keyC:
        unawaited(_copy());
        return handled;
      case LogicalKeyboardKey.keyX:
        unawaited(_copy(cut: true));
        return handled;
      case LogicalKeyboardKey.keyV:
        unawaited(_paste(textOnly: shift));
        return handled;
      case LogicalKeyboardKey.keyB:
        toggleMark(MarkKind.bold);
        return handled;
      case LogicalKeyboardKey.keyI:
        toggleMark(MarkKind.italic);
        return handled;
      case LogicalKeyboardKey.keyU:
        toggleMark(MarkKind.underline);
        return handled;
      case LogicalKeyboardKey.minus when !alt:
        toggleMark(MarkKind.strikethrough);
        return handled;
      case LogicalKeyboardKey.keyE when !shift:
        toggleMark(MarkKind.code);
        return handled;
      case LogicalKeyboardKey.keyH when shift:
        toggleMark(MarkKind.highlight);
        return handled;
      case LogicalKeyboardKey.period:
        toggleBlockKind(TextBlockKind.bulleted);
        return handled;
      case LogicalKeyboardKey.slash:
        toggleBlockKind(TextBlockKind.numbered);
        return handled;
      case LogicalKeyboardKey.digit1 when !alt:
        toggleBlockKind(TextBlockKind.todo);
        return handled;
      case LogicalKeyboardKey.digit1 when alt:
        toggleBlockKind(TextBlockKind.heading1);
        return handled;
      case LogicalKeyboardKey.digit2 when alt:
        toggleBlockKind(TextBlockKind.heading2);
        return handled;
      case LogicalKeyboardKey.digit3 when alt:
        toggleBlockKind(TextBlockKind.heading3);
        return handled;
      case LogicalKeyboardKey.keyN when shift:
        // Normal text, as in OneNote. Toggling to a paragraph always lands on
        // a paragraph.
        toggleBlockKind(TextBlockKind.paragraph);
        return handled;
    }
    return null;
  }

  /// Selects everything in the box, or in the formula being edited.
  ///
  /// Returns false where there was nothing to select — an empty box, or one
  /// already selected whole — so that the caret blinking in a box with
  /// nothing in it does not swallow Ctrl+A.
  bool _selectAll() {
    final formula = _formula;
    final span = formula == null ? null : _formulaSpan(formula)!;
    final whole = span == null
        ? _wholeBox
        : RichSelection(
            RichPosition(formula!.block, span.start),
            RichPosition(formula.block, span.end),
          );
    if (whole.isCollapsed || whole == _selection) return false;
    _select(whole);
    return true;
  }

  /// Everything in the box, from its first block to the end of its last.
  RichSelection get _wholeBox =>
      RichSelection(RichPosition.zero, RichTextEditing.endOf(_blocks));
}

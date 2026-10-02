/// The connection between a text box and the platform's input method.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where the text the input method sees is on screen, for it to place its
/// candidate window and handles: the box it is laid out in, that box's
/// transform to the screen, and the caret in it.
typedef InputGeometry = ({Size size, Matrix4 transform, Rect? caret});

/// A text box's connection to the input method, through the delta model: it
/// tells the input method what the box holds where the caret is, and hands
/// the input method's edits back to the box.
///
/// The box decides what the input method sees ([valueOf]) — the paragraph
/// with the caret, or the source of the formula being typed — and applies
/// each edit to its own text ([onReplace], [onSelect]).
class TextBoxInput implements DeltaTextInputClient {
  TextBoxInput({
    required this.valueOf,
    required this.configuration,
    required this.geometry,
    required this.accepts,
    required this.onReplace,
    required this.onSelect,
    required this.onComposed,
  });

  /// The text the input method sees, with the selection, and [composing]
  /// where it still fits.
  final TextEditingValue Function(TextRange composing) valueOf;

  /// How the input method is to treat the text.
  final TextInputConfiguration Function() configuration;

  /// Where the text is on screen, once laid out.
  final InputGeometry? Function() geometry;

  /// Whether edits are taken now: while the box is being edited.
  final bool Function() accepts;

  /// Replaces [TextRange] of the text the input method sees with the text
  /// given.
  final void Function(TextRange range, String text) onReplace;

  /// Moves the selection, in the text the input method sees.
  final void Function(TextSelection selection) onSelect;

  /// Called after a batch of edits, once [composing] is known.
  final VoidCallback onComposed;

  TextInputConnection? _connection;
  TextEditingValue _value = TextEditingValue.empty;

  /// Text the input method is still composing, in the text it sees.
  TextRange get composing => _composing;
  TextRange _composing = TextRange.empty;

  /// Opens the connection, unless it is open.
  void open() {
    if (_connection?.attached ?? false) return;
    _value = valueOf(_composing);
    _connection = TextInput.attach(this, configuration())
      ..show()
      ..setEditingState(_value);
    _placeLater();
  }

  /// Closes the connection, forgetting what was being composed.
  void close() {
    _connection?.close();
    _connection = null;
    _composing = TextRange.empty;
  }

  /// Tells the input method that the text, the selection or where they are
  /// have changed.
  void sync() {
    final connection = _connection;
    if (connection == null || !connection.attached) return;
    final value = valueOf(_composing);
    if (value != _value) {
      _value = value;
      connection.setEditingState(value);
    }
    _placeLater();
  }

  /// Tells the input method that how it is to treat the text has changed:
  /// a formula opened or closed.
  void reconfigure() => _connection?.updateConfig(configuration());

  /// Tells the input method where the text is once the frame is laid out.
  void _placeLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connection = _connection;
      if (connection == null || !connection.attached) return;
      final placed = geometry();
      if (placed == null) return;
      connection.setEditableSizeAndTransform(placed.size, placed.transform);
      if (placed.caret case final caret?) connection.setCaretRect(caret);
    });
  }

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    // Only used without the delta model, which this client never requests.
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (!accepts()) return;
    for (final delta in deltas) {
      _value = delta.apply(_value);
      switch (delta) {
        case TextEditingDeltaInsertion():
          onReplace(
            TextRange.collapsed(delta.insertionOffset),
            delta.textInserted,
          );
        case TextEditingDeltaDeletion():
          onReplace(delta.deletedRange, '');
        case TextEditingDeltaReplacement():
          onReplace(delta.replacedRange, delta.replacementText);
        case TextEditingDeltaNonTextUpdate():
          onSelect(delta.selection);
      }
      _composing = delta.composing;
    }
    onComposed();
    sync();
  }

  @override
  void performAction(TextInputAction action) {
    // Enter arrives as a newline inserted through the delta model.
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    _composing = TextRange.empty;
  }

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  bool onFocusReceived() => false;

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void showToolbar() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {}
}

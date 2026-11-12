/// What the benchmarks drive the app with, as a person's hands would: a
/// mouse, a touchpad and a pen, by the pointer events they send; the
/// keyboard, by the key events the engine hands the window; and what is
/// typed, by the messages the system's input method sends.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aantekening/src/editor/trackpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'measuring.dart';

/// Sends the page what a mouse, a touchpad and a pen would. The events are
/// handed to the window as the engine's are once it has read them
/// ([GestureBinding.handlePointerEvent]), and go on from there as a
/// person's do.
class Input {
  Input(this.view) {
    _send(PointerAddedEvent(position: _at, device: _mouse));
    _send(PointerHoverEvent(position: _at, device: _mouse));
  }

  final Rect view;
  final Stopwatch _clock = Stopwatch()..start();
  static const int _mouse = 1;
  static const int _touchpad = 2;
  static const int _pen = 3;
  int _gesture = 100;
  bool _penThere = false;

  /// How often a touchpad reports.
  static const Duration _report = Duration(milliseconds: 8);

  Offset get _at => view.center;
  Duration get _time => _clock.elapsed;

  /// The touchpad's reports are scaled as the platform scales them, so the
  /// page moves as far as asked.
  final double _panScale = trackpadPanScale();

  void _send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);

  /// Sends [event], and says how many microseconds the window took over
  /// it before it could do anything else.
  int _timed(PointerEvent event) {
    final began = now();
    _send(event);
    return now() - began;
  }

  void wheel(Offset delta) => _send(
    PointerScrollEvent(
      timeStamp: _time,
      position: _at,
      device: _mouse,
      scrollDelta: delta,
    ),
  );

  void holdControl({required bool down}) {
    const physical = PhysicalKeyboardKey.controlLeft;
    const logical = LogicalKeyboardKey.controlLeft;
    HardwareKeyboard.instance.handleKeyEvent(
      down
          ? KeyDownEvent(
              physicalKey: physical,
              logicalKey: logical,
              timeStamp: _time,
            )
          : KeyUpEvent(
              physicalKey: physical,
              logicalKey: logical,
              timeStamp: _time,
            ),
    );
  }

  /// The mouse moved to [at], no button held.
  void hover(Offset at) =>
      _send(PointerHoverEvent(timeStamp: _time, position: at, device: _mouse));

  /// The mouse's button pressed at [at] and let go there.
  Future<void> click(Offset at) async {
    final pointer = _gesture++;
    hover(at);
    _send(
      PointerDownEvent(
        timeStamp: _time,
        position: at,
        kind: PointerDeviceKind.mouse,
        device: _mouse,
        pointer: pointer,
      ),
    );
    await wait(const Duration(milliseconds: 40));
    _send(
      PointerUpEvent(
        timeStamp: _time,
        position: at,
        kind: PointerDeviceKind.mouse,
        device: _mouse,
        pointer: pointer,
      ),
    );
  }

  /// A press at [from] dragged by [distance], evenly over [duration], then
  /// let go: a finger's, or with [kind] the mouse's. [onMove] is told how
  /// many microseconds the window took over each move, and [onLift] over
  /// the letting go.
  Future<void> drag(
    Offset from,
    Offset distance,
    Duration duration, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
    void Function(int microseconds)? onMove,
    void Function(int microseconds)? onLift,
  }) async {
    final pointer = _gesture++;
    if (kind == PointerDeviceKind.mouse) hover(from);
    _send(
      PointerDownEvent(
        timeStamp: _time,
        position: from,
        kind: kind,
        device: _mouse,
        pointer: pointer,
      ),
    );
    final steps = duration.inMicroseconds ~/ _report.inMicroseconds;
    var at = from;
    for (var step = 1; step <= steps; step++) {
      await wait(_report);
      final next = from + distance * (step / steps);
      final took = _timed(
        PointerMoveEvent(
          timeStamp: _time,
          position: next,
          delta: next - at,
          kind: kind,
          device: _mouse,
          pointer: pointer,
        ),
      );
      onMove?.call(took);
      at = next;
    }
    final took = _timed(
      PointerUpEvent(
        timeStamp: _time,
        position: at,
        kind: kind,
        device: _mouse,
        pointer: pointer,
      ),
    );
    onLift?.call(took);
  }

  /// The pen put down at [at], pressed as hard as [pressure] of what it
  /// can tell; how many microseconds the window took over it.
  int penDown(Offset at, double pressure) {
    if (!_penThere) {
      _penThere = true;
      _send(
        PointerAddedEvent(
          timeStamp: _time,
          position: at,
          kind: PointerDeviceKind.stylus,
          device: _pen,
        ),
      );
    }
    // Over the paper before it touches it, as a pen is.
    _send(
      PointerHoverEvent(
        timeStamp: _time,
        position: at,
        kind: PointerDeviceKind.stylus,
        device: _pen,
      ),
    );
    return _timed(
      PointerDownEvent(
        timeStamp: _time,
        position: at,
        kind: PointerDeviceKind.stylus,
        device: _pen,
        pointer: ++_gesture,
        pressure: pressure,
        pressureMin: 0,
      ),
    );
  }

  /// The pen, down, moved [by] to [at].
  int penMove(Offset at, Offset by, double pressure) => _timed(
    PointerMoveEvent(
      timeStamp: _time,
      position: at,
      delta: by,
      kind: PointerDeviceKind.stylus,
      device: _pen,
      pointer: _gesture,
      pressure: pressure,
      pressureMin: 0,
    ),
  );

  /// The pen lifted at [at].
  int penUp(Offset at) => _timed(
    PointerUpEvent(
      timeStamp: _time,
      position: at,
      kind: PointerDeviceKind.stylus,
      device: _pen,
      pointer: _gesture,
      pressureMin: 0,
    ),
  );

  /// Two fingers moving the page by [distance] over [duration], fastest in
  /// the middle, lifted while still moving, so the page coasts on.
  Future<void> swipe(Offset distance, Duration duration) async {
    final pointer = _gesture++;
    _send(
      PointerPanZoomStartEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
    final steps = duration.inMicroseconds ~/ _report.inMicroseconds;
    var pan = Offset.zero;
    for (var step = 1; step <= steps; step++) {
      await wait(_report);
      // Speeding up, then slowing a little before the fingers lift.
      final t = step / steps;
      final along =
          (1 - math.cos(math.pi * t * 0.85)) / (1 - math.cos(math.pi * 0.85));
      final next = distance * along / _panScale;
      _send(
        PointerPanZoomUpdateEvent(
          timeStamp: _time,
          position: _at,
          device: _touchpad,
          pointer: pointer,
          pan: next,
          panDelta: next - pan,
        ),
      );
      pan = next;
    }
    _send(
      PointerPanZoomEndEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
  }

  /// Two fingers pinching through [scales], evenly over [duration].
  Future<void> pinch(List<double> scales, Duration duration) async {
    final pointer = _gesture++;
    _send(
      PointerPanZoomStartEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
    final steps = duration.inMicroseconds ~/ _report.inMicroseconds;
    for (var step = 1; step <= steps; step++) {
      await wait(_report);
      final along = step / steps * (scales.length - 1);
      final from = math.min(along.floor(), scales.length - 2);
      final part = along - from;
      // Evenly in the logarithm, as fingers spread.
      final scale = math.exp(
        math.log(scales[from]) * (1 - part) + math.log(scales[from + 1]) * part,
      );
      _send(
        PointerPanZoomUpdateEvent(
          timeStamp: _time,
          position: _at,
          device: _touchpad,
          pointer: pointer,
          scale: scale,
        ),
      );
    }
    _send(
      PointerPanZoomEndEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
  }
}

/// Hands the window a message on a channel of the engine's, and [answered]
/// its answer.
typedef Deliver = void Function(
  String channel,
  ByteData? message,
  ui.PlatformMessageResponseCallback? answered,
);

/// As the engine hands the window a message: into the buffers the
/// channels are read from.
void _asTheEngine(
  String channel,
  ByteData? message,
  ui.PlatformMessageResponseCallback? answered,
) => ServicesBinding.instance.channelBuffers.push(
  channel,
  message,
  answered ?? (_) {},
);

/// Presses keys as a keyboard on Linux does: each is handed to the window
/// twice over, as the engine hands it — as key data, and as GTK's own
/// event on the key channel — and goes from there to whatever takes keys
/// ahead of the focus, to the focus, and to the window's shortcuts.
///
/// The keys are those of a US keyboard: a capital, or a character typed
/// with Shift there, is pressed with Shift held.
class Keys {
  /// Keys whose events reach the window as the engine's do — or, in a
  /// test, as [deliver] hands them over.
  Keys({this.deliver = _asTheEngine});

  final Deliver deliver;
  final Stopwatch _clock = Stopwatch()..start();

  static const JSONMessageCodec _codec = JSONMessageCodec();

  /// The keys that type no character, by the names the app's modes give
  /// them, and a few more.
  static final Map<String, (LogicalKeyboardKey, PhysicalKeyboardKey)> _named =
      <String, (LogicalKeyboardKey, PhysicalKeyboardKey)>{
        'Enter': (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter),
        'Esc': (LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
        'Backspace': (
          LogicalKeyboardKey.backspace,
          PhysicalKeyboardKey.backspace,
        ),
        'Delete': (LogicalKeyboardKey.delete, PhysicalKeyboardKey.delete),
        'Tab': (LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab),
        'Home': (LogicalKeyboardKey.home, PhysicalKeyboardKey.home),
        'End': (LogicalKeyboardKey.end, PhysicalKeyboardKey.end),
        '↑': (LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp),
        '↓': (LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
        '←': (LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
        '→': (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
      };

  /// The keys of a US keyboard that type a character, by the character
  /// each types alone.
  static final Map<String, PhysicalKeyboardKey> _plain =
      <String, PhysicalKeyboardKey>{
        ' ': PhysicalKeyboardKey.space,
        '-': PhysicalKeyboardKey.minus,
        '=': PhysicalKeyboardKey.equal,
        '[': PhysicalKeyboardKey.bracketLeft,
        ']': PhysicalKeyboardKey.bracketRight,
        r'\': PhysicalKeyboardKey.backslash,
        ';': PhysicalKeyboardKey.semicolon,
        "'": PhysicalKeyboardKey.quote,
        ',': PhysicalKeyboardKey.comma,
        '.': PhysicalKeyboardKey.period,
        '/': PhysicalKeyboardKey.slash,
        '`': PhysicalKeyboardKey.backquote,
        for (final (index, digit) in '1234567890'.split('').indexed)
          digit: _digits[index],
        for (final (index, letter)
            in 'abcdefghijklmnopqrstuvwxyz'.split('').indexed)
          letter: _letters[index],
      };

  static const List<PhysicalKeyboardKey> _digits = <PhysicalKeyboardKey>[
    PhysicalKeyboardKey.digit1,
    PhysicalKeyboardKey.digit2,
    PhysicalKeyboardKey.digit3,
    PhysicalKeyboardKey.digit4,
    PhysicalKeyboardKey.digit5,
    PhysicalKeyboardKey.digit6,
    PhysicalKeyboardKey.digit7,
    PhysicalKeyboardKey.digit8,
    PhysicalKeyboardKey.digit9,
    PhysicalKeyboardKey.digit0,
  ];

  static const List<PhysicalKeyboardKey> _letters = <PhysicalKeyboardKey>[
    PhysicalKeyboardKey.keyA,
    PhysicalKeyboardKey.keyB,
    PhysicalKeyboardKey.keyC,
    PhysicalKeyboardKey.keyD,
    PhysicalKeyboardKey.keyE,
    PhysicalKeyboardKey.keyF,
    PhysicalKeyboardKey.keyG,
    PhysicalKeyboardKey.keyH,
    PhysicalKeyboardKey.keyI,
    PhysicalKeyboardKey.keyJ,
    PhysicalKeyboardKey.keyK,
    PhysicalKeyboardKey.keyL,
    PhysicalKeyboardKey.keyM,
    PhysicalKeyboardKey.keyN,
    PhysicalKeyboardKey.keyO,
    PhysicalKeyboardKey.keyP,
    PhysicalKeyboardKey.keyQ,
    PhysicalKeyboardKey.keyR,
    PhysicalKeyboardKey.keyS,
    PhysicalKeyboardKey.keyT,
    PhysicalKeyboardKey.keyU,
    PhysicalKeyboardKey.keyV,
    PhysicalKeyboardKey.keyW,
    PhysicalKeyboardKey.keyX,
    PhysicalKeyboardKey.keyY,
    PhysicalKeyboardKey.keyZ,
  ];

  /// The characters typed with Shift on a US keyboard, each with the one
  /// its key types alone.
  static const Map<String, String> _shifted = <String, String>{
    '!': '1',
    '@': '2',
    '#': '3',
    r'$': '4',
    '%': '5',
    '^': '6',
    '&': '7',
    '*': '8',
    '(': '9',
    ')': '0',
    '_': '-',
    '+': '=',
    '{': '[',
    '}': ']',
    '|': r'\',
    ':': ';',
    '"': "'",
    '<': ',',
    '>': '.',
    '?': '/',
    '~': '`',
  };

  /// GTK's bits for Shift and Ctrl held.
  static const int _shiftBit = 1 << 0;
  static const int _controlBit = 1 << 2;

  /// Whether [key] is one that can be pressed: a key named as the app's
  /// modes name it, or a character a US keyboard types.
  static bool has(String key) =>
      _named.containsKey(key) ||
      _plain.containsKey(key) ||
      _shifted.containsKey(key) ||
      _plain.containsKey(key.toLowerCase());

  /// Presses [key] — a character, or a key by name: `Enter`, `Esc`, `↓` —
  /// and lets it go, with Ctrl held if [control]. Says whether the window
  /// took the press: a key it leaves goes on, on a real keyboard, to the
  /// input method.
  Future<bool> press(String key, {bool control = false}) async {
    final taken = await down(key, control: control);
    await up(key, control: control);
    return taken;
  }

  /// Presses [key] down, saying whether the window took it.
  Future<bool> down(String key, {bool control = false}) async {
    final (logical, physical, character, shift) = _keyOf(key);
    var held = 0;
    if (control) {
      await _send(
        ui.KeyEventType.down,
        LogicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.controlLeft,
        null,
        held,
      );
      held |= _controlBit;
    }
    if (shift) {
      await _send(
        ui.KeyEventType.down,
        LogicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.shiftLeft,
        null,
        held,
      );
      held |= _shiftBit;
    }
    return _send(
      ui.KeyEventType.down,
      logical,
      physical,
      control ? null : character,
      held,
    );
  }

  /// Lets [key] go, and what was held with it.
  Future<void> up(String key, {bool control = false}) async {
    final (logical, physical, _, shift) = _keyOf(key);
    var held = (control ? _controlBit : 0) | (shift ? _shiftBit : 0);
    await _send(ui.KeyEventType.up, logical, physical, null, held);
    if (shift) {
      await _send(
        ui.KeyEventType.up,
        LogicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.shiftLeft,
        null,
        held,
      );
      held &= ~_shiftBit;
    }
    if (control) {
      await _send(
        ui.KeyEventType.up,
        LogicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.controlLeft,
        null,
        held,
      );
    }
  }

  /// The key that [key] names or types: what it is, where it is on the
  /// keyboard, the character it types, and whether with Shift.
  static (LogicalKeyboardKey, PhysicalKeyboardKey, String?, bool) _keyOf(
    String key,
  ) {
    if (_named[key] case (final logical, final physical)?) {
      return (logical, physical, null, false);
    }
    final alone = _shifted[key] ?? key.toLowerCase();
    final physical = _plain[alone];
    if (physical == null) {
      throw ArgumentError.value(key, 'key', 'not a key of a US keyboard');
    }
    final shift = _shifted.containsKey(key) || key != alone;
    // A key is known by the character it types, a letter by its small one.
    final logical = LogicalKeyboardKey(
      (shift && _shifted.containsKey(key) ? key : alone).codeUnitAt(0),
    );
    return (logical, physical, key, shift);
  }

  /// Hands the window one event of a key, as the engine does, and waits
  /// for it to say whether it took it.
  Future<bool> _send(
    ui.KeyEventType type,
    LogicalKeyboardKey logical,
    PhysicalKeyboardKey physical,
    String? character,
    int held,
  ) {
    ui.PlatformDispatcher.instance.onKeyData?.call(
      ui.KeyData(
        type: type,
        timeStamp: _clock.elapsed,
        physical: physical.usbHidUsage,
        logical: logical.keyId,
        character: type == ui.KeyEventType.down ? character : null,
        synthesized: false,
      ),
    );
    final answered = Completer<bool>();
    deliver(
      SystemChannels.keyEvent.name,
      _codec.encodeMessage(<String, Object?>{
        'type': type == ui.KeyEventType.down ? 'keydown' : 'keyup',
        'keymap': 'linux',
        'toolkit': 'gtk',
        'keyCode': _gtkCodeOf(logical, character),
        'scanCode': _scanCodeOf(physical),
        'modifiers': held,
        'unicodeScalarValues': character?.runes.first ?? 0,
      }),
      (answer) {
        final decoded = _codec.decodeMessage(answer);
        answered.complete(decoded is Map && decoded['handled'] == true);
      },
    );
    return answered.future;
  }

  /// GTK's own number for the key: the character's, for one that types
  /// one, else what GTK calls the key.
  static int _gtkCodeOf(LogicalKeyboardKey logical, String? character) {
    if (character != null) return character.runes.first;
    for (final entry in kGtkToLogicalKey.entries) {
      if (entry.value == logical) return entry.key;
    }
    return logical.keyId & 0xFFFF;
  }

  /// The number Linux gives the key's place on the keyboard.
  static int _scanCodeOf(PhysicalKeyboardKey physical) {
    for (final entry in kLinuxToPhysicalKey.entries) {
      if (entry.value == physical) return entry.key;
    }
    return 0;
  }
}

/// Listens to what the app tells the system's input method — which field
/// has the keyboard, and the text it holds there — and types into that
/// field as the input method does: by the same messages, on the same
/// channel.
///
/// The app's messages reach it through [BenchBinding], which hands each on
/// to the system as it was.
class TypedText {
  /// What is typed reaches the window as the input method's messages do —
  /// or, in a test, as [deliver] hands them over.
  TypedText({this.deliver = _asTheEngine});

  final Deliver deliver;
  static const JSONMethodCodec _codec = JSONMethodCodec();

  /// The field that has the keyboard, as the app numbers it, or null while
  /// none has.
  int? client;

  /// Whether that field is told of each edit ([DeltaTextInputClient]), as
  /// a text box on the page is, rather than of its whole text after it.
  bool deltas = false;

  /// What Enter does in that field, as the app told the input method.
  String action = 'TextInputAction.done';

  /// Whether that field takes lines: Enter starts another in it.
  bool multiline = false;

  /// The text the input method has of that field, and what is picked in
  /// it — or where the caret is.
  String text = '';
  int base = 0;
  int extent = 0;

  /// Takes in a message the app sent on the text input channel.
  void sent(ByteData? message) {
    if (message == null) return;
    final MethodCall call;
    try {
      call = _codec.decodeMethodCall(message);
    } on FormatException {
      return;
    }
    final arguments = call.arguments;
    switch (call.method) {
      case 'TextInput.setClient' when arguments is List && arguments.length > 1:
        client = arguments[0] as int?;
        final configuration = arguments[1];
        if (configuration is Map) {
          deltas = configuration['enableDeltaModel'] == true;
          action = '${configuration['inputAction'] ?? action}';
          final type = configuration['inputType'];
          multiline = type is Map && type['name'] == 'TextInputType.multiline';
        }
        text = '';
        base = 0;
        extent = 0;
      case 'TextInput.setEditingState' when arguments is Map:
        text = '${arguments['text'] ?? ''}';
        base = _within(arguments['selectionBase']);
        extent = _within(arguments['selectionExtent']);
      case 'TextInput.clearClient':
        client = null;
    }
  }

  int _within(Object? offset) =>
      offset is int ? offset.clamp(0, text.length) : text.length;

  /// Types [typed] where the caret is, or over what is picked, as the
  /// input method tells the field of it; returns once the field has taken
  /// it. Does nothing, and says so, while no field has the keyboard.
  Future<bool> type(String typed) async {
    final id = client;
    if (id == null) return false;
    final from = math.min(base, extent);
    final to = math.max(base, extent);
    final before = text;
    text = before.replaceRange(from, to, typed);
    base = extent = from + typed.length;
    final selection = <String, Object?>{
      'selectionBase': base,
      'selectionExtent': extent,
      'selectionAffinity': 'TextAffinity.downstream',
      'selectionIsDirectional': false,
      'composingBase': -1,
      'composingExtent': -1,
    };
    await _send(
      deltas
          ? MethodCall(
              'TextInputClient.updateEditingStateWithDeltas',
              <Object?>[
                id,
                <String, Object?>{
                  'deltas': <Object?>[
                    <String, Object?>{
                      'oldText': before,
                      'deltaText': typed,
                      'deltaStart': from,
                      'deltaEnd': to,
                      ...selection,
                    },
                  ],
                },
              ],
            )
          : MethodCall('TextInputClient.updateEditingState', <Object?>[
              id,
              <String, Object?>{'text': text, ...selection},
            ]),
    );
    return true;
  }

  /// Does what Enter does in a field of one line, as the input method
  /// tells the field to once the window has left the key to it.
  Future<bool> perform() async {
    final id = client;
    if (id == null) return false;
    await _send(
      MethodCall('TextInputClient.performAction', <Object?>[id, action]),
    );
    return true;
  }

  Future<void> _send(MethodCall call) {
    final taken = Completer<void>();
    deliver(
      SystemChannels.textInput.name,
      _codec.encodeMethodCall(call),
      (_) => taken.complete(),
    );
    return taken.future;
  }
}

/// The binding the benchmarks run the app on: the app's own, with what the
/// app tells the input method overheard by [typed] on its way there.
class BenchBinding extends AantekeningBinding {
  /// What is typed, and into what.
  static final TypedText typed = TypedText();

  /// Starts the binding; before anything else is.
  static BenchBinding start() => BenchBinding();

  @override
  BinaryMessenger createBinaryMessenger() =>
      _Overhearing(super.createBinaryMessenger(), typed);
}

/// A messenger that tells [_typed] of each message sent on the text input
/// channel, and is otherwise the messenger it stands before.
class _Overhearing implements BinaryMessenger {
  _Overhearing(this._messenger, this._typed);

  final BinaryMessenger _messenger;
  final TypedText _typed;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == SystemChannels.textInput.name) _typed.sent(message);
    return _messenger.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _messenger.setMessageHandler(channel, handler);

  @override
  // The messenger's whole interface, this member of it with the rest.
  // ignore: deprecated_member_use
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      _messenger.handlePlatformMessage(channel, data, callback);
}

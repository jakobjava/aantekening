import 'package:aantekening/src/editor/trackpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackpadAim', () {
    PointerHoverEvent hover(Offset at) =>
        PointerHoverEvent(position: at, kind: PointerDeviceKind.mouse);
    PointerPanZoomStartEvent gesture(Offset at) =>
        PointerPanZoomStartEvent(position: at);
    PointerScrollEvent wheel(Offset at) =>
        PointerScrollEvent(position: at, scrollDelta: const Offset(0, 40));

    test('aims a gesture at the pointer, not at where it is reported', () {
      final aim = TrackpadAim()..aim(hover(const Offset(400, 300)));
      final aimed = aim.aim(gesture(const Offset(20, 40)));
      expect(aimed, isA<PointerPanZoomStartEvent>());
      expect(aimed.position, const Offset(400, 300));
    });

    test('aims scrolling at the pointer as well', () {
      final aim = TrackpadAim()..aim(hover(const Offset(400, 300)));
      final aimed = aim.aim(wheel(const Offset(20, 40)));
      expect(aimed, isA<PointerScrollEvent>());
      expect(aimed.position, const Offset(400, 300));
      expect((aimed as PointerScrollEvent).scrollDelta, const Offset(0, 40));
    });

    testWidgets('a whole gesture reaches what the pointer is over', (
      tester,
    ) async {
      // The status line, clicked last, on the left; the page on the right.
      final reached = <String>[];
      Widget side(String name) => Expanded(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerPanZoomStart: (_) => reached.add('$name start'),
          onPointerPanZoomUpdate: (_) => reached.add('$name update'),
          onPointerPanZoomEnd: (_) => reached.add('$name end'),
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: <Widget>[side('status'), side('page')]),
        ),
      );
      final status = tester.getCenter(find.byType(Listener).first);
      final page = tester.getCenter(find.byType(Listener).last);

      final aim = TrackpadAim();
      void send(PointerEvent event) =>
          tester.binding.handlePointerEvent(aim.aim(event));
      // Clicked on the status line, then moved over the page.
      send(hover(status));
      send(hover(page));
      // The gesture, reported where the click was.
      send(PointerPanZoomStartEvent(pointer: 7, position: status));
      for (var i = 1; i <= 2; i++) {
        send(
          PointerPanZoomUpdateEvent(
            pointer: 7,
            position: status,
            scale: 1 + i / 10,
          ),
        );
      }
      send(PointerPanZoomEndEvent(pointer: 7, position: status));

      expect(reached, <String>[
        'page start',
        'page update',
        'page update',
        'page end',
      ]);
    });

    test('a scroll does not say where the pointer is', () {
      final aim = TrackpadAim()
        ..aim(hover(const Offset(400, 300)))
        ..aim(wheel(const Offset(20, 40)));
      expect(aim.aim(gesture(Offset.zero)).position, const Offset(400, 300));
    });

    test('leaves a gesture alone until the pointer has been somewhere', () {
      final reported = gesture(const Offset(20, 40));
      expect(identical(TrackpadAim().aim(reported), reported), isTrue);
    });

    test('forgets the pointer once it has left', () {
      final aim = TrackpadAim()
        ..aim(hover(const Offset(400, 300)))
        ..aim(const PointerRemovedEvent(kind: PointerDeviceKind.mouse));
      expect(
        aim.aim(gesture(const Offset(20, 40))).position,
        const Offset(20, 40),
      );
    });

    test('leaves the rest of a gesture where it says it is', () {
      final aim = TrackpadAim()..aim(hover(const Offset(400, 300)));
      const update = PointerPanZoomUpdateEvent(position: Offset(20, 40));
      expect(identical(aim.aim(update), update), isTrue);
      expect(
        aim.aim(gesture(const Offset(20, 40))).position,
        const Offset(400, 300),
        reason: 'an update says nothing about where the pointer is',
      );
    });
  });

  group('trackpadPanScale', () {
    test('is 1 away from Linux', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.android,
      ]) {
        expect(
          trackpadPanScale(
            platform: platform,
            environment: const <String, String>{},
          ),
          1,
        );
      }
    });

    test('undoes the Linux embedder multiplier', () {
      expect(
        trackpadPanScale(
          platform: TargetPlatform.linux,
          environment: const <String, String>{'WAYLAND_DISPLAY': 'wayland-0'},
        ),
        10 / 53,
      );
      expect(
        trackpadPanScale(
          platform: TargetPlatform.linux,
          environment: const <String, String>{'DISPLAY': ':0'},
        ),
        15 / 53,
      );
      expect(
        trackpadPanScale(
          platform: TargetPlatform.linux,
          environment: const <String, String>{
            'WAYLAND_DISPLAY': 'wayland-0',
            'GDK_BACKEND': 'x11',
          },
        ),
        15 / 53,
      );
    });
  });
}

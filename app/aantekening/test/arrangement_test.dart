import 'package:aantekening/src/arrangement/arrangement.dart';
import 'package:aantekening/src/editor/ribbon/ribbon_layout.dart';
import 'package:aantekening/src/shell/sidebar_state.dart';
import 'package:aantekening/src/editor/trackpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final RibbonLayout _defaults = RibbonLayout.defaults(RibbonGroup.values);

List<RibbonItem> _everything(RibbonLayout layout) => <RibbonItem>[
  for (final group in RibbonGroup.values) ...layout.itemsIn(group),
];

void main() {
  group('the ribbon\'s arrangement', () {
    test('holds every button exactly once', () {
      final all = _everything(_defaults);
      expect(all.toSet(), RibbonItem.values.toSet());
      expect(all, hasLength(RibbonItem.values.length));
    });

    test('every tab has sections', () {
      for (final tab in RibbonTab.values) {
        expect(RibbonGroup.of(tab), isNotEmpty, reason: tab.label);
      }
    });

    test('moves a button along its own section', () {
      final layout = _defaults;
      // Italic in front of bold, then bold to the end.
      final swapped = layout.move(RibbonItem.italic, RibbonGroup.font, 1);
      expect(swapped.itemsIn(RibbonGroup.font).take(3), <RibbonItem>[
        RibbonItem.fontSize,
        RibbonItem.italic,
        RibbonItem.bold,
      ]);
      final last = swapped.move(RibbonItem.bold, RibbonGroup.font, 99);
      expect(last.itemsIn(RibbonGroup.font).last, RibbonItem.bold);
      expect(_everything(last), hasLength(RibbonItem.values.length));
    });

    test('dropping a button just after itself leaves it where it was', () {
      final layout = _defaults;
      final index = layout.itemsIn(RibbonGroup.font).indexOf(RibbonItem.bold);
      expect(layout.move(RibbonItem.bold, RibbonGroup.font, index), layout);
      expect(layout.move(RibbonItem.bold, RibbonGroup.font, index + 1), layout);
    });

    test('moves a button to another tab', () {
      final layout = _defaults.move(RibbonItem.undo, RibbonGroup.files, 0);
      expect(layout.groupOf(RibbonItem.undo), RibbonGroup.files);
      expect(layout.itemsIn(RibbonGroup.files).first, RibbonItem.undo);
      expect(layout.itemsIn(RibbonGroup.history), <RibbonItem>[
        RibbonItem.redo,
      ]);
      expect(layout.isDefault, isFalse);
    });

    test('survives being saved and read back', () {
      final layout = _defaults
          .move(RibbonItem.pen, RibbonGroup.history, 0)
          .move(RibbonItem.zoomIn, RibbonGroup.font, 3);
      expect(
        RibbonLayout.fromJson(RibbonGroup.values, layout.toJson()),
        layout,
      );
    });

    test('reads anything else as the defaults', () {
      for (final json in <Object?>[
        null,
        'nonsense',
        42,
        <String, Object?>{'groups': 'no'},
      ]) {
        expect(RibbonLayout.fromJson(RibbonGroup.values, json), _defaults);
      }
    });

    test('skips unknown and repeated names and restores missing ones', () {
      final layout = RibbonLayout.fromJson(
        RibbonGroup.values,
        <String, Object?>{
          'version': 1,
          'groups': <String, Object?>{
            'history': <Object?>['redo', 'undo', 'no-such-button', 7],
            'files': <Object?>['undo', 'pdf'],
            'no-such-section': <Object?>['bold'],
          },
        },
      );
      expect(layout.itemsIn(RibbonGroup.history), <RibbonItem>[
        RibbonItem.redo,
        RibbonItem.undo,
      ]);
      // Undo was already placed; the picture was not mentioned, so it
      // returns to where it starts out.
      expect(layout.itemsIn(RibbonGroup.files), <RibbonItem>[
        RibbonItem.pdf,
        RibbonItem.picture,
      ]);
      expect(layout.groupOf(RibbonItem.bold), RibbonGroup.font);
      expect(_everything(layout), hasLength(RibbonItem.values.length));
    });
  });

  group('the sidebar', () {
    test('holds every button once, the same way as the ribbon', () {
      final layout = Arrangement.defaults(SidebarGroup.values);
      final all = <SidebarTab>[
        for (final group in SidebarGroup.values) ...layout.itemsIn(group),
      ];
      expect(all.toSet(), SidebarTab.values.toSet());
      expect(all, hasLength(SidebarTab.values.length));

      final moved = layout.move(SidebarTab.graph, SidebarGroup.bottom, 0);
      expect(moved.itemsIn(SidebarGroup.bottom).single, SidebarTab.graph);
      expect(
        moved.itemsIn(SidebarGroup.top),
        isNot(contains(SidebarTab.graph)),
      );
      expect(Arrangement.fromJson(SidebarGroup.values, moved.toJson()), moved);
    });
  });

  group('TrackpadAim', () {
    PointerHoverEvent hover(Offset at) =>
        PointerHoverEvent(position: at, kind: PointerDeviceKind.mouse);
    PointerPanZoomStartEvent gesture(Offset at) =>
        PointerPanZoomStartEvent(position: at);
    PointerScrollEvent wheel(Offset at) => PointerScrollEvent(
      position: at,
      scrollDelta: const Offset(0, 40),
      kind: PointerDeviceKind.mouse,
    );

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
      // The ribbon, clicked last, on the left; the page on the right.
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
          child: Row(children: <Widget>[side('ribbon'), side('page')]),
        ),
      );
      final ribbon = tester.getCenter(find.byType(Listener).first);
      final page = tester.getCenter(find.byType(Listener).last);

      final aim = TrackpadAim();
      void send(PointerEvent event) =>
          tester.binding.handlePointerEvent(aim.aim(event));
      // Clicked on the ribbon, then moved over the page.
      send(hover(ribbon));
      send(hover(page));
      // The gesture, reported where the click was.
      send(PointerPanZoomStartEvent(pointer: 7, position: ribbon));
      for (var i = 1; i <= 2; i++) {
        send(
          PointerPanZoomUpdateEvent(
            pointer: 7,
            position: ribbon,
            scale: 1 + i / 10,
          ),
        );
      }
      send(PointerPanZoomEndEvent(pointer: 7, position: ribbon));

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

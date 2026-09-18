import 'package:aantekening/src/arrangement/arrangement.dart';
import 'package:aantekening/src/editor/ribbon/ribbon_layout.dart';
import 'package:aantekening/src/shell/sidebar_state.dart';
import 'package:aantekening/src/editor/trackpad.dart';
import 'package:flutter/foundation.dart';
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

      final moved = layout.move(SidebarTab.assistant, SidebarGroup.top, 0);
      expect(moved.itemsIn(SidebarGroup.top).first, SidebarTab.assistant);
      expect(moved.itemsIn(SidebarGroup.bottom), isEmpty);
      expect(Arrangement.fromJson(SidebarGroup.values, moved.toJson()), moved);
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

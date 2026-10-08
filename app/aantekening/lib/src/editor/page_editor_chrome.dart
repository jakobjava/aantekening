part of 'page_editor.dart';

/// Where the page goes while none is open: what to do instead.
class _NoPageSelected extends ConsumerWidget {
  const _NoPageSelected();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final bindings = ref.watch(shortcutsProvider);
    Widget line(AppCommand command, String what) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 170,
            child: Text(
              what,
              style: TextStyle(fontSize: 13, color: tones.muted),
            ),
          ),
          SizedBox(
            width: 120,
            child: KeyHint(
              bindings.of(command).firstOrNull?.label ?? '',
              color: tones.text,
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: tones.base,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            line(AppCommand.notebooks, 'Notebooks and pages'),
            line(AppCommand.goTo, 'A page by name'),
            line(AppCommand.newPage, 'New page'),
            line(AppCommand.search, 'Search every page'),
            line(AppCommand.menu, 'Everything else'),
            line(AppCommand.settings, 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Glass(
        borderRadius: Corners.controlRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(error, style: TextStyle(fontSize: 12, color: tones.text)),
        ),
      ),
    );
  }
}

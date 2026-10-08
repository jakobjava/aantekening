part of 'page_editor.dart';

/// Where the page goes while none is open: the keys to one, and to
/// everything else.
class _NoPageSelected extends StatelessWidget {
  const _NoPageSelected();

  /// The keys shown, and what they do.
  static const List<(List<String>, String)> _ways = <(List<String>, String)>[
    (<String>[ModeKey.space], 'The menu: everything'),
    (<String>[ModeKey.space, 'p'], 'Notebooks and pages'),
    (<String>[ModeKey.space, 'P'], 'A page by name'),
    (<String>['/'], 'Search every page'),
    (<String>[ModeKey.space, 'n'], 'Something new'),
    (<String>[ModeKey.space, ','], 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return ColoredBox(
      color: tones.base,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (keys, what) in _ways)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The labels lined up, past keys that take more room.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 96),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final key in keys) ...<Widget>[
                            KeyCap(key),
                            const SizedBox(width: 4),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: Text(
                        what,
                        style: TextStyle(fontSize: 13, color: tones.muted),
                      ),
                    ),
                  ],
                ),
              ),
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

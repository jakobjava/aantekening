/// Where a PDF printout put onto a page goes: onto it, onto sheets of its
/// own, or onto a page of its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../look/controls.dart';
import '../look/motion.dart';

/// Where the pages of a printout go.
enum PrintoutPlace {
  /// Each on a new sheet after the one in view, the sheets after moving on.
  newSheets(
    'On new sheets',
    'A sheet for each of its pages, after the sheet in view',
  ),

  /// Onto the page as it is: on the sheets from the one in view on, or down
  /// the page from the middle of the view.
  here('On this page', 'Over what is here, to write on'),

  /// A new page of its own, shown as pages, a sheet to each of its pages:
  /// a book, say.
  newPage('As a new page', 'A page of its own, a sheet for each of its pages');

  const PrintoutPlace(this.label, this.about);

  final String label;
  final String about;
}

/// Asks where the [pages] pages of a printout go — [places], the first
/// offered first, which Enter takes — returning the place chosen, or null.
Future<PrintoutPlace?> choosePrintoutPlace(
  BuildContext context, {
  required int pages,
  required List<PrintoutPlace> places,
}) => showAppDialog<PrintoutPlace>(
  context: context,
  builder: (context) => _PrintoutPlaceDialog(pages: pages, places: places),
);

class _PrintoutPlaceDialog extends StatefulWidget {
  const _PrintoutPlaceDialog({required this.pages, required this.places});

  final int pages;
  final List<PrintoutPlace> places;

  @override
  State<_PrintoutPlaceDialog> createState() => _PrintoutPlaceDialogState();
}

class _PrintoutPlaceDialogState extends State<_PrintoutPlaceDialog> {
  late PrintoutPlace _place = widget.places.first;

  void _take() => Navigator.of(context).pop(_place);

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages == 1 ? 'one page' : '${widget.pages} pages';
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _take,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _take,
      },
      child: AlertDialog(
        title: Text('Insert a printout of $pages'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final place in widget.places)
                CheckRow(
                  title: place.label,
                  description: place.about,
                  value: place == _place,
                  onChanged: (_) => setState(() => _place = place),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: _take,
            child: const Text('Insert'),
          ),
        ],
      ),
    );
  }
}

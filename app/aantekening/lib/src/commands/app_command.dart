/// Every command that can be given a shortcut, found in the command
/// palette and listed in the settings.
library;

import 'package:flutter/services.dart';

import 'key_chord.dart';

/// What a command is about, as the settings and the palette group them.
enum CommandGroup {
  go('Go'),
  tabs('Tabs'),
  panels('Panels'),
  library('Notebooks and pages'),
  page('Page'),
  tools('Tools'),
  view('View'),
  app('Application');

  const CommandGroup(this.label);

  final String label;
}

/// A command, what it is called, and the shortcuts it starts with.
///
/// A shortcut with Ctrl, Alt or Meta works wherever the keyboard is; one
/// without, a plain letter, works only while the page has the keyboard and
/// nothing on it is being typed in — so typing never sets one off.
enum AppCommand {
  goTo(
    'Go to…',
    CommandGroup.go,
    'Find a page, section or notebook by name and open it',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyP, control: true)],
  ),
  commands(
    'Commands…',
    CommandGroup.go,
    'Find any command by name and run it',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyP, control: true, shift: true)],
  ),
  back('Back', CommandGroup.go, 'The page open before, in this tab', <KeyChord>[
    KeyChord(LogicalKeyboardKey.arrowLeft, alt: true),
  ]),
  forward(
    'Forward',
    CommandGroup.go,
    'The page gone back from, in this tab',
    <KeyChord>[KeyChord(LogicalKeyboardKey.arrowRight, alt: true)],
  ),
  previousPage(
    'Previous page',
    CommandGroup.go,
    'The page above this one in its section',
    <KeyChord>[KeyChord(LogicalKeyboardKey.arrowUp, alt: true)],
  ),
  nextPage(
    'Next page',
    CommandGroup.go,
    'The page below this one in its section',
    <KeyChord>[KeyChord(LogicalKeyboardKey.arrowDown, alt: true)],
  ),
  previousSection(
    'Previous section',
    CommandGroup.go,
    'The section above this one in its notebook',
    <KeyChord>[KeyChord(LogicalKeyboardKey.arrowUp, alt: true, shift: true)],
  ),
  nextSection(
    'Next section',
    CommandGroup.go,
    'The section below this one in its notebook',
    <KeyChord>[KeyChord(LogicalKeyboardKey.arrowDown, alt: true, shift: true)],
  ),
  newTab(
    'New tab',
    CommandGroup.tabs,
    'A tab beside this one, on the same section',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyT, control: true)],
  ),
  closeTab('Close tab', CommandGroup.tabs, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyW, control: true),
  ]),
  reopenTab(
    'Reopen closed tab',
    CommandGroup.tabs,
    'The tab closed last, as it was',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyT, control: true, shift: true)],
  ),
  nextTab('Next tab', CommandGroup.tabs, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.tab, control: true),
    KeyChord(LogicalKeyboardKey.pageDown, control: true),
  ]),
  previousTab('Previous tab', CommandGroup.tabs, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.tab, control: true, shift: true),
    KeyChord(LogicalKeyboardKey.pageUp, control: true),
  ]),
  notebooks(
    'Notebooks',
    CommandGroup.panels,
    'The notebooks and pages beside the page, with the keyboard on them',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyE, control: true, shift: true)],
  ),
  search(
    'Search',
    CommandGroup.panels,
    'Search every page, with the keyboard in the search field',
    <KeyChord>[
      KeyChord(LogicalKeyboardKey.keyF, control: true),
      KeyChord(LogicalKeyboardKey.keyF, control: true, shift: true),
    ],
  ),
  graph(
    'Graph',
    CommandGroup.panels,
    'Every notebook, section and page, and how they nest',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyG, control: true, shift: true)],
  ),
  togglePanel(
    'Show or hide the panel',
    CommandGroup.panels,
    'The panel beside the page, put away or brought back',
    <KeyChord>[KeyChord(LogicalKeyboardKey.backslash, control: true)],
  ),
  ai(
    'AI',
    CommandGroup.panels,
    'Ask about what is open, and study it — or back to the notes',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyJ, control: true)],
  ),
  newPage(
    'New page',
    CommandGroup.library,
    'A page at the end of this section',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyN, control: true)],
  ),
  newSubpage(
    'New subpage',
    CommandGroup.library,
    'A page beneath the page open',
    <KeyChord>[],
  ),
  newSection(
    'New section',
    CommandGroup.library,
    'A section in this notebook',
    <KeyChord>[],
  ),
  newNotebook('New notebook', CommandGroup.library, null, <KeyChord>[]),
  renamePage(
    'Rename page',
    CommandGroup.library,
    'The keyboard in the page’s title',
    <KeyChord>[KeyChord(LogicalKeyboardKey.f2)],
  ),
  deletePage(
    'Delete page',
    CommandGroup.library,
    'Asks first; its subpages go with it',
    <KeyChord>[],
  ),
  save(
    'Save',
    CommandGroup.page,
    'Pages save themselves as they change; this saves at once',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyS, control: true)],
  ),
  insertTextBox('Insert text box', CommandGroup.page, null, <KeyChord>[]),
  insertPicture('Insert picture', CommandGroup.page, null, <KeyChord>[]),
  insertPdf('Insert PDF printout', CommandGroup.page, null, <KeyChord>[]),
  selectTool(
    'Type and select',
    CommandGroup.tools,
    'Click to write, drag to select',
    <KeyChord>[
      KeyChord(LogicalKeyboardKey.keyV),
      KeyChord(LogicalKeyboardKey.keyT),
    ],
  ),
  pen('Pen', CommandGroup.tools, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyP),
  ]),
  highlighter('Highlighter', CommandGroup.tools, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyH),
  ]),
  eraser('Eraser', CommandGroup.tools, 'Removes whole strokes', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyE),
  ]),
  zoomIn('Zoom in', CommandGroup.view, 'Or Ctrl and scroll', <KeyChord>[
    KeyChord(LogicalKeyboardKey.equal, control: true),
    KeyChord(LogicalKeyboardKey.add, control: true),
    KeyChord(LogicalKeyboardKey.numpadAdd, control: true),
  ]),
  zoomOut('Zoom out', CommandGroup.view, 'Or Ctrl and scroll', <KeyChord>[
    KeyChord(LogicalKeyboardKey.minus, control: true),
    KeyChord(LogicalKeyboardKey.numpadSubtract, control: true),
  ]),
  actualSize('Actual size', CommandGroup.view, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.digit0, control: true),
  ]),
  fitPage(
    'Fit page',
    CommandGroup.view,
    'Everything on the page in view',
    <KeyChord>[],
  ),
  pagePreview(
    'Page preview',
    CommandGroup.view,
    'The whole page drawn small beside it, in place of its scrollbar',
    <KeyChord>[],
  ),
  toggleRibbon(
    'Collapse or expand the ribbon',
    CommandGroup.view,
    null,
    <KeyChord>[KeyChord(LogicalKeyboardKey.f1, control: true)],
  ),
  toggleDark(
    'Light or dark',
    CommandGroup.view,
    'Switches between light and dark mode',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyD, control: true, shift: true)],
  ),
  spelling(
    'Check spelling',
    CommandGroup.view,
    'Underline words spelled wrongly, or stop',
    <KeyChord>[],
  ),
  settings('Settings', CommandGroup.app, null, <KeyChord>[
    KeyChord(LogicalKeyboardKey.comma, control: true),
  ]),
  keyboardShortcuts(
    'Keyboard shortcuts',
    CommandGroup.app,
    'Every shortcut, and changing them',
    <KeyChord>[KeyChord(LogicalKeyboardKey.f1)],
  ),
  aiSettings(
    'AI models',
    CommandGroup.app,
    'Which models questions go to',
    <KeyChord>[],
  ),
  dictionaries(
    'Spelling dictionaries',
    CommandGroup.app,
    'The languages spelling is checked in',
    <KeyChord>[],
  );

  const AppCommand(this.label, this.group, this.description, this.defaults);

  final String label;
  final CommandGroup group;

  /// What it does, where its name does not say.
  final String? description;

  /// The shortcuts it has until they are changed.
  final List<KeyChord> defaults;
}

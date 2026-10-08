/// Every command that can be given a shortcut, found in the command
/// palette and listed in the settings.
library;

import 'package:flutter/services.dart';

import 'key_chord.dart';

/// What a command is about, as the settings and the palette group them.
enum CommandGroup {
  go('Go'),
  tabs('Tabs'),
  find('Find'),
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
/// nothing on it is being typed in — so typing never sets one off — and
/// only where the mode the page is in leaves the letter free.
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
  menu(
    'Menu',
    CommandGroup.go,
    'What can be done here, each a key or two away; Space does the same '
        'where nothing is being typed',
    <KeyChord>[KeyChord(LogicalKeyboardKey.space, control: true)],
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
  splitSideBySide(
    'Split side by side',
    CommandGroup.tabs,
    'The page of another tab beside this one, or a new tab’s',
    <KeyChord>[],
  ),
  splitStacked(
    'Split one above the other',
    CommandGroup.tabs,
    'The page of another tab beneath this one, or a new tab’s',
    <KeyChord>[],
  ),
  unsplit(
    'One page in the window',
    CommandGroup.tabs,
    'The page with the keys alone; the one beside it stays a tab',
    <KeyChord>[],
  ),
  otherPane(
    'The other page',
    CommandGroup.tabs,
    'The keys to the page beside this one',
    <KeyChord>[
      KeyChord(LogicalKeyboardKey.keyH, alt: true),
      KeyChord(LogicalKeyboardKey.keyJ, alt: true),
      KeyChord(LogicalKeyboardKey.keyK, alt: true),
      KeyChord(LogicalKeyboardKey.keyL, alt: true),
    ],
  ),
  notebooks(
    'Notebooks',
    CommandGroup.find,
    'The notebooks and their pages, summoned over the page',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyE, control: true, shift: true)],
  ),
  search(
    'Search',
    CommandGroup.find,
    'Search every page, the words found marked on it; n and N step '
        'through them',
    <KeyChord>[
      KeyChord(LogicalKeyboardKey.keyF, control: true),
      KeyChord(LogicalKeyboardKey.keyF, control: true, shift: true),
    ],
  ),
  graph(
    'Graph',
    CommandGroup.find,
    'Every notebook, section and page, and how they nest',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyG, control: true, shift: true)],
  ),
  ai(
    'AI',
    CommandGroup.find,
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
    'Moves it to the bin; its subpages go with it',
    <KeyChord>[],
  ),
  bin(
    'Bin',
    CommandGroup.library,
    'What was deleted, to restore or delete for good',
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
  insertLatex(
    'Insert LaTeX…',
    CommandGroup.page,
    'Put LaTeX — a passage or a whole document — into the notes as text and '
        'formulas',
    <KeyChord>[],
  ),
  addSheet(
    'Add sheet',
    CommandGroup.page,
    'Another sheet of paper after the one in view, printed as you choose',
    <KeyChord>[KeyChord(LogicalKeyboardKey.enter, control: true, shift: true)],
  ),
  moveSheetUp(
    'Move sheet up',
    CommandGroup.page,
    'The sheet in view, with what is on it, before the one above',
    <KeyChord>[],
  ),
  moveSheetDown(
    'Move sheet down',
    CommandGroup.page,
    'The sheet in view, with what is on it, after the one below',
    <KeyChord>[],
  ),
  deleteSheet(
    'Delete sheet',
    CommandGroup.page,
    'The sheet in view, and what is on it',
    <KeyChord>[],
  ),
  selectTool(
    'Type and select',
    CommandGroup.tools,
    'Click to write, drag to select',
    <KeyChord>[],
  ),
  lassoTool(
    'Lasso select',
    CommandGroup.tools,
    'Draw round what to pick out: handwriting stroke by stroke',
    <KeyChord>[],
  ),
  pen('Pen', CommandGroup.tools, null, <KeyChord>[]),
  highlighter('Highlighter', CommandGroup.tools, null, <KeyChord>[]),
  shapes(
    'Shapes',
    CommandGroup.tools,
    'Drag out the shape chosen in Draw; or hold the pen still at '
        'the end of a stroke to make it the shape it was drawn as',
    <KeyChord>[],
  ),
  eraser('Eraser', CommandGroup.tools, 'Removes whole strokes', <KeyChord>[]),
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
    'Everything on the page in view, or the whole of the sheet in view',
    <KeyChord>[],
  ),
  pageLayout(
    'Pages or canvas',
    CommandGroup.view,
    'Shows the page as sheets, or as one paper without end; nothing on it '
        'moves',
    <KeyChord>[KeyChord(LogicalKeyboardKey.keyL, control: true, shift: true)],
  ),
  pagePreview(
    'Page preview',
    CommandGroup.view,
    'The whole page drawn small beside it, in place of its scrollbar',
    <KeyChord>[],
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
    'AI settings',
    CommandGroup.app,
    'Which models questions go to, what they know of you, study profiles',
    <KeyChord>[],
  ),
  dictionaries(
    'Spelling dictionaries',
    CommandGroup.app,
    'The languages spelling is checked in',
    <KeyChord>[],
  ),
  files(
    'Files and backups',
    CommandGroup.app,
    'Where the notes are kept, backups, importing and exporting',
    <KeyChord>[],
  ),
  importNotes(
    'Import notes…',
    CommandGroup.app,
    'From OneNote, Xournal++ or an export of this app',
    <KeyChord>[],
  ),
  backUpNow(
    'Back up now',
    CommandGroup.app,
    'Every note, picture and file, in one zip',
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

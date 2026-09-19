# 12. Spell checking: Hunspell in Dart, in an isolate, dictionaries on demand

**Status:** accepted

## Context

Notes are written in more than one language, often in one page: British
English, Dutch and German to begin with, and others later. Words spelled
wrongly should be underlined as they are typed, with corrections on a
right-click, as a word processor does.

The platforms each have a spell checker, but not the same one, not with the
same languages installed, and not on every platform in a form Flutter can
reach; Linux has none of its own. The dictionaries worth having are
Hunspell's — LibreOffice, Firefox and Chrome use them, and there is one for
nearly every language — but Hunspell is C++, and binding it would mean
building and shipping a native library for each platform.

## Decision

* **Hunspell, ported to Dart.** `aantekening_spell` reads Hunspell's affix
  files and word lists and checks and suggests as Hunspell 1.7.3 does,
  following its code closely: affixes tried in the same order with the same
  state kept between them, compounding, `BREAK`, `ICONV`, the flag formats,
  the suggestion generators and their time limits. It was checked against
  libhunspell 1.7.3 itself on some 168,000 words in the three languages, with
  no difference in verdict. Hungarian's special cases and morphological
  analysis are left out. Being a port, those files are under Hunspell's
  licence (MPL 1.1, GPL 2 or LGPL 2.1); see the package's `LICENSE`.
* **Several languages at once.** A word is right if any chosen dictionary
  has it, or the person has added it; suggestions take each language's best
  in turn. Nothing guesses the language of a paragraph.
* **In an isolate.** Reading a large dictionary takes about a second and a
  suggestion up to half of one, so a `BackgroundSpellChecker` does both in an
  isolate of its own, one request at a time. On the interface's side a
  `Proofreader` keeps every verdict it has been given; a word it has none for
  counts as right until the verdicts for the words drawn in that frame come
  back together, and the boxes are drawn again. The word the caret is in is
  never marked while it is being typed.
* **Dictionaries on demand.** None are bundled. The Review tab's Languages
  menu downloads British English, Dutch or German from one fixed commit of
  wooorm/dictionaries, and installs a file only if its SHA-256 is the one
  recorded; another language is one more entry with its hashes. Any Hunspell
  dictionary can also be added from its `.aff` and `.dic` files. They are
  kept in the application-support directory, outside the workspace, as the
  preferences are.
* **Drawn by the paragraph.** A misspelling is a range in a block's
  `BlockDecoration`, drawn by `RenderBlockParagraph` as a wavy line the same
  size on screen at any zoom. Formulas and code are not checked.

## Consequences

* The spell checker has no native parts, so it runs the same on Linux,
  Windows and Android, and is tested with `dart test`.
* Checking the first words after the app starts waits for the dictionaries
  to be read; until then nothing is underlined rather than everything.
* Words added to the dictionary are kept in the preferences, on this machine;
  they do not travel with a workspace.
* Downloading needs a network connection once per language; nothing is
  fetched until a language is chosen.

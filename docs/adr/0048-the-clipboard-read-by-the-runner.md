# 48. The clipboard read by the runner

**Status:** accepted; extends what ADR 14 pastes

## Context

Flutter's clipboard carries text alone. A screenshot copied — by grim and
wl-copy, Spectacle, the Snipping Tool, Print Screen — or a picture copied in
a browser, or files copied in a file manager, could not be pasted. Dropped,
the same files were brought in, each as what it is (pictures, PDFs as
printouts, LaTeX typeset, notes imported, anything else attached).

Plugins that read the clipboard bring a toolchain or a native library each,
for one call.

## Decision

**The runner reads the clipboard**, as it already reads a touchpad's
fingers: the channel `aantekening/clipboard` and its one method, `read`
(`linux/runner/clipboard_reader.cc`, `windows/runner/clipboard_reader.cpp`).
It answers with files copied — their paths, and web addresses as they are
— or else a picture, its bytes and kind, each with whether there is text
beside it; else with nothing.

* On Linux, GTK's clipboard, on Wayland and X alike: a list of URIs, or
  GNOME's copied files, then a picture, PNG first. Only web addresses
  copied with a picture are a picture copied in a browser, and the picture
  is what is pasted.
* On Windows: files copied in Explorer, then a PNG, then a bitmap, made a
  `.bmp` file, opaque, as Print Screen copies the screen.

**What is pasted** is, in turn: what was copied in the app, while the
clipboard holds its text still (ADR 14); files copied; a picture with no
text beside it; text. A spreadsheet's cells are copied with a picture of
them, and are pasted as their text.

**Files and pictures pasted are brought in as dropped ones are**, by the
same reading (`readDropped`, which takes a picture's bytes as well as
files), in the middle of the view, or where the menu was opened. Pasted
while a text box is typed in, they go into its text, and at a bare caret,
on the paper there.

## Consequences

* On Android, what other apps copy pastes as text alone, until its runner
  reads the clipboard's content URIs too.
* The Windows reader is built by CI alone, and was not run where it was
  written.

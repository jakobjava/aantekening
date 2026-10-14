# 45. Frames handed over without the window copied

**Status:** accepted; revises what ADR 30 found GTK costs a frame on Linux

## Context

Scrolling and zooming cost the battery more than the page did. Measured
with the benchmark (`app/aantekening/benchmark`) on eight of the person's
own pages — printouts written over, pages of formulas, a page of
twenty-five PDF pages — in a profile build at 2× under KDE on Wayland, on
battery and saving power:

* **Laying out and drawing the page was the least of it.** A frame took
  about 1 ms to build and 2 ms to draw, yet the process spent 300 ms a
  second showing frames in which nothing changed, two thirds of it on the
  thread the page is built on, and nearly none of that in Dart.
* **GTK copied the whole window into the graphics card at every frame.**
  Sampled with a debugger, the thread spent most of a frame in
  `gdk_gl_texture_from_surface`. GTK 3 paints a window drawn with OpenGL
  into a picture in memory as large as the window — sixteen megabytes at
  2× — cleared first; Flutter's frame has an alpha channel, so before
  drawing it GTK copies that picture, empty, into the graphics card, to
  blend the frame over.
* **The desktop drew what lies behind the window at every frame.** GTK
  tells the compositor a window is opaque only if it paints its
  background, which ADR 30 stopped it doing: KWin then took the window
  for translucent, and drew the windows and wallpaper behind it, and
  blended it over them, each time it changed.
* Glass, by contrast, cost little: drawn without its blur, a frame of a
  scroll took 0.3 ms less to draw, and the process 0–6% less time.
* Waiting for the view to rest — to tell a screen reader where the page's
  parts are, and to build the text boxes about it — set a timer and called
  the last one off at every step of a scroll, 125 times a second on a
  touchpad.

## Decision

**One opaque pixel is laid under every frame** (`opaque_underlay.cc` in
the Linux runner), drawn by the graphics card, stretched over the view,
in the very widget Flutter draws its frame in, before Flutter does: GTK
copies none of what it knows the graphics card has drawn. Drawn in a
widget around it, it would not do: GTK takes what was drawn beneath a
widget for something to blend the widget's drawing over, and copies it
after all. Only on Wayland; elsewhere GTK reads the graphics card's
drawing back, and the pixel would cost what it saves.

**The window is said to be opaque** over the view, once the pixel is laid
under it, and again each time GTK lays the window out, which unsays it.

**Each wait for the view to rest is one timer.** A step of a scroll only
marks that the view has moved; a timer that ends after a move waits as
long again, so it waits at least as long as the view has rested, and at
most twice that.

## Consequences

On six of the pages, the old runner and the new run one after the other,
the processor time of the app:

| | before | after |
|---|---|---|
| frames with nothing in them changed | 318 ms a second | 227 ms a second |
| scrolling with a wheel | 404 | 310 |
| scrolling with a touchpad | 504 | 390 |
| pinching | 367 | 291 |
| zooming with Ctrl and the wheel | 290 | 220 |

and KWin's, on two of them, saying the window is opaque besides:

| | before | after |
|---|---|---|
| scrolling with a touchpad | 155–162 ms a second | 114–118 ms a second |
| pinching | 101–114 | 75–79 |
| zooming with Ctrl and the wheel | 93–107 | 73–77 |

The app and the compositor together spend a quarter less while the page
moves, and the graphics card copies sixteen megabytes less at every frame.
Waiting by one timer takes a thirtieth of the Dart a scroll costs off it,
too little to tell in the processor time of it all.

On battery, the whole computer drew 9.8 W rather than 10.3 W scrolling on
for twenty seconds, of which about 5.5 W the computer draws with the
screen on and nothing moving; the readings are a second apart, and a
second run of each would be needed to say more.

* A frame Flutter has not drawn yet for a window just made larger shows
  black where it does not reach, not what lies behind the window.
* GTK still clears its picture of the window at every frame, though
  nothing is drawn from it: about 30 ms a second at 60 frames, which only
  replacing what GTK paints the window with in the whole process would
  save.
* GTK 3 draws the window at 2× where the desktop shows it at 1.25×, and
  the compositor shrinks it: a frame has two and a half times the pixels
  it needs, which only a toolkit that knows fractional scales would
  spare.
* The benchmark reports the compositor's processor time, and on battery
  the power the computer draws.

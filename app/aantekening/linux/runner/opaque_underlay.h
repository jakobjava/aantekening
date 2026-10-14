#ifndef RUNNER_OPAQUE_UNDERLAY_H_
#define RUNNER_OPAQUE_UNDERLAY_H_

#include <flutter_linux/flutter_linux.h>

// Lays something opaque beneath every frame of [view], drawn by the
// graphics card, before the frame itself: on Wayland, where GTK paints the
// window with OpenGL. Elsewhere it does nothing.
//
// Flutter's frames have an alpha channel, so GTK 3, before drawing one,
// first copies into the graphics card all that its own drawing left beneath
// it — the whole window, nothing in it, sixteen megabytes of it at twice
// the pixels — at every frame. What GTK knows to be drawn already by the
// graphics card it copies no longer: one opaque pixel, stretched over the
// view, saves all of it. And the window, opaque then, is said to be, so
// the desktop need not draw what lies behind it either.
void opaque_underlay_lay(FlView* view);

#endif  // RUNNER_OPAQUE_UNDERLAY_H_

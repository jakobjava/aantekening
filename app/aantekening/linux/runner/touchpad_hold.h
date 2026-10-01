#ifndef RUNNER_TOUCHPAD_HOLD_H_
#define RUNNER_TOUCHPAD_HOLD_H_

#include <flutter_linux/flutter_linux.h>

// Tells the app in [view], over the channel "aantekening/touchpad", what
// two or more fingers on a touchpad do — the method "fingers", with
// "resting" as they come to rest on it, then "lifted" as they lift without
// moving, or "moving" as they move on — where the desktop says so: on
// Wayland, by its hold gestures. Elsewhere it says nothing.
//
// GTK 3 passes on no hold gestures, and a touchpad reports fingers put
// down only once they move: without this, fingers put down on a page
// coasting after a flick could not stop it.
void touchpad_hold_listen(FlView* view);

#endif  // RUNNER_TOUCHPAD_HOLD_H_

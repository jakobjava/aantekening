#ifndef RUNNER_CLIPBOARD_READER_H_
#define RUNNER_CLIPBOARD_READER_H_

#include <flutter_linux/flutter_linux.h>

// Answers the app in [view], over the channel "aantekening/clipboard", the
// method "read": what the system clipboard holds beyond text, which
// Flutter's own clipboard does not read. Files copied in a file manager
// come as {"files": [paths and web addresses]}, a picture — a screenshot,
// say — as {"picture": its bytes, "type": its MIME type}, each with
// "text": whether there is text beside it; anything else as null.
void clipboard_reader_listen(FlView* view);

#endif  // RUNNER_CLIPBOARD_READER_H_

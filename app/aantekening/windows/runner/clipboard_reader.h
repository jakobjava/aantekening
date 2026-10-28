#ifndef RUNNER_CLIPBOARD_READER_H_
#define RUNNER_CLIPBOARD_READER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Answers the app, over the channel "aantekening/clipboard" on [messenger],
// the method "read": what the system clipboard holds beyond text, which
// Flutter's own clipboard does not read. Files copied in Explorer come as
// {"files": [paths]}, a picture — a screenshot, say — as {"picture": its
// bytes, "type": its MIME type}, each with "text": whether there is text
// beside it; anything else as null. The clipboard is opened for [window].
//
// The channel answers for as long as what is returned is kept.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
ListenToClipboardReads(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_CLIPBOARD_READER_H_

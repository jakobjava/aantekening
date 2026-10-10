# desktop_drop 0.8.4, patched

Takes files, pictures and text dragged onto the window from other programs,
as published on pub.dev (Apache-2.0, see `LICENSE`), with three changes to
what it does on Linux, each marked `aantekening:` where it is made. The
workspace uses it through `dependency_overrides` in its `pubspec.yaml`;
0.8.4 is the package's latest release.

* **Files as URIs first** (`linux/desktop_drop_plugin.cc`). It asked first for a transfer through the
  desktop portal (`application/vnd.portal.filetransfer`), which KDE's file
  manager offers beside the files' URIs. An app outside a sandbox is refused
  the transfer — `org.freedesktop.DBus.Error.AccessDenied: Invalid
  transfer` — and a file dropped from Dolphin came to nothing. It asks for
  URIs first now, then text, and the transfer last, for a source that
  offers nothing else.
* **Text as UTF-8** (the same). Text was asked for only as `STRING`, Latin-1, and
  passed on as it came; it is asked for in any of GTK's text forms now and
  passed on as UTF-8.

* **A transfer's key is not text** (`lib/src/channel.dart`). A transfer
  the portal refused was passed on as text dragged — its key — and would
  have been put on the page as such; it is passed on as nothing now.

Only `lib`, the platforms' code, the licence, the change log and the
pubspec are kept.

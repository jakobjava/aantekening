# desktop_drop 0.8.4, patched

Takes files, pictures and text dragged onto the window from other programs,
as published on pub.dev (Apache-2.0, see `LICENSE`), with the changes below
to what it does on Linux and Windows, each marked `aantekening:` where it is
made. The workspace uses it through `dependency_overrides` in its
`pubspec.yaml`; 0.8.4 is the package's latest release.

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

* **Nothing leaks** (`linux/desktop_drop_plugin.cc`). Each drop's path and
  point were appended with a reference of their own taken, and never
  freed, and the desktop's name, lowered, at start-up; and the handler of
  `drag-motion`, a signal whose handlers return whether the point is
  somewhere to drop, returned nothing. They are freed now, and it returns
  `FALSE`, which `GTK_DEST_DEFAULT_ALL` answers for.

* **A transfer's key is not text** (`lib/src/channel.dart`). A transfer
  the portal refused was passed on as text dragged — its key — and would
  have been put on the page as such; it is passed on as nothing now.

* **Paths of any length** (`windows/desktop_drop_plugin.cpp`). A dropped
  file's path was read into a buffer of `MAX_PATH` characters said to
  hold twice as many — its size in bytes — so a longer one, with long paths
  enabled, ran past it, and one of `MAX_PATH` or more was cut short. Each
  path's length is asked for first now, and the path read whole; and paths
  are no longer written to the console as they are dropped.
* **Copied, and said so** (the same). The drop's effect was left as the
  source allowed, so dragged within a drive in Explorer the pointer said
  Move; it is a copy now, from entering to the drop.

* **Only the platforms the app is built for** (`pubspec.yaml`,
  `lib/src/channel.dart`). macOS's code and the web's — `macos/`,
  `lib/desktop_drop_web.dart`, `lib/src/web_drop_item.dart`, and the
  channel's drops and security-scoped bookmarks for them — are left out,
  with the web's dependencies; Linux, Windows and Android are kept.

Only `lib`, the platforms' code, the licence, the change log and the
pubspec are kept.

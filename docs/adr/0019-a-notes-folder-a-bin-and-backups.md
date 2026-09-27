# 19. A notes folder of files, an index beside the app, a bin and backups

**Status:** accepted — revises ADR 2

## Context

The notes lived in one SQLite database in the app's own folder (ADR 2). The
person wants to choose where their notes are — a folder OneDrive keeps in
step, so the same notes are on each of their computers — and wants nothing
lost or damaged, ever: deleting should put things in a bin, not end them,
and a backup should be a button away.

A database cannot be the thing a sync service copies. A service uploads a
database while it is being written, or its journal without it, and the
copy on the other computer is damaged; two computers writing one file
leave a "conflicted copy" of the whole of it, and every edit made on one
since is lost from the other. What a sync service handles well is a folder
of small files, each written whole.

## Decision

**The notes are files.** The notes folder holds a file for each notebook,
section and page, and for each conversation with the AI and thing kept
from one; the pictures and files the pages show are beside them, named by
their contents, as before:

```
Notes/
  aantekening.json          which notes these are
  notebooks/<id>.json       sections/<id>.json
  pages/<id>.json.gz        a page, where it is, what it shows, its contents
  conversations/<id>.json   kept/<id>.json
  assets/<ab>/<sha-256>
```

A page's file is its metadata, the pictures it shows and its page document
— the same document `docs/file-format.md` describes, so the files are the
open format, not a copy of it. Every file is written beside where it goes,
flushed to the disk and moved over it, so a crash, a full disk or a sync
service reading mid-write finds the old file or the new one, never half.

**The database is an index beside the app.** It is this computer's own,
kept under the app's folder by the notes' identity — never in the notes
folder — and does what it did: makes navigating and searching instant, and
is what the editor saves to. It commits with `synchronous = FULL`.

**Both ways, nothing lost.** Every change to a mirrored table puts the
thing changed in an outbox, by trigger, in the transaction that changed it;
`FolderMirror` writes its file once the change is still and takes it out.
The outbox survives the app stopping, so what was saved is written the next
time. The other way, the folder is looked at every minute, whenever the
system says something in it changed, and as the app starts: a file changed
since it was last written or read here is read into the index — notebooks
before their sections, sections before their pages — with the triggers
paused so it is not written back.

What could lose a change is caught instead:

* A page changed here and by another computer before either wrote: the file
  about to be written over is kept first, as a page of its own beside it,
  "(other version)". A page open and being edited when another computer's
  version of it arrives is kept the same way, "(changed elsewhere)".
* A sync service's conflicting copy of a page's file ("…-LAPTOP.json.gz")
  becomes a page of its own; then the copy goes.
* A file gone missing is written again from the index. Nothing is taken from
  the index because a file is not there — a folder half synced must not
  delete notes — only a **tombstone**, the small file a thing deleted for
  good leaves where it was, deletes it on every computer.
* An index a crash left damaged is set aside, not used, and filled again
  from the folder.

**Choosing the folder.** Settings → Files moves the notes to a folder: every
file is copied and checked, and the folder they were in is left as it was.
A folder already holding notes — another computer's — is opened instead,
with an index of its own. A database from before notes folders is taken as
the index of the folder it was in, its notes written out as files, and kept,
renamed, beside them.

**The bin.** Deleting only marks a notebook, section or page deleted, as it
did; now the bin lists them — each deleted by itself, with where it was and
how many pages went with it — restores them, the section and notebook
round a page too if those went since, and deletes them for good once asked.
Deleting from the menus asks nothing and offers Undo instead. Pictures and
files go only once no page shows them, not even one in the bin.

**Backups.** A backup is a zip of the notes folder, written beside where it
goes and checked before it is kept. The app backs up by itself, daily
unless told otherwise, keeping the ten newest; a backup restores into a
folder of its own, as notes of their own, never over the notes open.

**Saving before stopping.** The window saves every open page and writes
everything waiting to the folder before the app is let close, and when it
goes to the background on a phone.

## Consequences

* The notes can be synced by any service that syncs folders, and read by
  anything that reads JSON; the index can always be made again.
* Two computers editing the same page between syncs keep both versions as
  two pages rather than merging them; merging is left for later.
* Each change is written twice, to the index and to a file. A page's file is
  written once edits pause, not on every keystroke.
* Deleted things take room until the bin is emptied; tombstones stay, a few
  hundred bytes each.
* On Android the notes stay in the app's folder: its apps cannot be given an
  arbitrary folder to write to as files.

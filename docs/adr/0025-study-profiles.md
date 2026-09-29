# 25. Study profiles, and what the person says of themselves

**Status:** accepted; revises how ADR 17 asks for a study set

## Context

ADR 17 offered four study sets, each asked for in words written into the
app: the summary, flashcards, a quiz and the key terms. A student could not
change what they ask for: that the notes are German and the sets should be
too, that a quiz should have twelve questions as hard as the Abitur, or that
the student is in Q13 in Bavaria. They could not ask for anything else
either: exam tasks with worked solutions, a cheat sheet, a timeline.

## Decision

**What is asked for is split from the form it is written in.** A
`StudyKind` is a form: the JSON it is written in (`form`, with its `schema`)
and the view it is shown in. What to make in that form is a
`StudyProfile`: a name, a form, the idea in the person's words, and anything
they add (`details`). The instructions a model gets are the idea, then the
form, then the additions, which it is told to follow where they differ from
the rest, but in the form asked for.

**The app's own profiles are profiles too.** One for each JSON form, their id
the name of their kind, so sets made before keep belonging to them. They can
be renamed, their idea rewritten and added to, and reset; their form stays.
Only what differs from the app's own is kept in the AI settings, with the
person's own profiles after them, so a later build's better wording reaches
every profile left as it came.

**Free text, for everything else.** A fifth form, `StudyKind.text`, is
Markdown citing the notes as an answer does: its sources go as sources, cited
by each provider its own way, not numbered into JSON. It is kept as a
`StudyText`, an answer, and shown with the answer's view.

**A set belongs to its profile.** A kept set's kind (`ai_items.kind`) is its
profile's id. A set whose profile was deleted still shows, under a profile
made up from it, and can be made again or its profile saved back.

**About you.** What the person says of themselves, in the AI settings, goes
into the standing instructions of every question and study set, as
something a teacher who knows them would bear in mind.

## Consequences

* Profiles live in the preferences, on this machine, as the models do; the
  sets they make live with the notes.
* A new form is a new `StudyKind`: its instructions, its schema, how it is
  read, and its view; every profile can then take it.
* An edited profile changes what is asked the next time a set is made; sets
  already made stay as they were.

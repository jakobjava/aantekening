# 44. The notes understood and checked, not repeated

**Status:** accepted; revises how ADR 41's answers and study sets, and
ADR 43's podcasts, are asked for

## Context

Made from the school notes with MiMo 2.6 Flash, answers and study sets
often tied things together wrongly and got facts wrong:

* **What was typed onto a worksheet was tied to the wrong blank.** A
  printout's text is read out of it by machine, its blanks left out; the
  words and formulas typed into them come after it, one passage each, not
  in the order they stand on the sheet (ADR 17). The model read them as
  following on from one another: a label in a drawing, $\vec v_E$, became
  a value "given", and a summary cited the label $M_S$ for "the Earth's
  pull on the Sun can be neglected".
* **Mistakes in the notes were passed on as fact.** A student's typed
  answer worked out the Earth's $g$ where the task asked for the Moon's; a
  formula was rearranged wrongly; a law worksheet wrote "verschuldete" for
  "geschuldete" — and the summaries said the same. A summary was told that
  only its "beyond" might hold what the notes do not say, so where it knew
  better it wrote the notes' version as a point and the right one beneath,
  contradicting itself.
* **Quizzes marked the wrong option** — two of nine in one, each with an
  explanation arguing for another.

The prompts told the model to reuse the student's words and to cite the
notes, and nothing about how the notes come to it, or that they may be
wrong.

## Decision

**Every prompt that gives the notes says how to read them**
(`NoteAgent.readingTheNotes`): they are a student's, incomplete and
sometimes wrong; a printout's text is read by machine, garbled in places,
its blanks missing; what was typed onto a sheet comes after its text, in
pieces, and only the picture shows where each stands — look before tying
a piece to anything, and tie what cannot be placed to nothing; passages
next to one another need not belong together, and a worked example's
numbers belong to it alone. The notes are put right only where they are
surely wrong — a simplification taught at school is no mistake.

**The model thinks before it writes, and checks.** It works out what the
notes mean and how their parts connect, as a teacher of the subject
would, then checks every fact, formula, unit and number — working
calculations out again — and that each is tied to the right thing. A
study set says what is right, never repeating a mistake of the notes; the
student's terms and phrases are kept where they are right. A summary's
points are put right where the notes are wrong, and its "beyond" says so.
A quiz question is worked out before it is written: one option right,
named alike by "answer" and the explanation. Citations name the passages
that say a thing, not those that only share a word with it, and passage
numbers stay out of the text a student reads.

## Consequences

Measured by making the same sets of the same school pages (physics,
chemistry, law, calculus) with MiMo 2.6 Flash through Requesty, as the app
asks for them, the worksheets drawn as the app draws them — twice before
the change, and four times after:

* Quiz answers marked or worked out wrong fell from two in 27 questions
  to one in 78. The rearranged formula for the Moon's period, wrong in a
  summary before, was right in all after.
* The sets found the mistakes in the student's own work — the Earth's $g$
  for the Moon's, the Moon's radius added to its distance and in the wrong
  unit, an integral worked out between the wrong bounds, § 280 V for
  § 281 V, § 280 II for § 280 III — and explained what the notes only half
  said, such as why acid takes the colour out of 4-nitroaniline.
* Its own arithmetic is not to be trusted for all that: having found the
  wrong bounds, it worked the integral out wrongly itself.
* Corrections overreach in law: it still says now and then that a
  guarantee takes away what the debtor must answer for, where it is the
  other way round. The line on correcting only what is surely wrong made
  that rarer, not rare.
* A fill-in is still cited now and then where the printout's sentence
  should be: the text gives no place for what was typed, so only a model
  that looks at the picture can place it. Giving each typed piece the
  printout line it stands beside would settle it.
* The model thinks far longer before a study set — ten to a hundred
  thousand characters — so a set costs about twice as much, still under a
  cent, and takes longer. Long thinking sometimes leaves a stray word of
  another language in what it writes.

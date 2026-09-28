# 22. Study sets from any model

**Status:** accepted; supersedes how ADR 17 reads a study set

## Context

A study set is asked for as JSON (ADR 17). Claude and the larger OpenAI
models write it as asked; others do not, each in its own way. MiMo 2.6
Flash, through Requesty, wrote a summary that was shown growing as it
streamed, then vanished once it was done, with "the model did not write the
summary in a form the app can read". Two readings disagreed: the one while
it streamed closed the JSON where it broke off, and the one at the end took
the text from its first `{` to its last `}` and handed it to `jsonDecode`.
Anything the model wrote after its JSON with a brace in it, a second object,
or one quote left bare inside a string (`der sogenannte „Luftwiderstand"`)
failed the second reading after the first had shown the set.

Models otherwise differ in whether they wrap the JSON in a fence or prose,
double LaTeX's backslashes, leave commas out or in, name fields their own
way (`"Question"`, `"answer": "B"`, options as `{"A": …}`), wrap the set in
another object, write it into their reasoning, or write Markdown instead.

## Decision

**One reading, forgiving, for text still arriving and text complete.**
`LooseJson` reads every object and list in what a model wrote, passing over
the prose round them. Where JSON is broken it reads what a person would take
it to mean: a quote closes a string only where what follows can follow one;
LaTeX's backslashes are kept where they are not JSON's escapes; comments,
missing and trailing commas, single quotes, bare keys and Python's `True`
are read; a value broken off keeps what it holds so far. It says whether
anything was lost: reading stopped at something it could not read.

**A set is read by what its fields mean.** `StudySet.reading` takes the
fullest set any value in the text holds, a level or two into what wraps it,
each field found by any of the names models give it, a quiz's right answer
by its index, letter or words.

**Held to the form where the provider can.** Each kind of set has a JSON
Schema (`StudyKind.schema`), sent with the request (`answerSchema`) as the
provider allows: to Ollama as `format`, which any model follows as it
writes; through the OpenAI API as `response_format`, a schema or JSON alone,
where the listing says the model takes it (`StructuredOutput`). A server
that refuses it is asked again without.

**Asked once more, never taken away.** What cannot all be read, the model
is asked to put in order: what it wrote, without the notes, with the form
asked for again. The set kept is the fullest of what was read, what came of
asking again, and what was shown while it streamed.

## Consequences

* A set once shown stays; it is replaced only by one that holds more.
* A model that writes Markdown, or its own JSON, still makes a set, at the
  cost of a second, short request.
* Flashcards and quizzes in an answer's fenced blocks are read the same way.
* Names a model may give a field are a list to add to, not a format the
  app demands.

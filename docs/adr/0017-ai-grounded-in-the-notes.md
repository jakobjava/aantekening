# 17. AI from any provider, grounded in the notes, and kept apart from them

**Status:** accepted — supersedes ADR 7

## Context

The AI was a panel in the sidebar holding the settings of one local
runtime, Ollama, and a handful of prompt builders nothing used. It could
read none of what a page holds but typed text, cited nothing, and kept
nothing. What it has to become:

* a companion that answers as someone who has read every note — typed text,
  formulas, tables, pictures, PDF printouts, and the handwriting and
  drawings over them;
* grounded: citing every source, telling the person's notes from the web
  from its own knowledge, and linking to each;
* organised by the notes: every notebook, section and page has an AI of its
  own, where what was made about it — summaries, flashcards, quizzes,
  answers — is kept;
* able to run on this machine or on a provider the person chooses, and ready
  for models and kinds of note that do not exist yet.

## Decision

* **One provider interface** (`ChatProvider`), streaming a neutral
  conversation (`ChatMessage` of text, images, sources, tool calls and
  results) into neutral events. Two classes cover the field: Anthropic's
  Messages API, and the OpenAI chat completions API that nearly every
  runtime and service speaks — LM Studio, llama.cpp, vLLM, OpenAI, Gemini,
  OpenRouter, Mistral, Groq, DeepSeek. Ollama is spoken to in its own API
  (a subclass writing the same messages its way), because its OpenAI one
  cannot say how much room a model runs with: left alone, Ollama runs a
  model with 4,096 tokens, and a model that thinks first spends them all
  thinking. Its models run with the room the settings give (16k by
  default), and think first only if the settings let them. A model that
  thinks longer than the settings allow (three minutes by default), or into
  the room its answer needs, is stopped and asked again with what it thought
  handed back and its answer begun — which closes its thinking, so it
  answers from there. Small models on a slow computer otherwise think in
  circles for half an hour. Stopping an answer breaks its request off at
  once, even while the model is still reading and has sent nothing: the
  connection closes, and the model stops once it has read the chunk of
  the prompt under way — 512 tokens, so a slow computer is free again in
  seconds, not minutes. What only one provider
  understands (Claude's reasoning, its web searches) is kept verbatim as a
  `NativePart`, handed back to that provider as it came and ignored by
  others. What a model can do (`ModelCapabilities`: images, tools, native
  citations, native web search, reasoning, context length) decides how it is asked,
  never which model it is.
* **Nothing goes anywhere by default.** No provider is set up until the
  person adds one; the settings say for each whether the notes stay on this
  machine. API keys live in the system keychain, never in a file.
* **Pages are taken apart once, for every model** (`PageDigest`, in core):
  their content in reading order as citable passages — Markdown, formulas
  as LaTeX, tables as rows — and their visuals: pictures, PDF pages and
  drawings. Whatever lies on a sheet — a PDF page, a picture, or a text box
  holding a printout — is kept together with it: the handwriting over it and
  the text boxes typed onto it, as on a worksheet (*Arbeitsblatt*), since
  what is written on a sheet only means something seen with it. The typed
  text stays citable as text, and says what it was typed onto. Every
  element type describes itself there in one exhaustive switch over the
  sealed `NoteElement`, so a new kind of element — a mind map — does not
  compile until the AI can read it. Visuals are drawn by the app as the
  canvas draws them (`VisualRenderer`) and shown to models that can see.
* **Context is chosen, not dumped** (`NoteContext`): the scope's pages go
  with the first question — the page whole, or in a section or notebook
  those most about the question first — within a share of the model's
  context; the rest is named in an overview, to be read on demand. A sheet
  is drawn as the canvas draws it: its text boxes laid out off the screen
  by the page's own text box, so formulas and lists look as they do, and
  the printouts in them drawn where the layout put them.
  Handwriting over printouts and drawings are shown up front; plain PDF
  pages, whose text is given, are looked at when needed.
* **An agent, not a prompt** (`NoteAgent`): models that use tools search the
  notes — the scope, or everything — read pages, look at visuals, and search
  the web through the app where their provider cannot. Models that cannot
  are given the passages about each question instead.
* **Citations down to the sentence.** Every paragraph is split into its
  sentences (`SentenceSplitter`, which knows abbreviations, numbers and
  formulas), and each is a `Source` passage with a link to its very words
  (`NoteLink` with `from` and `to`). Anthropic cites search results
  natively, a span of sentences as one range; other models cite numbered
  markers the app reads back and checks, so a made-up number is never a
  citation. Web results are sources too, marked as the web. An answer
  (`AiAnswer`) is Markdown with markers into its citations, the same
  whoever wrote it. Opening a citation opens the page in a tab of its own,
  picks the text box and marks the sentence in it.
* **Studying is not chatting.** The AI mode of a notebook, section or page
  opens on an overview of what can be made to learn from it: a summary,
  flashcards, a quiz and the key terms (`StudyKind`). Each is asked for as
  JSON (`NoteAgent.make`), from the notes given whole with their sentences
  numbered, every point, card, question and term naming the sentences it
  comes from; the JSON is read leniently (`StudyJson`: what a model wraps
  it in, LaTeX whose backslashes it did not double, trailing commas) and
  read as far as it goes while it streams, so a set is seen growing. Each
  set has a view of its own: the summary as a study sheet — the gist,
  numbered parts, formulas in boxes, what goes beyond the notes set apart,
  and the sentences cited quoted beneath; flashcards as cards that turn
  over, graded Again, Hard, Good or Easy and scheduled by spaced repetition
  (`CardReview`, SM-2 as Anki has it, learning steps in minutes and reviews
  in days), with every card to look through and correct; a quiz a question
  at a time, explained as it is answered, the missed ones to take again;
  the key terms as a glossary. Made again, a set keeps what was learnt of
  the cards that ask the same.
* **An answer shows where each part comes from**: small numbers after what
  they support, coloured blue for the notes and green for the web, the
  sentence cited shown on hover; what cites nothing, the model's own
  knowledge, ruled grey down its side; and the sentences cited quoted
  beneath, by page, the web after.
* **An AI mode for every notebook, section and page**, in place of the page
  (Ctrl+J, the sidebar's AI button, or the item's menu): the overview, the
  sets, the conversations and the answers kept down the side, and a line
  to ask in at the foot. Flashcards or a quiz a conversation writes are
  fenced JSON blocks in its Markdown, drawn with the same views, and cards
  can be added to the set.
* **An answer shows how it is coming along**: the agent reports a stage
  (gathering, reading, thinking, writing, working) and what it is doing in
  words — how much the model was given to read, in tokens and pictures;
  providers stream reasoning apart from the answer (`Reasoning`), read out
  of `<think>` tags where a runtime writes it into the text. The app times
  each step and shows the one it is on counting up, the reasoning as it
  comes and how fast the model writes, since a model on this computer can
  read for a minute before it writes a word.
* **Kept apart from the notes, in storage too**: conversations
  (`ai_threads`, `ai_turns`), what was kept and made (`ai_items`) and how
  its cards are learnt (`ai_reviews`) are tables of their own, belonging to the notebook, section or page they are about.
  Nothing of them is ever written into a page, and the notes are only ever
  what the person wrote.
* **Links to notes in general** (`aantekening://page/<id>#element=…`): a
  page, section or notebook's menu copies one, a text box's menu copies one
  to a paragraph, a link pasted alone is pasted as a link, and Ctrl+click
  follows one.

## Consequences

* Adding a provider with an API of its own is one class; a provider on the
  OpenAI API is a preset. New capabilities of models are new fields of
  `ModelCapabilities`, and new tools are new `ToolSpec`s.
* Search for the AI uses full-text search with any of a question's words,
  ranked by BM25; embeddings are stored per model but not used for it yet.
* A notebook too large for the context is read through its overview and the
  tools, which a model without tools cannot do: it gets the passages that
  match each question.
* Handwriting is understood by models that can see, when they look at it;
  it is still not searchable.

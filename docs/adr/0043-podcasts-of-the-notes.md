# 43. Podcasts of the notes, with the models and voices one chooses

**Status:** accepted; adds to what ADR 17's AI makes, and folds the sources
beneath its answers

## Context

A student revising on the bus, or with their eyes tired, learns better by
ear than by reading their notes again. Open Notebook makes podcasts of what
it is given, and is the guide here: two tiers of profile — an *episode
profile* saying what to make (a briefing, how many segments, the language)
and which models plan and write it, and a *speaker profile* saying who
speaks (one to four speakers, each with a voice, a backstory and a
personality) and through which text-to-speech model; an outline, then a
transcript written segment by segment, each knowing what was said before;
and the lines spoken and joined.

The app talked to chat models only. It had no voice, no sound, and every
study set was made by the one model in use.

Two smaller things were wrong with answers. The sources listed beneath an
answer, quoted one by one, were often longer than the answer itself. And
the preview of a citation, on hover, was written in the base colour, as for
a tooltip drawn in the text's colour — but tooltips had become raised
panels of the base colour (ADR 40), so in the dark the quote was black on
near-black.

## Decision

**Voice providers beside model providers** (`VoiceConfig`, `SpeechProvider`).
Three APIs cover the field: OpenAI's `/audio/speech`, which the speech
servers one runs oneself speak too (Kokoro-FastAPI, Speaches,
openedai-speech, LocalAI); Gemini's `generateContent` asked for audio; and
ElevenLabs. Each is asked for sound it can be asked for alike — WAV or
16-bit PCM — and every answer is read into one form (`Sound`: one channel
of 16-bit samples), mixed to one channel and brought to 24 kHz, whatever
it came as. Their keys live in the keychain, as the models' do. The
settings say for each whether what is spoken stays on this computer; only
the words to speak go to a service, never the notes.

**Episode and speaker profiles, as Open Notebook has them**
(`EpisodeProfile`, `SpeakerProfile`), on a settings page of their own. An
episode profile names the model that plans the episode and the one that
writes it (`ModelChoice`): the model in use, or any model of any provider
set up — a strong model to plan and a quick one to write, say. The app
comes with three of each — a study conversation between a teacher and a
student, an exam drill between two classmates, a short lecture — and keeps
them, changed, in the AI settings once the person changes any.

**Made in three steps, each shown** (`PodcastMaker`). The notes are given
as a study set's are, within the smaller budget of the two models. The
planner writes the segments as JSON, held to a schema where the provider
can and read however it was written; the writer writes each segment's
lines as JSON, with the plan and what was said before (its last 12,000
characters); a part that cannot be read is asked for once more. Everything
is written to be heard: no Markdown, no stage directions, formulas said in
words. Then each line is spoken in its speaker's voice — four at once
from a service, one at a time from this computer — and joined, a breath
between speakers, with where each line begins kept.

**The transcript is kept first, the sound beside the app.** The episode
(`PodcastEpisode`) is kept as the AI's other things are (`ai_items`, kind
`podcast`) as soon as it is written, so a voice that fails loses nothing.
Its sound is a WAV file in the app's own folder on this computer, never in
the notes folder: it is large, and wherever it is missing it can be spoken
again from the transcript. Deleting the episode deletes the file.

**Heard with its transcript.** The episode's page plays it (`audioplayers`:
GStreamer on Linux, Media Foundation on Windows, the system's player on
Android), marks the line being said and keeps it in view, starts from a
line clicked, plays at up to twice the speed, and saves the sound as a WAV
file. A player is only made once something is played.

**Sources beneath an answer fold.** The notes and the web are each a line
saying how many places are cited, opened by a click; the numbers in the
answer and their previews are unchanged. A preview is written in the text's
colour, on the tooltip's raised panel.

## Consequences

* Linux builds need GStreamer's development files, and the app GStreamer
  with its base and good plugins (for WAV) at run time.
* A podcast costs a request to plan it and one for each segment, each with
  the notes; a provider that caches what it was given before makes the
  later ones cheap. What writing it cost is shown with it; what speaking it
  cost is not, since voice providers do not say.
* A ten-minute episode is about 30 MB of WAV. It is not compressed: no
  encoder is to hand on every platform without a native library.
* New voice APIs are a `SpeechKind` and a class; new voices of a known API
  are in its preset's list, or listed by the server.

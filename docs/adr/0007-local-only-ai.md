# 7. AI runs locally, is optional, and is off by default

**Status:** accepted

## Context

Notes are among the most private things people keep. AI features are useful —
summaries, semantic search, answering questions across a notebook — but not at
the cost of sending notes somewhere.

## Decision

All model access goes through the `LocalModelClient` interface. The only
implementation ships against Ollama on the loopback interface. The features are
disabled until the user turns them on and picks a model.

## Consequences

* The application is fully usable with no model installed, and opens no socket
  until asked.
* Adding another runtime — llama.cpp over FFI, or a self-hosted server — means
  writing one class, not touching the features.
* Embeddings are stored per model, because vectors are only comparable within
  one; changing the embedding model rebuilds the index.
* Prompts are pure functions, reviewable and testable without a model running,
  and each instructs the model to work only from the supplied notes. An
  assistant that invents plausible content is worse than none when its output
  will later be read back as the user's own notes.

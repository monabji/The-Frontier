# 0013 — Free access, not a personal login

**Status:** Accepted — 2026-11-22

## Context

The paper runs on a server at 05:15 IST. Its editor needs a model. The owner
will not pay and does not want the daily run to depend on a logged-in browser
session at ChatGPT, Gemini or Claude. The survey in
`docs/research/free-llm-access.md` compares the no-card and keyless options.

Consumer chat windows cannot be the daily editor: they require a personal
login, their markup changes without notice, and their terms do not invite
automation. A free API tier is a stable, server-compatible alternative.

## Decision

- The editor remains an OpenAI-compatible `/chat/completions` call. A free key
  is a configuration change, not a code change: point `FRONTIER_LLM_BASE_URL`
  and `FRONTIER_LLM_MODEL` at the provider and set `FRONTIER_LLM_API_KEY`.
- The recommended no-card provider is the Gemini free tier; OpenRouter's free
  models are the fallback. Both hold the whole brief in one call and let the
  paper meet its 80–100 word summaries and 8–10 minute read.
- `FRONTIER_LLM_KEYLESS=1` allows an endpoint with no Authorization header.
  `FRONTIER_EDITOR=keyless` writes the paper one section at a time in a plain
  line format (`Frontier.Editor.Plain`) so a small model cannot corrupt the
  whole reply by mis-escaping JSON. A quote that is not verbatim is replaced
  with the first clean sentence from the source; the rest of the grounding is
  unchanged. Keyless editions have looser word budgets and print their real,
  shorter read time.
- `mix frontier.brief` and the token-gated `/desk` page remain the manual path:
  brief out, paste a chat reply back, same grounding.

## Consequences

- No payment and no personal account are required for the keyless run. A free
  key costs nothing and restores the full word budgets.
- Free providers change limits and model IDs. The research note is a starting
  point, not a promise; verify a provider before relying on it for a streak.
- The keyless path is an emergency edition, not an equal substitute. It is
  visibly shorter and the run log names the model that wrote it.

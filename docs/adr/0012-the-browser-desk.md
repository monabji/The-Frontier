# 0012 — The browser is the editor when there is no key

**Status:** Accepted — 2026-11-22

## Context

The editor calls an OpenAI-compatible endpoint. Without an API key or direct
model access there is no morning: the pool is fetched and clustered, and then
nothing is written, so the page stays on yesterday's edition. The person who
runs the paper has browser accounts at ChatGPT, Gemini and Claude but no key.

Two responses are wrong. A deterministic "summarizer" that stitches source
excerpts together would print prose nobody edited and would tempt the grounding
check to accept copied text. A hand-authored edition checked into the repo
would stop being a newspaper after one day.

## Decision

The editor gains a **desk**: a brief out, a reply in.

- `mix frontier.brief` writes the exact prompt a model would receive — the
  paper's furniture, caps, word budgets, quote rule, and every candidate with
  its id, link and source text — to `tmp/desk/<day>-brief.txt`.
- A person pastes that into a chat window and pastes the JSON reply back with
  `mix frontier.desk --reply <file> --assistant chatgpt`, or into the
  token-gated `/desk` page, which can assemble and publish.
- The reply is a **client**, not a special path: `Frontier.Editor.Client.Desk`
  returns the pasted JSON to the same `Editor.edit/2`, which builds the plan and
  grounds every entry. Sections, caps, quote-substring checks, entity checks,
  word budgets and link resolution are unchanged. A failed check drops the
  story. The repair pass is off, because there is no live model to ask again;
  the person can fix the JSON and re-submit while the edition is a draft.
- The run records `desk:<assistant>` with zero tokens and zero cost. It is
  visibly not a model run, and it is not disguised as one.
- `/desk` is disabled unless `FRONTIER_DESK_TOKEN` is set, and requires that
  token on every request. It can write and publish an edition.

## Consequences

- The paper can publish every day with no vendor account, at the cost of one
  paste in each direction.
- The chat window is untrusted input: code fences and preamble are tolerated,
  but the reply is decoded and grounded, never executed or trusted.
- A pasted edition is one person's reading of the day, and the log says so.
  The desk is intended as the bridge until a key exists, not a reason never to
  add one.
- The brief is large (about 60,000 characters for 100 candidates). Chat windows
  that truncate a long paste will produce a short or invalid reply; grounding
  catches it and the desk can be re-run.

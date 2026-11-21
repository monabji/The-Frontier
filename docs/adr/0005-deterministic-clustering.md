# 0005 — Clustering is deterministic, never learned

**Status:** Accepted — 2026-11-22

## Context

The paper's unit is the story: one real-world event, however many sources
carried it. Hacker News and a company blog publish the same launch; a social
post reacts to it. Printing three entries would make the paper a feed with
duplicates. Embedding similarity would work but costs money, cannot be
reproduced byte-for-byte, and makes "no canonical URL appears in two stories"
a probabilistic claim rather than a guarantee.

## Decision

Clustering is a pure function of the day's items:

1. **Same canonical URL** — always the same story. Identity is normalised URL:
   lowercased, `www.` dropped, `http` folded into `https`, campaign parameters
   and fragments removed, query sorted, trailing slash dropped.
2. **Same distinctive name within 24 hours** — a name is a run of capitalised
   words with version numbers kept ("Inkling 2 Mini", "Gemini 4 Argon"). A
   name of two words is a company or a family ("Hugging Face") and never merges
   two stories; three words, or a version, is an event.
3. **Title overlap above 0.55** (Jaccard over content words, stopwords and bare
   numbers removed) within the same 24-hour window, for the same event written
   two ways.

The story's key is its primary item's canonical URL. The primary is the
publication, never the aggregator; among publications, the earliest. Roles:
`primary` (printed link), `discussion` (aggregator thread), `duplicate`.

The pool is rebuilt, not appended to: a rebuild replaces the day's stories, and
running it twice over the same items produces the same keys and members.

## Consequences

- A re-run is idempotent and inspectable: the same pool gives the same stories,
  and `/pool` shows why each item landed where it did.
- Thresholds are tuning knobs, and they are cheap now: the phase-3 review gate
  hand-checks real clusters and moves them.
- False negatives are visible as duplicates on the page; false positives as two
  unrelated headlines in one story. Both are inspected on `/pool`, not guessed
  at.
- A two-word company name cannot merge stories, so a busy launch day by one
  vendor stays several entries — until phase 4's editor judges them.
- No embeddings means no per-item cost, no model version to pin, and no
  network in `mix test`.

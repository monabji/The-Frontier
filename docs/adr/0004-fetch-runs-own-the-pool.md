# 0004 — A fetch run owns its pool; the page reads the latest run

**Status:** Accepted — 2026-11-22

## Context

`raw_items` holds one row per `(source, external_id)`, refreshed on every
fetch. The page selected a source's rows for the day and ordered them by the
source's own rank. Two fetches in one day break that: after HN's front page
rotates, the second batch's stories carry the same positions as the first, the
older rows win the tie on `id`, and the page keeps printing stories that are no
longer on the front page while never showing the ones that are. The same
ambiguity would make phase 5's "rebuild a past day" impossible to reason about.

## Decision

Every adapter run opens a `runs` row before it fetches, and every stored item
carries the `run_id` that last saw it. The page reads each source's most recent
successful run for the edition day, not "all rows seen today". `edition_day` is
the IST day an item was last seen on; `first_seen_at` and `inserted_at` are
never rewritten.

`raw_items` stays current state, not history: a story's score and comment count
are today's. History lives in the run rows and, from phase 5, in the published
edition artifact — which is why a printed day never moves when the fetch runs
again.

## Consequences

- The page is a projection of one batch per source: rotation is honest, and a
  failed run leaves the previous batch in place rather than an empty page.
- Per-source counts are already a row, so phase 6's run log and phase 10's
  admin page read the same table.
- A re-run does not append history to `raw_items`; the run row records that it
  happened and what it saw.
- Clustering works from one day's latest batches; the artifact in phase 5
  freezes that pool.
- A run that fetched nothing does not become "the latest": the previous batch
  stays visible, so a feed that suddenly parses to zero items cannot blank its
  column.
- The page falls back to the most recent day that did fetch, so midnight does
  not empty the paper for five hours; it prints the last edition and its date.
- One fetch per source per day is the intended rhythm. A second fetch replaces
  the first batch rather than accumulating history; phase 3's 24-hour window
  reads `published_at`, not fetch history. If Late Wire or manual re-runs need
  membership history, that is a `run_items` table and a deliberate change to
  this record.

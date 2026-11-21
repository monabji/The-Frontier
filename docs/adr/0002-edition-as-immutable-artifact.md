# 0002 — The edition is an immutable artifact; the page is a projection

**Status:** Accepted — 2026-11-22

## Context

A newspaper's credibility depends on "what did it say that morning" staying true. A feed-backed page re-renders from current data, which silently rewrites history and makes archives, corrections and debugging ambiguous. The product also needs Late Wire additions and a freeze at midnight.

## Decision

Each edition is built as a content-addressed artifact (JSON + rendered HTML) and stored. The web app renders artifacts. Late Wire additions are appended as new entries to the day's log with timestamps; the edition freezes at midnight and is never rewritten. Republishing a past day means rebuilding from the recorded pool, producing a new artifact version, not mutating the old one.

## Consequences

- Archives and rollbacks are storage lookups; "what did Tuesday say" has one answer.
- The page is cheap to render and cache; readers never wait on the pipeline.
- Every stage must record enough input (raw item ids, cluster keys, editor output) to make a rebuild reproducible.
- Corrections need an explicit, visible mechanism rather than an edit.

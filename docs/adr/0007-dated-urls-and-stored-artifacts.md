# 0007 — A dated URL names an artifact, not a query

**Status:** Accepted — 2026-11-22

## Context

A daily paper is only credible if "what did it say on Tuesday" has one answer. A URL that renders whatever the database currently holds rewrites history whenever the pool is re-fetched or an editor re-runs. The artifact (ADR 0002) made the edition a stored object; phase 5 has to decide the URL, the storage layout, and what freezing means.

## Decision

- **The URL is the edition date in IST**: `/2026/11/22`, never a UTC date and never a slug. The archive is `/archive`. A missing day is a 404, not a redirect to the latest paper.
- **The artifact is content-addressed.** `priv/editions/<day>/<sha256>.json` holds the canonical document and `<sha256>.html` its rendered snapshot. `current` is an atomically replaced pointer to the version the page shows. Old versions stay; a republish adds a version, it does not erase one.
- **The hash covers the paper, not the build.** Keys are sorted at every level; the hash is over the day, status, published time, desk note, stats, sections and entries. Build time lives in the database only, so the same inputs produce the same hash and the same bytes whenever they are assembled.
- **The page reads the artifact, not the database.** `/`, `/2026/11/22` and `/archive` read `Store` only. The cluster pool remains a pre-first-edition fallback; once an artifact exists, serving it touches no Ecto query.
- **Freezing is a file marker.** `frozen` records the hash that may never move. `assemble`, `publish` and `save_draft` all refuse a frozen day; the frozen bytes are never rewritten.
- **Archive lists published days only.** A draft can be assembled for preview, but it is not part of the public record until it is published. Phase 6 owns when that happens.

## Consequences

- A published day can be read with the database stopped, restored from the JSON + HTML pair, or moved to object storage by swapping `Store` for another implementation.
- A rebuild of a past day is a pure function of its recorded edition entries; the acceptance test assembles twice and compares hashes.
- URLs are permanent and cheap; changing them later would break every link and every archive reference, so the shape is settled now.
- Corrections and Late Wire additions are new artifact versions with visible timestamps; they never mutate a frozen hash.
- Drafts are visible at `/` during development but excluded from the archive; phase 6's publish job is what makes a day public.

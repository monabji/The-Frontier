# The Frontier — glossary

Vocabulary used across the codebase, issues and docs. When a term here competes with a synonym, use this one.

## The paper

- **Edition** — the paper's unit of record: one immutable, dated bundle published at 06:00 IST, identified by its date (`2026-11-22`). After midnight it is frozen; corrections and late additions live in its log, never by rewriting it.
- **Edition date** — the calendar day an edition belongs to, in India Standard Time (UTC+05:30, no daylight saving). The date line and the archive key both use the IST date; a UTC evening is already tomorrow's edition (`Frontier.Newsroom.Dateline`).
- **Edition artifact** — the content-addressed JSON + rendered HTML bundle for one edition. Archives and rollbacks read artifacts, never re-query the database.
- **Late Wire** — stories added to the current day's edition between 06:00 and 18:00, capped at 3, visibly marked with the time added. Not a second edition.
- **Quiet day** — an edition with fewer stories than target, labelled honestly in the desk note. Never padded.
- **Desk note** — the two-sentence "From the desk" opening that reads the day's shape. Machine-written, always labelled as such.

## Editorial

- **Story** — one clustered real-world event: headline, dek, summary, one verbatim source quote, one working link, optional discourse quotes. A story appears at most once per edition. Before the editor writes copy, its headline is the primary item's title.
- **Cluster** — the deterministic grouping that makes one story out of many raw items: same canonical URL, a distinctive name shared within 24 hours, or a near-identical title inside the same window (ADR 0005).
- **Story item** — a raw item's membership in a story, with its role: `primary` (the publication whose link is printed), `discussion` (an aggregator's thread), or `duplicate` (another source carrying the same event).
- **The pool** — the day's stories before the editor ranks and places them, inspected at `/pool`.
- **Candidate pool** — the day's clustered stories (~150) before the editor picks and places them.
- **Section** — Front Page, Models & Releases, Research, Tooling & Dev, The Discourse, The Long Read, Back Page. Fixed names, no quotas: a section with nothing real disappears for the day.
- **Also Today** — the one-line ticker for real-but-minor items; 10–15 entries, never padded.
- **Lead** — the Front Page story above the fold. Until the editor writes summaries it is the newest item, set at display scale with a rule beneath it; the drop cap and dek return with the editor.
- **Source quote** — one verbatim line from the fetched source text, shown under the summary. It grounds the summary and is checked mechanically.
- **Discourse** — 2–3 quoted reactions to a story, set as typeset pull-quotes with handle and link, not embed widgets.
- **Reprint window** — a story printed in the last 72 hours does not reprint unless materially updated; updates are marked as such.
- **No link, no story** — a story without a resolving link and a verified quote is not printed.

## The editor

- **The editor** — the LLM pipeline stage that ranks the pool, assigns sections, writes headlines, summaries and the desk note, and picks quotes. It never invents facts; every claim traces to a source or a quote.
- **Grounding check** — mechanical validation: quote is a substring of source text, link resolves, entities appear in the source, word budgets respected. Failures send the story back, not to print.
- **Run** — one execution of a pipeline stage for a day, recorded with timing, cost and errors.

## Readers

- **Reader ID** — a signed anonymous cookie identity. There are no accounts, passwords or emails in v1.
- **Your paper link** — a saveable recovery link that re-binds a reader ID, so a cleared browser is not a lost profile.
- **Taste profile** — a readable, versioned document per reader: interest chips, trusted accounts, avoid list, thumb history. Not a model, not embeddings; it is passed to the editor as context.
- **Thumb** — an explicit up/down on a story; appended to the profile and reflected in tomorrow's fold.
- **Fold** — a reader's personalized selection and ordering drawn from the shared pool. The shared spine stays identical for everyone.
- **Shared spine** — Front Page, Models & Releases, Research, Tooling & Dev: the same stories for every reader.
- **Night Edition** — the dark theme.

## Sources and infrastructure

- **Source adapter** — one module per source (HN, RSS feeds, arXiv, Bluesky, X) implementing fetch → normalize. Sources are peers; swapping one is configuration, and each run reports its own counts and failure.
- **Raw item** — a fetched post, article or paper before clustering, identified by source and external id and refreshed in place; the run that last saw it is recorded.
- **Cluster key** — the deterministic identity of a story: canonical URL, entity + time window, title similarity. Clustering is deterministic; there are no embeddings.
- **Republish** — rebuilding and re-publishing an edition artifact from the recorded pool for the same day.
- **Front page** — what the reader gets: one lead and a ranked index, built from each source's latest successful run for the edition day.
- **Fetch** — one run of one source adapter: request, normalize, upsert, with a count of new and refreshed items and how long it took. A failed fetch is logged and reported, never fatal to the other sources.
- **Source line** — the line under a front-page item that names the site it came from, the date it was posted, its score and its discussion. It is the item's provenance, not decoration.

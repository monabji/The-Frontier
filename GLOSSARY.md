# The Frontier — glossary

Vocabulary used across the codebase, issues and docs. When a term here competes with a synonym, use this one.

## The paper

- **Edition** — the paper's unit of record: one immutable, dated bundle published at 06:00 IST, identified by its date (`2026-11-22`). After midnight it is frozen; corrections and late additions live in its log, never by rewriting it.
- **Edition artifact** — the content-addressed JSON + rendered HTML bundle for one edition. Archives and rollbacks read artifacts, never re-query the database.
- **Late Wire** — stories added to the current day's edition between 06:00 and 18:00, capped at 3, visibly marked with the time added. Not a second edition.
- **Quiet day** — an edition with fewer stories than target, labelled honestly in the desk note. Never padded.
- **Desk note** — the two-sentence "From the desk" opening that reads the day's shape. Machine-written, always labelled as such.

## Editorial

- **Story** — one clustered real-world event: headline, dek, summary, one verbatim source quote, one working link, optional discourse quotes. A story appears at most once per edition.
- **Candidate pool** — the day's clustered stories (~150) before the editor picks and places them.
- **Section** — Front Page, Models & Releases, Research, Tooling & Dev, The Discourse, The Long Read, Back Page. Fixed names, no quotas: a section with nothing real disappears for the day.
- **Also Today** — the one-line ticker for real-but-minor items; 10–15 entries, never padded.
- **Lead** — the Front Page story above the fold; the only story with a drop cap and (later) a credited image.
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

- **Source adapter** — one module per source (HN, RSS/company blogs, arXiv, Bluesky, X) implementing fetch → normalize, with cluster hints. Sources are peers; swapping one is configuration.
- **Raw item** — a fetched post, article or paper before clustering.
- **Cluster key** — the deterministic identity of a story: canonical URL, entity + time window, title similarity. Clustering is deterministic; there are no embeddings.
- **Republish** — rebuilding and re-publishing an edition artifact from the recorded pool for the same day.

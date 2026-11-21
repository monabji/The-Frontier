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

Clustering is a pure function of the day's pool. Two items are the same story
when, checked in this order:

1. **Same canonical URL.** Identity is the normalised URL: lowercased, `www.`
   dropped, `http` folded into `https`, campaign parameters and fragments
   removed, query sorted, trailing slash dropped.
2. **No one-word-difference.** Two headlines of the same length that differ by
   exactly one content word name two products ("Gemini 4 Neon for developers"
   vs "Gemini 4 Argon for developers"). Event verbs are stopwords, so
   "releases" against "launches" is not a difference.
3. **No version conflict.** If both titles name versions and the versions
   differ, they are two releases — "Gemini 4 Neon" and "Gemini 5 Neon" never
   merge, however alike they read. A number only counts as a version when it
   sits inside a name, so a post mentioning "3.4B parameters" is not claiming a
   release.
4. **Same content hash**, within the day: title plus text, normalised. The same
   article syndicated at two addresses is one story.
5. **Same headline up to a name**: one title's content words sit inside the
   other's ("Inkling 2 Mini" inside the blog's full headline), or the titles
   share ≥ 70% of their words.
6. **A shared name**, when the name is the whole name in both titles and the
   titles agree on more than it (≥ 25% word overlap). "Gemini 4 Argon" merges
   its launch with its coverage; "Hugging Face" alone never merges two
   Hugging Face posts.
7. **A shared rare phrase**: an adjacent pair of words that only a few of the
   day's items used ("lead azide"), together with at least three shared rare
   words. This is what catches sentence-case headlines, which never yield a
   capitalised name.

Merges 4–7 require the two items to be published within 24 hours of each other.
A new item must relate to a publication already in the cluster, not to whatever
aggregator chain reached it, so a chain cannot bridge two unrelated events.

The story's key is its primary item's canonical URL. The primary is the
publication, never an aggregator; among publications, the earliest. An
aggregator that links out (HN) beats one that links to itself (a social
permalink). Roles: `primary` (the printed link), `discussion` (an aggregator
thread or a social post about it).

The pool is rebuilt, not appended to: a rebuild replaces the day's stories, and
running it twice over the same items produces the same keys and members. An
empty pool is not a rebuild — a past day whose items have since been re-fetched
keeps the stories it has.

## Consequences

- A re-run is idempotent and inspectable: the same pool gives the same stories,
  and `/pool` shows why each item landed where it did.
- Rarity is read off the day's pool, so clustering is deterministic for a
  given pool but a very small pool has no common words; the tests use a pool
  with filler stories for that reason.
- The pool holds the week up to the edition day: 118 items became 111 stories
  on 22 November, with five genuine multi-source clusters (Inkling 2 Mini,
  GPT-6.2 Astra and Sol, the lead azide delay, the Lean verification, Datasette
  Lite). Under-merging is deliberate at the margins: two rows for one event is
  embarrassing, one story for two events is a wrong paper.
- **Editorial copy never lives on `stories`.** A rebuild deletes stale stories
  and rewrites headlines and members, so phase 4 writes dek, summary, quote and
  placement into the edition tables (`edition_entries`), which the clusterer
  never touches.
- **A past day is replayed from its artifact, not recomputed.** `raw_items` is
  current state; phase 5's artifact freezes the pool, its members and their
  roles, and reproducibility replays that. `Pool.rebuild/2` refuses to write an
  empty pool rather than erasing a day.

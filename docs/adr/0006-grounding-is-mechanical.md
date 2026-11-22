# 0006 — Grounding is mechanical; a story that fails it is dropped

**Status:** Accepted — 2026-11-22

## Context

Phase 4 asks a model to write headlines, summaries and quotes. A model can write a sentence that sounds exactly like the source and is not in it. A newspaper that prints one unverified quote has no reason to be believed on any other day. Editorial judgement cannot be delegated to the same model that produced the copy: it must be a separate, mechanical check against text the pipeline actually read.

## Decision

Every entry the editor proposes passes four checks before it is placed:

1. **Quote.** After normalising typography only — curly quotes, en/em dashes, ellipses, whitespace — the quote is a case-sensitive substring of the source text. Words are never normalised. A quote under five words fails. The reply carries the best quote plus up to two exact alternates (`quote_candidates`); the first that verifies is printed. This is a robustness measure, not a relaxation: every candidate must still be found verbatim.
2. **Entities.** Every distinctive name in the headline (`Frontier.Newsroom.Entities`) appears in the source text, compared by its alphanumeric key so hyphenation and case do not matter.
3. **Link.** A browser-like HEAD returns 2xx, or 403/405/429: bot protection and a refused method both mean a live server answering, not a missing page. A 404, a 410 or a dead host drops the story.
4. **Budget.** The summary is inside its kind's word range (lead 120–150, standard 60–80, ticker 12–18).

Failures go back to the model **once**, with the failed entry, the reason and the source excerpt. A failure after that is dropped, not printed, and written to `editor_rejections` with its reason. An edition with nothing left is an error, not an empty page.

Source text is the feed's stored excerpt when it is substantial, otherwise one fetch of the article's link. Fetched HTML is reduced to the page's `<article>` or `<main>` when either carries real prose, falling back to the whole page with navigation, headers, footers and asides removed, then bounded at 6,000 characters. Extraction reads the body, not the menu, because a menu cannot ground a quote. The article is not stored wholesale: the compliance rule is short quotes with attribution.

The model chooses and writes; `Frontier.Editor.Plan` owns caps, positions and the lead. The reply's order inside a section is its ranking; the plan turns that order into positions. The model never decides where a story goes or whether it grounded. Entity presence is checked on the headline, the one piece of copy that names a thing without context; summaries are checked against budgets and the quote check covers their factual anchor.

The edition's advertised read time is a target made of hard per-entry budgets, not a fifth per-edition reject. `Sections.read_minutes/1` estimates it at 220 words a minute and the page prints the estimate; a tight day produces a shorter paper with an honest desk note rather than padding.

Costs are recorded as whole micro-dollars per run, computed from token usage and the configured price per million. A run with no usage records zero rather than a guess.

## Consequences

- Grounding is deterministic and testable offline with fixtures; `mix test` never calls a model or the network.
- A quote that is merely close is not accepted. The failure mode is a shorter paper, never a false one.
- A source that blocks automated requests is not punished for it; a source that has deleted the page is.
- The drop log is part of the record. Quality decay shows up as rejections before it shows up as a bad page.
- Changing the prompt, caps or budgets is cheap; relaxing a check is a deliberate change to this record.

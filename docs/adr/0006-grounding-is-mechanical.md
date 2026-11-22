# 0006 — Grounding is mechanical; a story that fails it is dropped

**Status:** Accepted — 2026-11-22

## Context

Phase 4 asks a model to write headlines, summaries and quotes. A model can write a sentence that sounds exactly like the source and is not in it. A newspaper that prints one unverified quote has no reason to be believed on any other day. Editorial judgement cannot be delegated to the same model that produced the copy: it must be a separate, mechanical check against text the pipeline actually read.

## Decision

Every entry the editor proposes passes four checks before it is placed:

1. **Quote.** After normalising typography only — curly quotes, en/em dashes, ellipses, whitespace — the quote is a case-sensitive substring of the source text. Words are never normalised. A quote under five words fails.
2. **Entities.** Every distinctive name in the headline (`Frontier.Newsroom.Entities`) appears in the source text, compared by its alphanumeric key so hyphenation and case do not matter.
3. **Link.** A browser-like HEAD returns 2xx, or 403/429, which is bot protection rather than death. A 404, a 410 or a dead host drops the story.
4. **Budget.** The summary is inside its kind's word range (lead 120–150, standard 60–80, ticker 12–18).

Failures go back to the model **once**, with the failed entry, the reason and the source excerpt. A failure after that is dropped, not printed, and written to `editor_rejections` with its reason. An edition with nothing left is an error, not an empty page.

Source text is the feed's stored excerpt when it is substantial, otherwise one fetch of the article's link, reduced to readable text and bounded at 6,000 characters. The article is not stored wholesale: the compliance rule is short quotes with attribution.

The model chooses and writes; `Frontier.Editor.Plan` owns caps, positions and the lead. The model never decides where a story goes or whether it grounded.

Costs are recorded as whole micro-dollars per run, computed from token usage and the configured price per million. A run with no usage records zero rather than a guess.

## Consequences

- Grounding is deterministic and testable offline with fixtures; `mix test` never calls a model or the network.
- A quote that is merely close is not accepted. The failure mode is a shorter paper, never a false one.
- A source that blocks automated requests is not punished for it; a source that has deleted the page is.
- The drop log is part of the record. Quality decay shows up as rejections before it shows up as a bad page.
- Changing the prompt, caps or budgets is cheap; relaxing a check is a deliberate change to this record.

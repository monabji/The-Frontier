# Building The Frontier

The rule: **vertical slices, each one visible in the browser.** Never build a whole layer (all sources, then all clustering, then all UI) — the paper must run at every step.

## Toolchain

Elixir and Erlang come from mise (`.mise.toml`); no system install, no sudo.

```bash
mise install        # first time
mix deps.get
mix ecto.setup
mix phx.server      # http://localhost:4000
```

Tests: `mix test` (must run with no network and no LLM calls — fixtures only).

## Slices

Each slice ends with a working paper and a commit.

| # | Slice | Done when |
|---|---|---|
| 0 | **Hello paper** — Phoenix up, one hardcoded story rendered in the real type | the page reads as a newspaper at 390px |
| 1 | **One source** — HN adapter → `raw_items` → one story → page | running the fetch shows today's HN front page as a paper |
| 2 | **Second source** — RSS/blog adapter, dedupe by canonical URL | the same link from HN and a blog is one story |
| 3 | **Clustering** — pool of ~150 stories from all adapters | a launch covered by three sources is one story with one link |
| 4 | **The editor** — rank, assign, summarize, ground | every printed story has a verified quote and a resolving link |
| 5 | **Edition artifact** — JSON + HTML, dated, archived | yesterday's paper is still readable offline from its artifact |
| 6 | **Daily run** — Oban cron, retries, delayed-banner fallback, alert | killing the job mid-run still serves the previous edition |
| 7 | **Identity** — cookie reader, chips, profile, thumbs | a thumb changes tomorrow's fold, not today's facts |
| 8 | **Fold** — personalized extras from the shared pool | two readers see different back pages, same front page |
| 9 | **Late Wire** — capped, timestamped additions until 18:00 | a 09:00 story appears marked; an 18:01 story waits |
| 10 | **Admin + launch** — run now, force publish, 14-day streak | ten of fourteen days needed no manual fix |

## Working rules

- **Fixtures before features.** Every adapter and the editor are tested against recorded payloads. Tests never hit the network or an LLM.
- **One commit per slice**, message names the slice.
- **The page renders from stored data**, never from a live fetch.
- **Cost is a field.** Every editor run records tokens/cost; a slice isn't done if you can't say what it cost.
- **No silent fallbacks.** If grounding fails, the story is dropped and logged — never printed with a guess.
- **Keep the design live.** The stylesheet is part of slice 0, not a later coat of paint.

# The Frontier — plan

A daily, free, public newspaper for AI and tech: one dated edition each morning, finite (8–10 minutes), edited from a shared corpus, personalized only where taste belongs, archived forever.

**Non-goals for v1:** infinite feed, comments or social graph, real-time updates, reader payments, mobile app, email newsletter.

## Decisions

| Area | Decision |
|---|---|
| Promise | Complete-enough coverage of the last 24h plus a few genuinely interesting finds; the edition visibly ends |
| Audience | Public and free; anonymous readers get the default edition, personalization needs no account |
| Sources | HN, six feeds (OpenAI, Hugging Face, DeepMind, Google AI, Ars Technica, Simon Willison) and Bluesky since phase 3; arXiv joins next, filling Research. Anthropic has no public feed. X is an optional paid adapter (`≤$150/mo`), disabled until launch budget is approved |
| Relevance | LLM editor ranks a shared corpus against a readable taste profile; thumbs refine it |
| Format | One page, headline + 60–80 word summary + source quote + link; no full articles |
| Cadence | One dated edition at 06:00 IST; Late Wire until 18:00 (max 3); archive freezes at midnight |
| Sections | Front Page, Models & Releases, Research, Tooling & Dev, The Discourse, The Long Read, Back Page, plus Also Today |
| Stack | Elixir + Phoenix LiveView + SQLite + Oban, one release binary, one free VM |
| Identity | Signed anonymous cookie ID, no accounts; saveable "your paper" link |
| Design | Letterpress broadsheet: Newsreader body, Fraunces display (settled in phase 0, see `docs/DESIGN.md`), letterspaced small-cap datelines, no images in v1, Night Edition |
| Ops | Oracle Cloud Always Free ARM VM, Caddy TLS, Oban cron, alerts, delayed-edition fallback |
| Money | $0 infrastructure; LLM cents per edition; X is the only paid upgrade and is not needed to launch |

See `docs/adr/` for the decisions worth remembering and `GLOSSARY.md` for vocabulary.

## Architecture

- **The edition is an immutable artifact.** The daily job builds a JSON + HTML bundle, content-addressed and stored. The web app renders it; archives and rollbacks are storage lookups.
- **A printed day is frozen, not recomputed.** `raw_items` is current state and re-fetching moves it; a pool is rebuilt only for the current day. Phase 5's artifact freezes the pool, its members and roles, and a past day is replayed from the artifact (ADR 0004, 0005).
- **The page is a projection of the latest run.** Each source's most recent successful fetch is the pool the page reads (ADR 0004); `raw_items` is current state, and history lives in `runs` and, later, in edition artifacts. Late Wire appends entries; nothing printed is mutated.
- **Taste is a document, not a model.** Profiles are versioned JSON passed to the editor as context. No embeddings, no training.
- **Sources are adapters.** Each adapter implements `fetch/1 → normalize/1` with cluster hints. X, Bluesky, HN, RSS and arXiv are peers.
- **One process, one database.** Phoenix serves pages, Oban runs jobs, SQLite holds state. No JS build, no client framework.

### Data model (SQLite via Ecto)

| Table | Holds |
|---|---|
| `sources` | adapter key, enabled flag, config |
| `raw_items` | fetched posts/articles/papers: source + external id (the identity), URL, canonical URL, content hash, kind, discussion URL, author, title, text excerpt, score, comment count, fetch-rank position, edition day, run id, first/last seen times |
| `stories` | clustered events: edition day, cluster key, headline, canonical/primary URL, item and source counts, first/last published. Dek, summary, quote and section arrive with the editor |
| `story_items` | story ↔ raw item membership and role (primary, discussion, duplicate) |
| `editions` | day, published time, status (draft/published/late/frozen), artifact path + hash, desk note, stats |
| `edition_entries` | edition ↔ story placement: section, position, kind (lead/standard/ticker/quote), origin (edition/late/wire), and the editor's copy (dek, summary, quote, section). Editorial copy lives here, never on `stories`: the clusterer rewrites stories on every rebuild |
| `readers` | signed reader ID, first/last seen |
| `profiles` | reader ↔ versioned profile document |
| `profile_events` | append-only chips, thumb ups/downs, edits |
| `folds` | reader + day + generated payload, cached; model and cost |
| `runs` | stage, day, status, timing, cost, errors |

### Pipeline

1. **Fetch** (05:15 IST) — adapters write raw items.
2. **Normalize** — canonical URLs, dedupe by URL and content hash.
3. **Cluster** — deterministic: canonical URL, distinctive name + 24h window, title similarity ≥ 0.55 (ADR 0005). Output: the day's candidate pool, rebuilt in place.
4. **Edit** — LLM ranks, assigns sections, writes headline/dek/summary/desk note, picks 2–3 discourse quotes per story. Structured output.
5. **Ground** — quote substring check, link resolution, entity presence, word budgets. Failures retry once, then the story is dropped.

   *Where the quote is checked.* Feeds store an excerpt at fetch; HN link posts store only what the submission said. When the editor needs a verbatim quote it fetches the article once, keeps the quote and a bounded excerpt, and stores no full text (the compliance rule). Phase 4 owns this; phase 2 leaves the seam.

   *What "resolves" means.* A browser-like GET returning 2xx, or a source that answers 403/429 to automated clients and is confirmed alive in a browser. A 404 or a dead host drops the story; bot protection alone does not.
6. **Assemble** — build edition artifact, mark published, archive.
7. **Late Wire** (hourly 06:00–18:00) — new pool stories may be appended (max 3, visibly marked).
8. **Freeze** (00:00) — edition closes; archive immutable.

Fold generation is lazy: on a reader's first page load of the day, the editor builds their fold from the published pool + profile, cached in `folds`.

## Editorial rules

- **Length:** 22–25 stories, ~1,800–2,000 words, 8–10 minutes: lead 120–150 words, standard 60–80, ticker 12–18, discourse quote 25–40.
- **Caps:** Front Page 3, Models & Releases 4, Research 3, Tooling & Dev 4, The Discourse 3, The Long Read 1, Back Page 4, Also Today 10–15.
- **Once only:** a story is printed in exactly one section; cross-reference instead of duplicating.
- **Reprint window:** nothing prints twice within 72h unless materially updated, and updates are marked.
- **No link, no story:** every story has a resolving link and a verified source quote.
- **Quiet days:** shorter paper, honest desk note. No padding, no evergreen filler.
- **Compliance:** short quotes with attribution and permalinks; no full-text storage; honor source deletions within 24h; official embeds only if ever needed.

## Personalization

- The **shared spine** is identical for every reader.
- The **fold** personalizes selection and ordering in The Discourse, The Long Read and Back Page, plus the emphasis of summaries — never facts.
- Thumbs append to the profile immediately; tomorrow's fold reflects them. No per-reader fetching, so cost stays flat and facts stay coherent.

## Design

- Wordmark + date line, hairline rules, small-caps section kickers, drop cap on the lead.
- Body: **Newsreader**. Display: **Fraunces**, settled in phase 0 — the wordmark and headlines are the only place it appears, and it is named once, in `--font-display` (`docs/DESIGN.md`). Datelines/source lines: letterspaced small caps of the text face. No mono by default.
- No images in v1; a single credited source image on the lead may be earned later. No AI illustrations.
- Mobile: single column, larger type, masthead and rules retained — a broadsheet folded, not a web app.
- Night Edition: dimmed newsprint, not OLED black.

## Operations

- **06:00 IST** publish; Oban cron with exponential retry (Oban Lite on SQLite); alert to email/Telegram on failure.
- If generation fails, serve the **previous edition with a "delayed" banner** — never a blank page.
- Admin page: run job now, view run log, force publish (republish), disable a source.
- **Host:** Oracle Cloud Always Free `VM.Standard.A1.Flex` — 2 OCPU / 12 GB ARM since Jun 2026 (older guides say 4/24), Ubuntu 24.04 aarch64, 50 GB boot. Build the release for aarch64.
- **TLS/DNS:** DuckDNS subdomain behind Caddy (HTTP-01). Never nip.io/sslip.io in production — they are not on the Public Suffix List and share Let's Encrypt's global 50-certs/week budget. A real domain (~$11/yr) as soon as there are readers.
- **Firewall:** open 80/443 in both the VCN security list and the Ubuntu iptables chain (OCI images ship a REJECT rule). Egress is already open.
- **Backups:** nightly `sqlite3 .backup` → gzip → Backblaze B2 (10 GB free, 30-day retention), plus a weekly private-repo copy. Restore tested once.
- **Fallback host:** GCP e2-micro or Fly.io's under-$5 waiver if Oracle signup fails; the release is host-agnostic. Oracle signup, not capacity, is the likeliest blocker — verify the account before writing deploy automation.

## Build order

1. Infra: Phoenix app, SQLite, Oban, release on the free VM, Caddy TLS, health check.
2. Source adapters and raw-item store (HN, RSS/blogs, arXiv, Bluesky; X adapter stubbed).
3. Deterministic clustering into the candidate pool.
4. The editor: structured output, grounding checks, word budgets.
5. Edition artifact and renderer (masthead, sections, Also Today, mobile, Night Edition).
6. Daily run: cron, archive, reprint window, delayed-edition fallback, alerts.
7. Anonymous identity, onboarding chips, taste profile, thumbs.
8. Fold generation and per-day caching.
9. Late Wire with visible timestamps and counts.
10. Admin page and run log.
11. Launch: 14-day streak, domain/DNS, announcement.

## Launch bar

Fourteen consecutive days of a 06:00 edition where: every story links, a normal day has 20+ stories, the page is readable on a phone, the archive is intact, and at least 10 of the 14 days needed no manual fixing.

## Deferred

- X ingest (adapter ready, disabled): official pay-per-use, ~50 accounts, cap $150/mo, official display rules.
- RSS feed (dropped; ~30 lines when wanted), email digest, accounts/login, app.
- Lead image policy, per-edition LLM model and cost ceiling (start cheap; record cost per run).
- Domain and handle availability for "The Frontier".

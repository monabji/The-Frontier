# Phases

How the paper gets built: one phase at a time, each ending in something you can look at, judge, and change before the next one starts. Nothing here is a deadline — a phase is done when its acceptance list is true, not when the clock says so.

The build slices live in [BUILD.md](BUILD.md); this file is the working rhythm around them.

## The phase ritual

1. **Branch** — `git switch -c phase-N-name`.
2. **Build the slice** — smallest thing that makes the phase's demo real. Tests first where there is real logic (`$matt-tdd`).
3. **Look at it** — run `mix phx.server`, open it at phone width, walk the acceptance list yourself. Screenshots of the page, not test output, decide whether the phase passed.
4. **Review** — run `$code-review` on the branch (Standards + Spec). Fix findings; add a regression test for any real bug (`$matt-tdd`).
5. **Close** — merge, tick the boxes here, close the issue. If a decision moved, update `GLOSSARY.md`, `docs/PLAN.md` or add an ADR (`$domain-modeling`).
6. **Stop.** Decide explicitly: continue, change something, or leave it for a week. The repo must always be in a runnable state.

**What is cheap to change, and when.** Change these *now*, while the phase is open:

| Cheap now, expensive later | When |
|---|---|
| Typography, masthead, section treatment | Phase 0 |
| Source mix (which feeds, how many) | Phases 1–2 |
| Cluster thresholds (over/under-merging) | Phase 3 |
| Prompt voice, section caps, word budgets | Phase 4 |
| URL shape and date semantics | Phase 5 |
| Publication time, alert channel | Phase 6 |
| Onboarding chips and questions | Phase 7 |
| What the fold is allowed to personalize | Phase 8 |

Expensive to change after the fact because other things hang off them: the edition-as-artifact model (ADR 0002), anonymous identity (ADR 0003), once-only/no-link-no-story rules. Those would be a deliberate re-open, not a tweak.

---

## Phase 0 — The press is installed

**Issue:** #14 · **Size:** S

**Goal:** a Phoenix app with SQLite and Oban running locally, showing one hardcoded story in the paper's real typography.

**You'll see:** a masthead, a date line, one lead story with headline, dek, summary and source quote — readable at 390px and on a desktop.

**Build:** mise toolchain, `mix phx.new` with SQLite, Oban configured, base layout, Newsreader + chosen display face, masthead/date, the lead story component, mobile single column. GitHub Actions: format, compile with warnings-as-errors, test.

**Acceptance:**
- [x] `mix phx.server` serves the page; `mix test` and CI are green
- [x] the page reads as a newspaper at 390px, not as a web app
- [x] the display typeface is chosen and set in one place
- [x] no secrets or generated files committed

**Review gate:** the look. This is the cheapest moment to change the paper's face — do it before anything is generated.

---

## Phase 1 — One source

**Issue:** #3 · **Size:** M

**Goal:** Hacker News → `raw_items` → a page of real stories. No clustering, no LLM.

**You'll see:** today's HN front page as a paper: 20–30 items, each with a link and a source line.

**Build:** `Sources.Adapter` behaviour, HN adapter (Algolia API), `raw_items` schema with idempotent upsert, a `mix` task to fetch, fixtures recorded from the API.

**Acceptance:**
- [ ] one fetch populates `raw_items`; re-running adds nothing twice
- [ ] a failing request is logged and doesn't abort the task
- [ ] tests use fixtures only — no network in `mix test`
- [ ] every story on the page has a working link

**Review gate:** paper or link list? Does the item model miss fields you already want (author, published time, score, discussion URL)?

---

## Phase 2 — Second source, and no duplicates

**Issue:** #3 · **Size:** M

**Goal:** add RSS/company blogs, canonicalize URLs, and show the same article only once.

**You'll see:** a mixed-source paper with a source line per story and no repeated links.

**Build:** RSS adapter, canonical URL normalization (tracking params, redirects), content hash, per-source run reporting.

**Acceptance:**
- [ ] the same article from HN and a blog renders once
- [ ] one broken feed doesn't stop the others
- [ ] each source's item count is visible in the run log

**Review gate:** is this the right source mix? Decide now whether arXiv and Bluesky join here or later.

---

## Phase 3 — Clustering

**Issue:** #4 · **Size:** L

**Goal:** ~150 deterministic stories a day, each one event with its related items.

**You'll see:** the paper grouped properly — a launch reported by three sources is one story with one link and related discussion.

**Build:** cluster key (canonical URL, entity + 24h window, title similarity), `stories` + `story_items` with roles, an internal pool page for inspection.

**Acceptance:**
- [ ] golden fixture: the same launch from HN, a blog and a social post is one story
- [ ] re-running is idempotent
- [ ] no canonical URL appears in two stories
- [ ] you have hand-checked ten clusters and tuned the thresholds

**Review gate:** over-merging (two different model releases become one) or under-merging (one launch becomes six). Tune now; this is the paper-vs-feed line.

---

## Phase 4 — The editor

**Issue:** #5 · **Size:** L

**Goal:** a real edition: ranked, sectioned, summarized, quoted, grounded.

**You'll see:** the paper you subscribed to in your head — 22–25 stories, seven sections, desk note, Also Today, 8–10 minutes.

**Build:** structured-output schema, prompts, section caps and word budgets, grounding checks (quote is a substring, link resolves, entities present), drop-and-log on failure, cost per run.

**Acceptance:**
- [ ] every printed story has a verified quote and a resolving link
- [ ] an injected hallucinated quote is rejected, not printed
- [ ] the edition reads in 8–10 minutes
- [ ] cost and token use are recorded per run
- [ ] a quiet day produces a shorter paper with an honest desk note

**Review gate:** read it as a reader, not a developer. Voice, summary quality, section balance. Change prompts and caps here; never relax grounding.

---

## Phase 5 — The edition is an artifact

**Issue:** #6 · **Size:** M

**Goal:** every day becomes an immutable, dated artifact with a working archive.

**You'll see:** `/2026/11/22` and an archive index; the paper still renders with the database stopped.

**Build:** artifact JSON + HTML, content hash, storage, archive page, freeze-at-midnight semantics, reproducible rebuild.

**Acceptance:**
- [ ] the page renders from the artifact alone
- [ ] the archive lists every published day
- [ ] rebuilding a past day produces the same artifact hash from the same inputs
- [ ] nothing rewrites a frozen edition

**Review gate:** URL shape and date semantics. Cheap now, permanent later.

---

## Phase 6 — The daily run

**Issue:** #7 · **Size:** M

**Goal:** a paper every morning without you touching it, and a graceful failure when it can't.

**You'll see:** the 06:00 run happen; when you kill it mid-flight, yesterday's paper appears with a "delayed" banner and you get an alert.

**Build:** Oban cron (fetch 05:15, publish 06:00 IST), retries with backoff, run records, alert channel, previous-edition fallback, freeze.

**Acceptance:**
- [ ] a simulated failure serves the previous edition with the banner
- [ ] the failure sends an alert
- [ ] a normal run finishes well before 06:00
- [ ] every run leaves a readable log

**Review gate:** timing and the alert channel. Do you actually want 06:00, or 06:30?

---

## Phase 7 — Identity

**Issue:** #8 · **Size:** M

**Goal:** personalization without accounts.

**You'll see:** a short onboarding (chips + optional trusted accounts), a saveable "your paper" link, thumbs on stories, a plain-language privacy page.

**Build:** signed cookie reader ID, append-only `profile_events`, versioned profile document, thumbs, recovery link.

**Acceptance:**
- [ ] clearing cookies then opening the recovery link restores the profile
- [ ] a thumb appends an event and bumps the profile version
- [ ] no email, password or account exists anywhere
- [ ] the privacy page says exactly what is stored

**Review gate:** the onboarding questions. Do they produce a good first fold? Change the chips now — this is the only place a new reader can express taste.

---

## Phase 8 — The fold

**Issue:** #9 · **Size:** M

**Goal:** two readers get different papers where taste belongs, and the same paper where facts do.

**You'll see:** with two profiles, the same Front Page, Models and Research; a different Discourse, Long Read and Back Page.

**Build:** lazy fold generation per reader per day, caching, deterministic fallback when the editor call fails, cost logging.

**Acceptance:**
- [ ] the shared spine is identical byte-for-byte for both readers
- [ ] the extras differ visibly and sensibly
- [ ] a cached fold is served in one query
- [ ] a failed generation falls back to tag scoring, never a blank page

**Review gate:** is personalization doing enough to matter, without fragmenting the paper? Tune what the fold may touch.

---

## Phase 9 — Late Wire

**Issue:** #10 · **Size:** S

**Goal:** the page stays alive during the day without becoming a feed.

**You'll see:** a story that lands at 09:00 appears in a marked strip with its time; a fourth, or one after 18:00, does not.

**Build:** hourly check 06:00–18:00, append-only entries with timestamps, cap of 3, visible treatment, midnight freeze.

**Acceptance:**
- [ ] additions are visibly marked with the time added
- [ ] exactly three is the maximum; the fourth waits for tomorrow
- [ ] nothing after 18:00
- [ ] the archive still freezes at midnight

**Review gate:** does it read as a late edition or as a breaking-news feed? The copy and treatment decide it.

---

## Phase 10 — Admin, host, and launch

**Issues:** #11, #12 · **Size:** L

**Goal:** operate it at 5:59am, put it on the internet, and prove it for fourteen days.

**You'll see:** an admin page (run now, log, force publish, source toggles), a public URL, and a 14-day streak you can point at.

**Build:** admin with a single token, GCP e2-micro deploy (`$wizard` for the human-only steps), Caddy + Cloudflare, backups to B2, then the launch checklist and announcement.

**Acceptance:**
- [ ] you can trigger a run and read its log from the browser
- [ ] you can disable a broken source without a deploy
- [ ] the launch bar in `PLAN.md` is met: 14 days, ≤2 failures, 10+ no-touch days
- [ ] the public URL is live and archived

**Review gate:** the streak log. If ten of fourteen days needed manual work, the pipeline isn't done — fix that before telling anyone.

---

## Using the skills

Invoke with `$name` in chat (the agent also loads one itself when a task matches). A practical mapping:

| Skill | Use it for | In this project |
|---|---|---|
| `$matt-tdd` | test-first work | clustering, grounding checks, reprint window, canonical URLs — the logic that will quietly rot |
| `$code-review` | review the branch before merging | every phase; check Standards and Spec, not just "does it run" |
| `$diagnosing-bugs` | a failing run, a broken page, a stale edition | "the 06:00 job died", "the quote check rejects everything" |
| `$domain-modeling` | new terms and decisions | when "fold" or "cluster" starts meaning two things; anything that becomes an ADR |
| `$prototype` | throwaway experiments | paper layout variants, the fold's ranking logic before committing to it |
| `$frontend-design` | the look | phase 0 and phase 5, before the design hardens |
| `$research` | facts you shouldn't guess | an API's terms, a library's support, a pricing change |
| `$wizard` | steps only a human can take | GCP signup, DNS, the 14-day launch checklist |
| `$file-pr`, `$pr`, `$babysit-pr` | PR workflow | if you branch per phase and want review/CI tracked |
| `$grilling` | a genuinely new decision | *not* every phase — only when a question like "what is a story?" reopens |

The rhythm that works: **`$prototype` → `$matt-tdd` → `$code-review` → merge.** Prototype when the shape is unclear, test-first when the logic matters, review before it lands.

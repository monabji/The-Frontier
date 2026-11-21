# The Frontier — agent guide

A daily AI/tech newspaper. Elixir/Phoenix, SQLite, Oban; one dated edition, 06:00 IST.

- Plan and decisions: `docs/PLAN.md`
- Phases and acceptance: `PHASES.md`
- Vocabulary: `GLOSSARY.md`
- ADRs: `docs/adr/`
- Build slices: `docs/BUILD.md`

## The phase loop

Work one phase at a time, in order. Manav starts each phase; when its acceptance boxes are all checked, stop at the review gate and hand back.

A phase is done when: every acceptance box in `PHASES.md` is checked, the page has been seen at 390px in a browser, `mix test` passes, and the slice is committed on its phase branch.

Before closing a phase: tick `PHASES.md`, update `GLOSSARY.md` or `docs/PLAN.md` if a decision moved, and commit.

## Load skills yourself

Load the skill at the start of the matching work, with the skill tool. These are triggers, not suggestions.

| Work | Skill |
|---|---|
| Logic with a right answer — clustering, canonical URLs, grounding checks, reprint window, fold fallback | `matt-tdd` |
| Finishing a phase, before merge | `code-review` |
| Something broken, failing, slow or stale | `diagnosing-bugs` |
| A term or decision that moved; a new ADR | `domain-modeling` |
| A UI or state shape unclear before building it | `prototype` |
| The page's look (phases 0 and 5) | `frontend-design` |
| A fact about an external API, library, price or terms | `research` |
| A step only Manav can take — accounts, DNS, launch | `wizard` |
| Opening a PR, writing its body, watching CI | `file-pr`, `pr`, `babysit-pr` |
| A settled decision genuinely reopening | `grilling` |

When a phase spans several of these, load each as its part begins — `matt-tdd` for the logic, `code-review` for the merge.

## Non-negotiables

- Every printed story has a verified source quote and a resolving link. A failed check drops the story; it never prints with a guess.
- The page renders from stored data, never from a live fetch.
- Every adapter and the editor are tested against fixtures. `mix test` never touches the network or an LLM.
- Each editor run records tokens and cost.
- One phase per branch; a commit per working slice.

## Issue tracker

Issues live in the repo's GitHub Issues (monabji/newspaper), managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

## Domain docs

Single-context layout: `GLOSSARY.md` at the repo root and `docs/adr/`. See `docs/agents/domain.md`.

# 0011 — Eleven beats, one paper

**Status:** Accepted — 2026-11-22

## Context

The first edition was built around AI and its immediate companies: models,
research, tooling, argument and a back page. That is one reader's day, not a
newspaper for people who build software. The request is a daily paper that also
covers security and exploits, game development, app development, open source,
operations, the wider sciences (bioinformatics, quantum, blockchain, IoT) and
design (3D, VFX, motion, UI/UX), plus what technology is arguing about on
social. Twenty-odd stories, eight to ten minutes.

Two constraints shape the answer:

- The page holds one story once. A section is a beat, so a security story that
  mentions a model belongs in Security, not Models.
- A daily paper cannot fill eleven beats from one corner of the industry. The
  source mix and the prompt have to change with the sections, or the new
  headings are decoration over the old feed.

## Decision

- **Eleven sections, in print order:** Front Page, Models & Harnesses,
  Research, Security, Game Development, App Development, FOSS, DevOps,
  Frontier Science, Design, Trending. Front Page takes the day's three biggest
  stories from any beat.
- **Caps are ceilings:** 3 for Front Page, Models & Harnesses and Research; 2
  for every other beat; Also Today 5 one-line items. The editor aims for 21
  stories; a beat with nothing real disappears for the day rather than being
  padded.
- **Word budgets make 21 stories read in 8–10 minutes:** lead 140–175, standard
  80–100, ticker 12–18, desk note 20–60, at 220 words a minute.
- **Sources are chosen per beat.** Eighteen feeds join the original six: The
  Hacker News, BleepingComputer, Krebs on Security; Game Developer, Godot;
  Android Developers, React Native; Phoronix, LWN; Kubernetes, CNCF; Quanta,
  IEEE Spectrum, Quantum Computing Report, CoinDesk; 80.lv, Smashing Magazine,
  Blender. HN and Bluesky stay; Trending is what those two are arguing about
  until the paid X adapter is enabled.
- **The editor sees enough of the pool to be fair.** Candidate limit rises from
  40 to 100, so every source's first few stories reach the prompt instead of
  the top few feeds filling it. Selection stays deterministic; only the
  editor's choice is a model's.
- **Chips follow the beats.** Ten onboarding interests, one per section, so a
  reader can ask for games, open source or design.

## Consequences

- A normal day is deeper but not longer: more sources and more sections, the
  same 8–10 minute read, a higher prompt cost (about 100 candidates instead of
  40) recorded per run as before.
- Grounding is unchanged: every printed story still needs a verbatim quote and
  a resolving link. A thin beat loses its section rather than its standards.
- Some days will have no Design or Frontier Science section. That is the paper
  being honest, not incomplete.
- The feed list is now the maintenance surface. A dead feed fails alone in the
  run log; the beat it served goes quiet that day.

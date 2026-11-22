# 0008 — The morning has a deadline; a missed one is visible

**Status:** Accepted — 2026-11-22

## Context

A paper that is sometimes blank is not a daily paper. The pipeline can fail at any stage — a source is down, the model errors, the publisher cannot write — and the reader should never be the one to discover it as an empty page. The 06:00 promise also only means something if there is time to retry before it.

## Decision

- **The schedule is IST, expressed in UTC**: fetch and edit at 05:15 (23:45Z), publish at 06:00 (00:30Z), freeze the day that ended at 00:05 (18:35Z). India has no daylight saving, so fixed UTC expressions need no timezone database and cannot drift. The 45-minute window is the retry budget.
- **Fetching, editing and publishing are separate stages.** `Daily.run` fetches, rebuilds the pool, edits and assembles a draft; it never publishes. The 06:00 job publishes the draft, and refuses to publish unless the day has a successful `daily` run: a stale draft from a dead morning is not a paper. This is what makes a failed morning recoverable: a retry before 06:00 writes a draft, and the publish job is unchanged.
- **Retries are Oban's exponential backoff**, `max_attempts: 3`. Each attempt opens a run row; a retry is another row, not an edit. The day is derived from the job's enqueue time, not from when a delayed retry finally runs, so a restart past midnight cannot edit or freeze the wrong day.
- **Failure alerts a human.** Every failure sends the day, stage, attempt and reason to the configured channel: Telegram when `FRONTIER_TELEGRAM_BOT_TOKEN` and `FRONTIER_TELEGRAM_CHAT_ID` are set, any JSON webhook via `FRONTIER_ALERT_WEBHOOK_URL`, and always the log. An alert channel that itself fails is logged; it never becomes a second failure.
- **A missed deadline falls back visibly.** After 06:00, if today has no published artifact, `/` serves the most recent published edition with a "Delayed edition" strip naming its date. Before 06:00, the same edition is simply the current paper, with no banner. A draft is shown only when nothing has ever been published.
- **The day freezes at 00:05.** The midnight job freezes the day that just ended; a night with no artifact is skipped, not alarmed.
- **The run log is a command.** `runs` holds every stage; `mix frontier.log --day 2026-11-22` prints stage, source, status, counts, duration, cost and the failure reason. Scheduled jobs and the operator's manual tasks write the same rows.

## Consequences

- A reader sees either today's edition or yesterday's with an honest banner, never a blank page and never a silent stale paper.
- "Why is the paper late?" is answered by the alert and the run log, not by reading Oban's tables.
- The 45-minute window is a real budget: a run that takes longer than that has already missed its deadline, even if it eventually succeeds. The run row records the duration so the budget is observable.
- Publish and freeze failures are retried; the page's fallback is independent of the retry and holds from 06:00 onward.
- Freezing at 00:05, not 00:00, gives the last Late Wire additions (phase 9) their full window.

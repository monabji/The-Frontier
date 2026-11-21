# 0001 — Elixir/Phoenix + SQLite + Oban on one free VM

**Status:** Accepted — 2026-11-22

## Context

The paper needs three things at once: a scheduled multi-source job with retries, a public page that updates during the day, and personalization per anonymous reader. It must cost $0 to run and be interesting enough for a solo developer to want to maintain. Static hosting (GitHub Pages, Vercel) cannot host a long-lived process, a local database, or LiveView sockets.

## Decision

One Elixir/Phoenix application with LiveView, SQLite (WAL), and Oban, shipped as a single release binary to an Oracle Cloud Always Free ARM VM behind Caddy. No JavaScript build, no separate frontend, no managed database.

## Consequences

- The cron job, retry/backoff, and LiveView updates are native Oban/Phoenix features rather than assembled parts.
- SQLite means backups are file copies and rollback is trivial; it also caps write concurrency, which is fine for one daily edition and a few thousand readers.
- The whole product is one deployable unit: one binary, one database file, one systemd unit.
- We take on operator duties (VM patching, TLS, alerts). Oracle's Always Free ARM tier is 2 OCPU / 12 GB since Jun 2026 (older guides say 4/24), may reclaim idle instances, and signup itself can fail — mitigated by real traffic plus a synthetic check, off-provider backups, an aarch64 release, and a tested migration path (GCP e2-micro or Fly's under-$5 waiver).
- If free hosting disappears, the same binary runs on any €5 VPS with no rewrite.

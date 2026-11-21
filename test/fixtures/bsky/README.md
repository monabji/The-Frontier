# Recorded payloads — Bluesky

| File | Endpoint | Recorded |
|---|---|---|
| `simonwillison.json` | `https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=simonwillison.net&limit=30` | 2026-11-22 |

A real `getAuthorFeed` response: posts, their `record` text, authors, counts
and `createdAt`. The adapter reads a short list of accounts, so this one
account's feed is the shape it must handle; the second account is the same
endpoint with a different `actor`.

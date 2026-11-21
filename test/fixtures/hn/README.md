# Recorded payloads — Hacker News

Fixtures are real responses, recorded once and never re-fetched by a test.
`mix test` reads them from disk.

| File | Endpoint | Recorded |
|---|---|---|
| `front_page.json` | `https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30` | 2026-11-22 |

The payload is kept exactly as served, including the fields the adapter
ignores (`children`, `_highlightResult`), so the adapter is tested against the
shape it will actually meet. One entry is an Ask HN post with no `url`; it is
there on purpose.

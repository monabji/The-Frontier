# Recorded payloads — RSS and Atom

Fixtures are real feed responses, recorded once and never re-fetched by a
test. `mix test` reads them from disk.

| File | Endpoint | Format | Recorded |
|---|---|---|---|
| `google-ai.xml` | `https://blog.google/technology/ai/rss/` | RSS 2.0, with `content:encoded` | 2026-11-22 |
| `simon-willison-atom.xml` | `https://simonwillison.net/atom/everything/` | Atom 1.0 | 2026-11-22 |

Two shapes on purpose: RSS 2.0 dates its items with `pubDate` and puts the
address in the element's text, Atom dates with `<published>` and puts the
address in a `href` attribute. The parser must read both, so both are recorded.

Both are kept exactly as served, including the fields the adapter ignores.

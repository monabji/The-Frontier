# Recorded payloads — RSS and Atom

Fixtures are real feed responses, recorded once and never re-fetched by a
test. `mix test` reads them from disk.

| File | Endpoint | Format | Recorded |
|---|---|---|---|
| `google-ai.xml` | `https://blog.google/technology/ai/rss/` | RSS 2.0 | 2026-11-22 |
| `ars-technica.xml` | `https://arstechnica.com/feed/` | RSS 2.0 with `dc:creator` and `content:encoded` | 2026-11-22 |
| `simon-willison-atom.xml` | `https://simonwillison.net/atom/everything/` | Atom 1.0 | 2026-11-22 |

Two shapes on purpose: RSS 2.0 dates its items with `pubDate` and puts the
address in the element's text, Atom dates with `<published>` and puts the
address in a `href` attribute. `ars-technica.xml` adds the two namespaced
fields most WordPress-era feeds carry, so the prefixed lookups are exercised
against a real payload rather than assumed.

Every feed module is the same parser with a different key, label and address,
so the parser is what these three files test; the modules themselves are
covered by the feed-list test.

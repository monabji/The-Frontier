# The paper's face

Phase 0 decides how The Frontier looks. Everything below is cheap to change now
and expensive later, so it lives in one place: `assets/css/app.css`, under
`:root`. Change a token there, not in a component.

## Type

| Role | Face | Where |
|---|---|---|
| Display | **Fraunces** (variable, `SOFT` 40 / `WONK` 1) | masthead, headline, drop cap |
| Text | **Newsreader** (variable) | dek, body, quote, letterspaced lines |

Both are open-source, served from `priv/static/fonts/` as WOFF2, and named
exactly once, in `--font-display` and `--font-text`. The page makes no
third-party font request; `FrontierWeb.PageControllerTest` holds that.

**Why Fraunces, not Bodoni Moda.** Bodoni is a didone: hairline strokes that
read as a fashion title and break up at phone sizes. Fraunces is a soft
old-style with optical sizes, so the masthead keeps a letterpress warmth at
52px on a phone and at 96px on a desktop, and its `WONK` axis gives the
wordmark a little irregularity no default serif has. Newsreader was chosen
first (it is the plan's body face) and pairs with it: same era of feeling, more
calligraphic contrast.

## Stock and ink

| Token | Value | Use |
|---|---|---|
| `--paper` | `#e3dfd4` | uncoated newsprint, greyer than a magazine cream |
| `--ink` | `#191712` | warm black, never `#000` |
| `--ink-soft` | `#46423a` | deks, colophon |
| `--ink-faint` | `#6d6859` | edition flag, quiet colophon line |
| `--press-red` | `#8a3423` | the drop cap, and nothing else |

One accent, spent once. No gradients, no shadows, no cards, no rounded
corners, no images.

## Measure and scale

- Reading measure `34rem` (~63 characters of Newsreader at 18px). Masthead and
  dateline span the wider `58rem` sheet, so the page has a broadsheet's
  proportions without pretending to have columns it hasn't got.
- Body 18px / 1.55. Dek 20px italic. Headline `clamp(2.1rem, 7.2vw, 3.3rem)`.
  Masthead `clamp(2.9rem, 12.6vw, 6rem)`.
- Label device: uppercase Newsreader at 11–12px with `0.16em` tracking. It is
  only used where it carries information: edition flag, date line, section
  band, source line, quote credit.

## Rules

Three weights of hairline do all the hierarchy: 3px above the masthead, 1px for
the date band, section band, byline and quote, and nothing else. A rule is
never decoration; it separates two things that differ.

## What is deliberately absent

Navigation, buttons, flash messages, a footer sitemap, reading-time badges,
tracking, and any JavaScript the reader would need to see the page. There is
one page and it ends.

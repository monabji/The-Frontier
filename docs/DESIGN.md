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
| `--press-red` | `#8a3423` | focus rings and link hover, and the lead's drop cap when the editor returns it |

One accent, spent once per device: focus and hover are the interactive use, the
drop cap is the editorial one, and they never appear together. No gradients, no
shadows, no cards, no rounded corners, no decorative images. Photographs are the source's, credited and grayscale.

## Measure and scale

- Reading measure `34rem` (~63 characters of Newsreader at 18px). Masthead and
  dateline span the wider `58rem` sheet, so the page has a broadsheet's
  proportions without pretending to have columns it hasn't got.
- Body 18px / 1.55. Dek 20px italic. Headline `clamp(2.1rem, 7.2vw, 3.3rem)`.
  Masthead `clamp(2.9rem, 12.6vw, 6rem)`.
- **The lead, until the editor arrives.** Phases 1–3 print an index: one
  display-scale headline over a ruled two-column list, no dek, body or quote.
  The lead is distinguished by scale and the rule beneath it, not by a device.
  Phase 4 reintroduces the dek, the drop cap and the quote when there is a
  written summary to set them around.
- Label device: uppercase Newsreader at 11–12px with `0.16em` tracking. It is
  only used where it carries information: edition flag, date line, section
  band, source line, quote credit.
- **A delayed edition** carries one strip above the desk note: a red hairline box
  that names the missing 06:00 and the date the reader is actually holding. It
  is the only state message on the page, and it is never styled as an error card.
- **Read time** sits in the edition flag (`06:00 IST · 9 min read`),
  not in a badge or a card: the edition promises a length, so the page says it
  once, in the line that already names the edition.

## The two views

The paper has two server-rendered compositions, chosen by the **Standard |
Broadsheet** tabs under the date line. The switch is two links. The chosen view
travels in `?layout=reader|broadsheet` and is remembered in the signed session,
so no JavaScript is needed; the stored archive snapshot stays the Standard view.

**Standard** is the long-form reading page. On a desktop the sheet is 74rem and
the page is a 12-column grid: the Front Page lead runs full width, the two
briefs beside and below it six columns each; the bigger beats (Models &
Harnesses, Research, Frontier Science) run three across; the two-story beats
(Security, Game Development, App Development, FOSS, DevOps, Design, Trending)
run four across. Also Today is a five-column index. At tablet width the grid is
six columns and every story is two across; at 390px everything is one column.
Every story carries its summary and verified quote.

**Broadsheet** is page one. The sheet widens to 92rem, the nameplate is larger
and the date line is closed with a double rule. The Front Page lead takes the
left eight columns with a two-column body and a 16:9 photograph; the right rail
carries the desk note, the other two Front Page stories as compact briefs, and
an "Inside today" index of sections and counts. The ten remaining beats flow
as whole blocks down a two-column field, each block setting its stories in two
narrow columns. Also Today closes the page as a five-column index. It prints
the same stories and source lines as Standard, but keeps the pull quote for the
lead only; density is the point.

At 390px both views fold to one column, keep the masthead, rules and images, and
remain a paper rather than a web app. No story is printed twice in either view.

## Photography

A photograph is the source's evidence, not decoration. Use the publisher's own
feed image or `og:image`, print it grayscale with a slight contrast lift, and
credit the article's host in a small-caps caption. The lead gets a 21:9 crop in
Standard and 16:9 in Broadsheet; every other story 3:2. No
overlays, no rounded corners, no stock, no generated art. A story without an
image is set as type; no placeholder is invented to fill the hole.

## Rules

Three weights of hairline do all the hierarchy: 3px above the masthead, 1px for
the date band, section band, byline and quote, and nothing else. A rule is
never decoration; it separates two things that differ.

## Reader pages

Onboarding, your paper and privacy are set in the same sheet and the same two
faces. Chips are type-only labels with a hairline box, never pills or cards; the
selected state is the press red, used once. Thumb controls are two small-cap
words under the source line, not buttons with icons. The recovery link is a full
line of type the reader can select, not a hidden account setting.

## What is deliberately absent

Navigation, buttons, flash messages, a footer sitemap, tracking, and any
JavaScript the reader would need to see the page. There is one page and it
ends.

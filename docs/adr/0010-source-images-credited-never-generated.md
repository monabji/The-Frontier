# 0010 — Source images, credited, never generated

**Status:** Accepted — 2026-11-22

## Context

The first design decision was "no images in v1": type and rules only. The paper now asks for a broadsheet with photographs. Images change the visual identity and bring attribution and privacy obligations that a typographic page did not have.

## Decision

- **Use the publisher's own image.** A feed's `<media:content>`, `<media:thumbnail>` or image `<enclosure>` is stored as an image URL at fetch. When the editor fetches an article for source text, its `og:image`/`twitter:image` is captured in the same request. No image is generated, sourced from stock, or hotlinked from an unrelated page.
- **Store the URL, never the bytes.** The artifact carries the URL and the article link. The browser loads the publisher's asset directly; the paper does not re-host or proxy it. Offline reading therefore needs the network for photographs, while the words still render from the artifact.
- **Credit the publisher.** Every image carries a caption naming the article's host. `referrerpolicy="no-referrer"` is set so the publisher does not receive the reader's path.
- **Print it as a photograph, not a decoration.** Images are rendered grayscale with a slight contrast lift to sit in the newsprint palette; the lead gets a panoramic crop, standard stories a 3:2 crop, the Long Read a 21:9 crop. No rounded corners, no overlays, no borders beyond the paper's rules.
- **No image is not a hole.** A story without an image prints as type — headline, dek, summary, quote — with the lead's drop cap carrying the visual weight. No placeholder illustration and no "image unavailable" label.
- **The privacy page says what the reader's browser requests.** Images come from the publisher's server, not ours; that server sees the request. The page names this rather than claiming the page makes no third-party requests.
- **AI illustrations remain forbidden.** An image is evidence from the source or it is absent.

## Consequences

- The edition artifact's hash includes image URLs, so a source that changes its image produces a new version when republished; a frozen version keeps the URL it printed.
- Most company blogs and Hacker News links supply an Open Graph image; feeds without media print as type. That mix is the newspaper's real texture, not a failure.
- Attribution is structural: an image cannot render without its source caption.
- The image URL is validated as http(s) with a host; signed CDN query strings are preserved, because rewriting them breaks the asset.

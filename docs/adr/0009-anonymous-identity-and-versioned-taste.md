# 0009 — Identity is a signed cookie and a versioned document

**Status:** Accepted — 2026-11-22

## Context

Personalization without accounts is the product's promise and its main privacy risk. A login adds emails, passwords, resets and a breach surface to a free newspaper. A cookie alone is fragile: clearing it loses the profile, and a server-side identifier without a recovery path strands the reader. The shared page must also stay readable when identity is unavailable.

## Decision

- **The reader is a random ID in a signed cookie.** `frontier_reader` is HttpOnly, SameSite=Lax, Secure in production, two years, and holds a `Phoenix.Token` signed with the endpoint secret; both the cookie and the recovery token stop verifying after two years. There is no email, password, name or account anywhere in the schema. A tampered cookie is rejected and a fresh ID minted.
- **Nothing is stored on arrival.** The cookie is minted by a plug that never queries the database. A `readers` row is created on the first save — a chip, a trusted account or a thumb — not on a page view. The artifact page therefore stays a zero-database read even with identity enabled.
- **Taste is append-only events under a versioned document.** `profile_events` records each chip, trusted account and thumb with its story link, edition day and time. `profiles` holds every saved version of the JSON document (chips, trusted accounts, avoid list, thumbs, counts). A save inserts a new version; it never edits an old one.
- **A thumb is about tomorrow.** It appends an event and bumps the version immediately, and changes nothing on today's already-printed page. The fold (phase 8) reads the document on the next day.
- **The recovery link is a key.** `/recover/<token>` carries the same reader id signed with a different salt. The GET shows a confirmation page and does not rebind anything; a CSRF-protected POST restores the cookie in a browser with no saved paper, and refuses to replace a different existing reader. It is shown on `/your-paper` as both a link and a copyable field, with a plain warning that anyone holding it can restore and then change that profile.
- **Privacy is a page, not a policy paragraph.** `/privacy` names the cookie, its flags and lifetime, and lists the three tables and every field they hold. It also states what is not stored. The schema test asserts no reader/profile/event column contains `email`, `password` or `account`.
- **Erasing is explicit.** “Forget this reader” deletes the reader row and cascades every profile version and event, then clears the cookie. Clearing cookies without it leaves rows unreachable without the link.

## Consequences

- A cleared browser is recoverable only through the saved link; the UI makes that link prominent and warns what it is.
- Cross-device personalization works by sharing the link, not by logging in.
- The shared spine never depends on the reader document; facts do not vary and the page can be served from the artifact alone.
- The document is small, readable JSON, passed to the editor as context. There are no embeddings, no training and no per-reader fetching.
- The privacy page and the schema can be checked against each other; a new column is a deliberate change to both.

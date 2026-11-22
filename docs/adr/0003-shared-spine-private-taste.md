# 0003 — Shared spine, private taste, anonymous identity

**Status:** Accepted — 2026-11-22; spine amended by ADR 0011

## Context

The product is a newspaper: a shared artifact people can talk about. It is also meant to be relevant to each reader. Fully personalized editions fragment the shared artifact into a feed, multiply cost and inconsistency, and recreate the thing the product exists to replace. Accounts add auth, email, resets and privacy burdens to a free public site.

## Decision

- The news spine — Front Page, Models & Harnesses, Research, Security, Frontier Science — is identical for every reader.
- Personalization is confined to selection and ordering in the smaller beats (Game Development, App Development, FOSS, DevOps, Design, Trending) and to the emphasis of summaries. Facts never vary by reader.
- Readers are anonymous: a signed cookie ID, a versioned readable taste profile, and a saveable recovery link. No passwords, emails or accounts in v1.

## Consequences

- Everyone draws from one shared daily pool, so fetching and most LLM work are shared; per-reader cost stays in cents.
- The paper remains a common reference, which is the point of a newspaper.
- Losing a browser loses the profile unless the reader saved their link; the UI must make that link obvious.
- Cross-device personalization waits for a later login decision; the reader ID boundary keeps that migration contained.

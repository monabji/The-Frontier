# X data access for a daily AI/tech news site (Nov 2026)

**Scope:** public site, multiple readers, summarizes/links to X rather than republishing. Assumes a 30-day month, ~300 curated AI/tech accounts, 3,000–10,000 relevant posts/day including thread context, plus daily topic search. Prices are USD, read from primary sources unless marked otherwise. ✅ = verified against a primary doc/vendor page; ⚠️ = reported or inferred.

## 1. Official X API today: there are no self-serve tiers any more

X replaced Free/Basic/Pro with **pay-per-use (PPU) credits** on **6 Feb 2026** ✅ (X changelog; @XDevelopers announcement). Current pricing page (updated 3 Nov 2026, read 21 Nov 2026) lists only PPU and Enterprise. Basic ($200/mo) was retired after 1 Jun 2026; Pro ($5,000/mo) after 1 Sep 2026 ✅ (X staff forum posts, 21 May and 14 Aug 2026). The old "15k reads" / "1M reads" figures are legacy and no longer purchasable ⚠️ (vendor histories; X no longer publishes them).

| Plan (Nov 2026) | Price | Read allowance | Notes |
|---|---|---|---|
| **Pay-per-use** | Prepaid credits; $0.005/post read, $0.010/user or follow-edge read, $0.001/owned read | **3M post reads/month cap** | No subscription, no minimum. Deduped within a 24h UTC day (soft guarantee). |
| **Enterprise** | Custom, no public price; historically ~$42k/mo entry ⚠️ | Custom | Above 3M reads, custom rate limits, volume/firehose streams. |
| Free | $0 | — | Only "Public Utility" apps, case-by-case. New accounts get one-time $20 + up to $50 auto-recharge match, expiring in 3 months. |

**Cost per call:** reads bill per resource returned, so a 100-result search costs 100 × $0.005 = $0.50. Writes are per request ($0.015 plain post, **$0.200 if it contains a URL** — irrelevant for a read-only news site).

### What you can read (all included in PPU unless marked Enterprise) ✅

Rate limits from `docs.x.com/x-api/fundamentals/rate-limits`, read 21 Nov 2026.

| Need | Endpoint | Rate limit (app / user per 15 min) | Billed as |
|---|---|---|---|
| (a) User's **home** timeline | `GET /2/users/:id/timelines/reverse_chronological` | — / 180 | $0.005/post. **Reverse-chron only, excludes algorithmic ranking, requires that user's OAuth; only their own feed.** |
| (b) **List** timeline | `GET /2/lists/:id/tweets` | 900 / 900 | $0.005/post (list object $0.005) ⚠️ |
| (c) **Following** graph | `GET /2/users/:id/following` | 300 / 300 | $0.010 per edge |
| (d) **Recent search** | `GET /2/tweets/search/recent` | 450 / 300 | $0.005/post. 100 max results, 512-char query, 7-day lookback. |
| (d') Full-archive search | `GET /2/tweets/search/all` | 1/sec, 300 / 1/sec | $0.005/post. 500 max, 1,024-char query, back to 2006. Available on PPU ✅ |
| (e) **Filtered stream** | `GET /2/tweets/search/stream` | 50 / — | $0.005/post delivered. 1 connection, 1,000 rules, 250 posts/sec. |
| (f) **Thread/conversation** | recent/full search with `conversation_id:<id>` | same as search | $0.005/post. No dedicated thread endpoint; fetch replies by query. |
| (g) **User lookup by handle** | `GET /2/users/by/username/:username` | 300 / 900 | $0.010/user |
| Batch post lookup | `GET /2/tweets?ids=...` | 3,500 / 5,000 | $0.005/post, up to 100 IDs/call |

Also available: user posts (`/2/users/:id/tweets`, 10,000/900), mentions, quote tweets, reposts, likes, bookmarks, Spaces, communities, trends. **Not** available on PPU: full firehose, likes stream, PowerStream, stream webhooks (Enterprise-only) ✅.

**Key point:** the official API can build the *inputs* (accounts, lists, search, threads) but **cannot give you X's ranked "For You" feed**, and cannot give you another user's home feed.

## 2. The algorithmic "For You" feed

**No official API.** ✅ X's docs describe the home timeline endpoint as reverse-chronological and explicitly "excludes algorithmic ranking"; it needs the feed owner's OAuth token and returns only that authenticated user's feed. X open-sourced the *ranking code* (`xai-org/x-algorithm`, Jan 2026) but not data access.

Unofficial access exists only by **reverse-engineering X's internal GraphQL with a logged-in user's `auth_token` + `ct0` cookies**. Resellers sell this as a "home timeline" endpoint (GetXAPI, TwitterAPIs, twscrape). It is a clear ToS/Developer Agreement breach, breaks whenever X changes its web client, and can get the source account suspended. Do not build a public product on it.

**What broke, when** ✅:
- **Jan 2023:** Twitter cut third-party client API access; Tweetbot/Twitterrific/Talon died.
- **Mid-2023:** X blocked logged-out viewing and cut guest tokens; Nitter broke repeatedly.
- **Jan 2024:** X removed guest accounts entirely; most Nitter instances shut down.
- **Feb–Sep 2026:** Free ended for new developers (legacy Free migrated with a $10 voucher); Basic and Pro retired; PPU became the only self-serve route.
- **24 Aug 2026:** X sent Nitter a cease-and-desist (Texas Harmful Access by Computer Act + Lanham Act); repo archived 25 Aug, briefly revived, archived again 11 Sep; XCancel suspended.
- **9 Oct 2026:** New X ToS explicitly bans scraping and adds liquidated damages (see §5).

## 3. Cost math: 300 accounts, 3k–10k posts/day

Official PPU, assuming the 3k–10k figure already includes thread context:

| Line | 3,000/day | 10,000/day |
|---|---|---|
| Post reads (timelines + threads) | 90,000 × $0.005 = **$450** | 300,000 × $0.005 = **$1,500** |
| User lookups (300/day, deduped) | 9,000 × $0.010 = **$90** | **$90** |
| Topic search, +10–30% (overlap deduped) | **$45–135** | **$150–450** |
| **Monthly total** | **≈ $585–675** | **≈ $1,740–2,040** |

**Which limits bind:** cost, not throughput. Rate limits are generous (a 300-account list is a few pages per poll; 900/15min). The 3M reads/month cap equals ~100k posts/day, so it does not bind at 10k/day (10% of cap). 24h dedup means frequent polling of the same posts is free — poll list timelines every 5–15 min and only pay for new posts. Use **filtered stream** (one connection, `from:` rules for 300 accounts) if you want push instead of polling; same $0.005/post, no rate-limit juggling.

**Cheaper official variant:** curate 100 accounts and ~2,000 posts/day → 60k reads + 3k user reads + search ≈ **$350–450/mo**.

## 4. Alternatives: status and real prices (Nov 2026)

| Option | Alive? | Price | What you get | Main failure mode |
|---|---|---|---|---|
| **Official X API PPU** | ✅ | $0.005/post; $0.010/user | All public endpoints, lists, search, stream, legal cover | Bill scales linearly; credit exhaustion; policy/app review |
| **twitterapi.io** | ✅ | **$0.15/1k tweets**; plans from $29/mo; $1 free credit | Public tweets, users, lists, search, threads; no X account | Unofficial, no SLA, ToS breach, can vanish/repricing |
| **SocialData** | ✅ | **$0.20/1k** items; prepaid, no expiry; 120 req/min | Read-only tweets/profiles/followers/lists/threads | Same as above; no free plan |
| **Apify actors** | ✅ | **$0.15–$0.40/1k tweets** + Apify plan from $19/mo | Search/profile/list/thread actors, scheduling | Actor breakage when X changes; compute billed on top |
| **RSS.app** | ✅ | Free (2 feeds/5 posts/24h); **$9.99** Basic (15 feeds/60min); **$19.99** Developer (100 feeds/15min); **$99.99** Pro (500 feeds) | X profile/hashtag/search → RSS | Scraper-derived; 25–50 posts/feed cap; no thread context |
| **Nitter / XCancel** | ❌ | Free | Logged-out mirror + RSS | Dead: C&D Aug 2026, repo archived, XCancel suspended. A few volunteer instances remain, unreliable. |
| **Bluesky / AT Protocol** | ✅ | **Free** | Public firehose + Jetstream + public read API, no key/review | Coverage gap: labs and many AI accounts are not active there |
| **RapidAPI vendors** (e.g. twitter241) | ✅ | ~$0.10–$1.00/1k tweets depending on plan/volume ⚠️ | Same public reads; many separate vendors | Inconsistent quality/uptime; per-vendor ToS and billing; no accountability |

**Efficient reseller math:** with a 300-account **list**, poll every 15 min = 2,880 calls/mo. At ~100 posts/call that is 288k post reads → ~$43 at twitterapi.io, plus ~$2 profiles, plus thread calls → **~$50–70/mo**. Polling **each account individually** instead is 864k calls/mo; the $0.00015/call minimum alone is ~$130, plus tweets → **~$175/mo**. The list endpoint is the difference between hobby-cheap and not.

**Bluesky reality check** (public API, checked 21 Nov 2026) ✅:
- Free and genuinely open: `public.api.bsky.app` for reads; `wss://relay1.us-east.bsky.network` firehose; Jetstream gives filtered JSON with no auth. Limits: 3,000 requests/5 min/IP; writes 5,000 points/hr, 35,000/day per account.
- **Individuals cross-post, labs don't.** Simon Willison: 5,071 posts, last 19 Nov 2026. Ethan Mollick: 3,484 posts, last 21 Nov 2026. Anthropic's account exists (17k followers) but has **0 posts**. Karpathy's last post is **May 2023**. OpenAI/DeepMind/Meta AI/Hugging Face/Mistral official handles did not resolve or were dormant/squatted. So Bluesky is a useful *supplement* for individual AI writers, not a substitute for launch news and lab discourse.

## 5. Legal / ToS risk for a public site

- **X ToS (effective 9 Oct 2026)** ✅: you may not "access or search the Services by any means ... other than through our currently available, published interfaces"; scraping without written consent is expressly prohibited. It adds **liquidated damages of $15,000 per 1,000,000 posts** requested/viewed in any 24h period, Texas law, and a class-action waiver.
- **Developer Policy / Display Requirements** ✅: if you display posts, you must show avatar, display name, **@handle**, unmodified post text, and a timestamp linking to the permalink; use the X logo; link entities correctly. You must delete/update stored content within 24h of deletion on X. Redistribution to third parties is limited to IDs (max 1.5M IDs/30 days); up to 500 post/user objects per user/day via non-automated means. Notify X above 10M daily impressions.
- **Safest display:** use **official embeds** (`publish.twitter.com` / `platform.twitter.com`). X encourages them, and the Developer Agreement grants X a license to crawl pages containing embeds. Embeds handle attribution/display compliance and avoid copying text. Downside: slower, cookie/consent requirements, may not render for logged-out or privacy-hardened readers.
- **Summaries + short quotes:** your summary is your own text; quoting a sentence or two with clear attribution and a link is common practice and likely fair use. Don't reproduce full threads or long passages. Attribution is not a legal shield by itself, but it materially reduces both copyright and trademark exposure.
- **Caching:** storing IDs, your summaries, and metadata is fine. Building a permanent full-text archive is not — keep it current and honor deletions. For a daily newspaper, store the day's IDs and regenerate/refresh.
- **Avatars/handles:** required for post display; for a "source" chip, handle + link is lower risk than avatar use. Never imply endorsement by the author or X.
- **Third-party resellers:** you inherit the ToS problem. X has sued scrapers (Bright Data, 2023–25, settled) and sent C&Ds (Nitter, Aug 2026). Realistic exposure for a small site: low probability of a lawsuit, **high probability of API cutoff/legal letter** if you become visible or large. Not legal advice.
- **Common practice / exposure:** news sites typically embed the post, add 1–2 sentences of original summary or a short quote, and link to the permalink; they do not screenshot full threads or mirror timelines. Exposure is mostly contractual (ToS/Developer Agreement) and trademark (X marks, implied endorsement), with copyright relatively thin for short quotes but real for full-text reproduction. Profile data (handles/avatars) is publicly available, but using it to build profiles or imply endorsement raises privacy/trademark issues.

## 6. Recommendation

**Bottom line:** the cheapest *reliable* route is the **official PPU API on a curated subset** — ~$100–200/mo for 30–50 must-know accounts, ~$350–450/mo for 100 accounts / ~2k posts/day. The cheapest *workable* route for all 300 accounts is **twitterapi.io's list timeline** (~$50–70/mo) as a stopgap. Covering all 300 at 10k posts/day on the official API costs ~$1,700–2,000/mo, which is not hobby money.

**If you can spend ~$300–700/mo:** use the **official PPU API** with a curated list of 100–150 accounts, a filtered stream (or 5–15 min list polling), `conversation_id` lookups for threads, and official embeds for display. Store IDs + your own summaries, not full text. This is the only option that is both reliable and defensible; cost is the binding constraint, and 24h dedup keeps polling cheap.

**If the budget is under ~$200/mo:** go **Bluesky-first** for individual AI writers (free firehose), use the official API only for 30–50 must-have X accounts (~$100–200/mo), and embed X posts for everything else. If you must cover all 300 accounts now, **twitterapi.io list timeline at ~$50–70/mo** is the cheapest workable stopgap — but treat it as a bridge, cap spend, and keep a fallback. Do not build on Nitter, self-scraping, or session-cookie "For You" access.

**Failure modes:** official = bill spike/credit exhaustion, but recoverable; reseller = sudden shutdown or silent gaps (the Nitter precedent); RSS.app = scraper dependency and no thread context; Bluesky = missing labs and launch news; self-scrape = account bans and legal letters. Design the ingest layer so any one source can be swapped without taking the site down.

## Sources (read 21 Nov 2026 unless dated)

- X API pricing: https://docs.x.com/x-api/getting-started/pricing (updated 3 Nov 2026)
- X API rate limits: https://docs.x.com/x-api/fundamentals/rate-limits
- X API overview (PPU vs Enterprise-only): https://docs.x.com/x-api/overview
- Search/operators (conversation_id, list:, from:): https://docs.x.com/x-api/posts/search/integrate/operators
- Timelines (reverse-chron, no algorithm): https://docs.x.com/x-api/posts/timelines
- X ToS, effective 9 Oct 2026: https://x.com/en/tos
- X Developer Policy: https://docs.x.com/developer-terms/policy
- Display Requirements: https://about.x.com/company/display-requirements
- PPU launch, 6 Feb 2026: https://devcommunity.x.com/t/announcing-the-launch-of-x-api-pay-per-use-pricing/256476
- Basic retirement, 21 May 2026: https://devcommunity.x.com/t/important-update-legacy-x-api-basic-plans-are-moving-to-pay-per-use-ppu/266305
- Pro retirement, 14 Aug 2026: https://devcommunity.x.com/t/important-update-legacy-x-api-pro-plans-are-moving-to-pay-per-use-ppu/273255
- twitterapi.io pricing: https://twitterapi.io/pricing (details v2026-10-12)
- SocialData pricing: https://docs.socialdata.tools/getting-started/pricing (28 Aug 2026)
- Apify actors: https://apify.com/theagents/twitter-scraper and https://apify.com/apidojo/tweet-scraper (checked 2026-09-09)
- RSS.app pricing: https://rss.app/pricing
- Nitter C&D: https://techcrunch.com/2026/08/25/x-sends-cease-and-desist-to-open-source-project-nitter-over-alleged-scraping ; https://techcrunch.com/2026/09/15/nitter-and-xcancel-are-dead-again-after-xs-latest-legal-actions
- Nitter instance health: https://status.d420.de/
- Bluesky firehose/Jetstream: https://bsky.network/docs/relay ; https://bsky.network/docs/jetstream
- Bluesky limits: https://bsky.network/docs/rate-limits
- Bright Data case background: https://www.proskauer.com/release/proskauer-secures-dismissal-of-scraping-claims-against-bright-data

# Free hosting for a daily Phoenix newspaper ($0/month)

Research date: **22 Nov 2026**. ✅ = read on a primary/official page and quoted; ⚠️ = secondary sources, community reports, or docs that contradict themselves.
Assumptions: solo dev, 1 release binary, SQLite on local disk, Oban cron at 06:00 IST, <2,000 readers/day, no revenue, India-based signup.

## 1. Oracle Cloud Always Free (the tentative choice)

✅ [Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) (page © 2026, read 22 Nov 2026):

| Resource | Allowance | Notes |
|---|---|---|
| ARM `VM.Standard.A1.Flex` | **1,500 OCPU-h + 9,000 GB-h / month ≈ 2 OCPU + 12 GB** | one 2/12 VM or two 1/6 VMs |
| AMD `VM.Standard.E2.1.Micro` | 2 instances, 1/8 OCPU, 1 GB each | only in one AD |
| Block volume | 200 GB total (boot + block), 5 volume backups | 47 GB min stated, 50 GB default — plan 50 |
| Object storage | 20 GB combined + 50,000 API req/month | Standard/IA/Archive |
| Egress | **10 TB/month outbound** | generous; inbound free |
| Load balancer | 1 flexible, 10 Mbps | not needed here |

**2025–2026 changes (✅, material):** Oracle **halved** A1 from 4 OCPU/24 GB (3,000/18,000 h) to **2 OCPU/12 GB**, effective **15 Jun 2026**, no announcement; free-tier instances above the new ceiling were terminated after **18 Aug 2026** ([InfoQ 3 Jul 2026](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/), [Oracle community thread 21 Jul 2026](https://community.oracle.com/customerconnect/discussion/970310/oci-always-free-updated-ampere-a1-compute-allocation)). ⚠️ Oracle's own [Arm-Based Compute](https://docs.oracle.com/en-us/iaas/Content/Compute/References/arm.htm) page *still* says 3,000/18,000 — a stale page, not an entitlement. Treat 2/12 as the ceiling.

**Idle reclamation (✅, the big risk):** an instance is idle if, over 7 days, **all** of: p95 CPU <20%, network <20%, memory <20% (memory test A1-only). "Idle Always Free compute instances may be reclaimed." Notice period and whether the boot volume survives are **not documented** (⚠️). Separately, the [FAQ](https://www.oracle.com/cloud/free/faq/): accounts **idle 30+ days** may be deemed abandoned and suspended/terminated; Always Free has **no SLA and no support entitlement** (so no mandatory paid support — ✅ nothing weird there).

**Signup (✅ card required; ⚠️ India failure rate):** credit card, or debit card that "functions like a credit card"; **no PIN-debit, virtual, single-use or prepaid cards**; temporary auth hold of ~₹10,000 is reported. ⚠️ Through Oct–Nov 2026 there is a steady stream of India reports of *"We're unable to complete your sign-up"* and *"maximum number of sign-up attempts"* **after** successful card verification (SBI/HDFC/Mastercard), with support tickets unanswered for 2–17 days ([example](https://community.oracle.com/customerconnect/discussion/986162/oracle-cloud-always-free-registration-failed-after-card-verification), [r/oraclecloud](https://www.reddit.com/r/oraclecloud/comments/1xchg32/oracle_cloud_free_tier_signup_keeps_failing_even/)). Use one clean attempt: no VPN, details matching the card, one account only — attempts are capped.

**ARM capacity (✅ docs, ⚠️ severity):** "Out of host capacity" is expected, not a bug; Oracle says try another AD or wait. India West (Mumbai) and India South (Hyderabad) have **one AD each**, so AD-hopping is impossible; Hyderabad is reported marginally easier. Home region is permanent. PAYG upgrade is reported to improve success rates but buys no guaranteed capacity.

## 2. Does it fit this app?

✅ Yes, comfortably: 2 dedicated ARM cores / 12 GB for one BEAM node + SQLite + Oban is ~5–10% utilisation. Oban needs no Postgres — **`Oban.Engines.Lite` (SQLite3) is open-source core**, current Oban 2.24 ([docs](https://oban.hexdocs.pm/installation.html)). Two practical constraints: build the release for **aarch64** (build on the VM or `docker buildx` with `ubuntu:24.04-arm`), and keep SQLite in WAL mode with `busy_timeout`.

✅ **Firewall needs two layers.** Default security list allows ingress only **TCP 22** + ICMP, and **egress: allow all** (so outbound HTTPS to sources/LLM works untouched). Ubuntu images also ship an `iptables` INPUT chain ending in `REJECT`, so port 80/443 must be inserted **above** it and persisted:

```bash
# 1) Console: VCN → Default Security List → Add ingress 0.0.0.0/0 TCP 80 and 443
sudo iptables -I INPUT 6 -p tcp -m state --state NEW --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -p tcp -m state --state NEW --dport 443 -j ACCEPT
sudo apt install -y iptables-persistent && sudo netfilter-persistent save
```
([Oracle security lists doc](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securitylists.htm); UFW is disabled by design on OCI images — do not mix.)

## 3. Alternatives in Nov 2026

| Option | Free terms (Nov 2026) | Verdict |
|---|---|---|
| **GCP e2-micro** ✅ | 1 e2-micro/month in `us-west1`/`us-central1`/`us-east1`; 30 GB-months PD; **1 GB/month** egress from North America (an allowance, not per-GB price) ([free tier](https://cloud.google.com/free/docs/free-cloud-features)) | Real fallback. 1 GB RAM / 0.25–2 shared vCPU is tight for BEAM; needs a **billing account**; trial resources stop if you don't upgrade |
| **Fly.io** ✅ | No free tier. Bills **< $5/month are waived** on a personal org with a card ([free waiver](https://docs.fly.io/about/free-waiver.md)). 512 MB machine $3.69 + 3 GB volume $0.45 ≈ $4.14 | Best $0 fallback, but India egress is $0.12/GB and it's easy to cross $5 |
| **Render free** ✅ | 750 h/mo, **spins down after 15 min**, **no persistent disk**, SQLite lost on every restart; cron jobs have a **$1/mo minimum** ([free](https://render.com/docs/free), [cron](https://render.com/docs/cronjobs)) | Disqualified (no disk, no cron) |
| **Koyeb** ✅ | Starter/free plan **closed to new signups** Feb 2026 (Mistral acquisition); new accounts start at Pro **$29/mo** ([pricing](https://www.koyeb.com/pricing)) | Out (⚠️ FAQ still documents a free 512 MB instance you can't reach) |
| **Railway** ✅ | Free = **$1/mo credit**, sleeps after 5–10 min, 0.5 GB volume max ([pricing](https://railway.com/pricing)) | Out (won't run 24/7) |
| **HF Spaces** ✅ | **Docker/Gradio Spaces now need a paid plan (PRO)**; static only is free; 50 GB **non-persistent** disk; free hardware sleeps ([docs](https://huggingface.co/docs/hub/spaces-overview)) | Out |
| **Cloudflare Workers + D1 + Cron** ✅ | 100k req/day, **10 ms CPU per request and per cron trigger**, 5 cron triggers, D1 500 MB/db, 7-day Time Travel ([limits](https://developers.cloudflare.com/workers/platform/limits/), [D1](https://developers.cloudflare.com/d1/platform/limits/)) | Out: 10 ms CPU cannot fetch sources + call an LLM. Elixir/WASM exists but is experimental (BEAM.com rc.6 on Durable Objects, beamflare) — no production path for this app |
| **GitHub Actions + Pages** ✅ | Public repo: standard runners **free/unmetered**; private: **$12/mo included compute** on Free (~2,000 Linux min), 500 MB artifacts. Pages: 1 GB site, **100 GB/mo soft bandwidth**, 10 builds/h ([billing](https://docs.github.com/en/billing/managing-billing-for-your-products/about-billing-for-github-actions), [limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)) | Good for **static export + cron**, not for a long-lived Phoenix process |

## 4. Free domain/DNS + TLS

✅ All four are alive. Key finding, verified by grepping the [Public Suffix List](https://publicsuffix.org/list/public_suffix_list.dat) on 22 Nov 2026: **`duckdns.org` and `dynv6.net` are on the PSL; `nip.io`, `sslip.io` and `afraid.org` are not.**

Consequence: Let's Encrypt caps issuance at **50 certificates per registered domain per 7 days, globally across all accounts** ([rate limits, updated 5 Aug 2026](https://letsencrypt.org/docs/rate-limits/)). Because nip.io/sslip.io aren't public suffixes, **every user worldwide shares one 50/week budget** — your renewal can lose to a stranger and your TLS expires. They also don't support wildcard certs ([nip.io](https://nip.io/)).

- **Use DuckDNS** (`yourname.duckdns.org`): free, no card, on the PSL so you get your own quota, Caddy does HTTP-01 automatically. This is the correct $0 choice.
- **Do not use nip.io/sslip.io for the production site** — fine for a staging URL.
- Wildcard certs need DNS-01 (a Caddy DuckDNS plugin); unnecessary here — one hostname, one cert, ARI renewals are rate-limit exempt.
- **Cheapest real domain:** Cloudflare Registrar at cost, **.com ≈ $11.17/yr** after the 1 Nov 2026 Verisign increase ([cloudflare.com/domains](https://www.cloudflare.com/domains/)); Spaceship ~$9.98. Worth it the moment the site has readers, because it removes the DuckDNS dependency and any cookie/session scoping concerns.

## 5. Backups at $0

| Option | Terms | Simplest? |
|---|---|---|
| **Oracle Object Storage** ✅ | 20 GB + 50k requests/mo, already in the tenancy | Yes, one-line `oci os object put` from a timer — but same account as the VM, so it dies with the account |
| **Backblaze B2** ✅ | **first 10 GB always free**, no minimum fees, egress free to 3× stored ([pricing](https://www.backblaze.com/cloud-storage/pricing)) | Best off-site option; a nightly SQLite dump is ~1–3 MB |
| **GitHub private repo** ✅ | free, off-site, versioned | Easiest to set up, worst retention model (git history bloat, no lifecycle rules) |

Do this: `sqlite3 .backup` → `gzip` → **B2** nightly (keeps 30 days), plus a weekly copy to a private GitHub repo. Two providers, both $0, and neither is Oracle — that is the point.

## 6. Bottom line

**Yes — this product runs at $0 on Oracle Always Free**, with real caveats: the ARM allowance is now half what every older guide claims, the account may never get created, and the VM is reclaimable.

Concrete deploy shape: **Ubuntu 24.04 LTS aarch64** (not Minimal) on A1.Flex 2 OCPU/12 GB, 50 GB boot volume, home region Hyderabad or Mumbai.

```
/opt/newspaper/            release unpacked, owned by user `newspaper`
/var/lib/newspaper/        newspaper.db (+ -wal/-shm)
/etc/caddy/Caddyfile       newspaper.duckdns.org { reverse_proxy 127.0.0.1:4000 }
```
systemd unit `newspaper.service`: `User=newspaper`, `WorkingDirectory=/opt/newspaper`, `ExecStart=/opt/newspaper/bin/newspaper start`, `EnvironmentFile=/etc/newspaper/env`, `Restart=always`, `Environment=PHX_SERVER=true`, `Environment=PORT=4000`. Bind Phoenix to `127.0.0.1` only and let Caddy own 80/443. Cron via `Oban.Plugins.Cron` with `timezone: "Asia/Kolkata"` and `crontab: [{"0 6 * * *", Newspaper.BuildWorker}]` (needs `tzdata`). A `newspaper-backup.timer` runs the B2 dump at 04:00 IST. Set a $0 budget alert and never upgrade to PAYG mid-month without checking the sliders.

**Top 3 ways it breaks, and the mitigation:**

1. **Signup never completes** (card passes, account creation fails; attempt cap reached). → One clean attempt on a mainstream card, no VPN, name/address exactly as on the card. Have GCP e2-micro or the Fly <$5 waiver ready as plan B *before* you start, and don't retry more than twice — the cap is per-identity, not per-day.
2. **Idle reclamation or "abandoned account" suspension.** → Keep the node genuinely working: real reader traffic plus a 5-minute synthetic check on `/` (also your uptime alarm), and let the BEAM sit at a few hundred MB so memory is never near 20% of 12 GB. Keep the deploy reproducible (Dockerfile + this runbook) so a rebuild is an hour, not a weekend, and keep backups off Oracle.
3. **Capacity or policy change at rebuild time.** → Never stop the instance "to be tidy" (restart also needs host capacity). Snapshot the boot volume monthly, keep off-site backups current, and monitor Oracle's Always Free page quarterly — the June 2026 halving came with no announcement and only ~2 months' notice before termination, so assume the terms can move again.

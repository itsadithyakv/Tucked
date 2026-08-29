# Tucked — cost model and low-cost operating rules

*Standing order: Tucked runs on pocket change until revenue exists, and every recurring dollar after that must name the trigger that justified it. This document is the budget, the guardrails, and the upgrade triggers. Prices are in USD unless marked CAD, correct as of Aug 2026 — **re-verify vendor pricing before each phase**, tiers move.*

---

## 1. The shape of the budget

Three principles:

1. **Fixed costs ≈ $0 until a pilot centre exists.** Development happens on local tooling and free tiers.
2. **Costs step, never creep.** Each paid tier is adopted only when a named trigger fires (§5), never "just in case".
3. **Revenue outruns cost from centre one.** At the planned pricing (flat CAD per enrolled child, roughly $6–10/child/mo band), one 40-child centre ≈ **CA$240–400/mo** — several multiples of the entire infrastructure bill at that stage.

## 2. One-time costs

| Item | Cost | When |
|---|---|---|
| Google Play developer account | $25 once | First Android internal-testing build |
| Apple Developer Program | $99/**yr** (recurring but annual) | First TestFlight build |
| `tucked.ca` (+ `gettucked.ca`) | ~CA$15–20/yr each | Now — the plan says register immediately |
| ~~Gilroy font licence~~ | $0 | Superseded 29 Aug 2026: the identity moved to Baloo 2 + Nunito, both OFL (free, embedding included) |
| CIPO trademark filing (classes 42 + 9) + agent opinion | ~CA$500–1,200 | Business decision per the plan §12 — not an infra cost |

## 3. Recurring costs by stage

### Stage A — Discovery & development (now → first pilot). Target: **$0/mo**

| Service | Tier | Cost | Notes |
|---|---|---|---|
| Supabase | **Local via CLI** (Docker) + Free tier project | $0 | Free tier: ~500 MB db, 1 GB storage, pauses after ~1 week idle — fine for dev, never for a pilot. Full stack runs locally for daily work. |
| Expo EAS | Free tier | $0 | Limited cloud builds/mo — enough when JS changes ship via EAS Update instead of rebuilds. |
| GitHub | Free (private repo) | $0 | 2,000 Actions min/mo covers lint/test CI at solo scale; EAS builds don't run per-commit. |
| Sentry | Developer (free) | $0 | 5k errors/mo. |
| Web console hosting | Cloudflare Pages free | $0 | **Not Vercel Hobby** — its terms prohibit commercial use; Cloudflare's free tier permits it. Vercel Pro ($20/mo) only if its DX ever earns the line item. |
| Push notifications | Expo push | $0 | No OneSignal, no vendor. |
| Email (magic links) | Supabase built-in | $0 | Rate-limited (a few/hour) — acceptable for dev only. |

### Stage B — Pilot (2–3 centres, free-until-first-inspection offer). Target: **~$25–30/mo**

| Service | Tier | Cost | Trigger that moved it |
|---|---|---|---|
| Supabase | **Pro** | $25/mo | First real centre's data: no project pausing, daily backups, 8 GB db, 100 GB storage, 250 GB egress. Backups are non-negotiable once regulated records exist. |
| Email | Resend free (3k/mo, 100/day) via custom SMTP | $0 | Production magic links + CWELCC-notice delivery evidence need real deliverability. Volume at 3 centres ≈ hundreds/mo. (Amazon SES at $0.10/1k is the fallback if the daily cap ever binds.) |
| Everything else | unchanged | $0 | |

### Stage C — First 10 paying centres. Target: **~$45–70/mo**

| Service | Change | Cost | Trigger |
|---|---|---|---|
| Supabase Pro | + compute/storage as used | $25–40/mo | ~400 children × photos ≈ well inside Pro's included 100 GB for the first year (maths in §4). |
| Expo EAS | Paid plan **only if** build volume or update MAU outgrows free | +$19/mo | Named trigger: a month where free build queue actually blocked a release. |
| Sentry | Paid **only if** error volume outgrows 5k/mo | +$26/mo | Usually means a bug to fix, not a tier to buy. |
| Anthropic API (Phase 2 story polish, translation) | Haiku-class, cached | ~$2–5/mo per centre *worst case* | See §4. Drafts only; never a hard dependency. |
| Stripe (Phase 2 billing) | Per-transaction only | 0 fixed | Cards ~2.9% + 30¢; pre-authorised debit ~1% + 40¢ (verify current CA rates). Absorbed by the centre's plan — **never charged to parents**. |

**Steady-state floor at 10 centres: roughly $50/mo + $99/yr Apple — against ~CA$2,500–4,000/mo revenue at list price.** Infrastructure is never the business risk.

## 4. The two usage costs that could bite, and why they don't

**Photos (storage + egress).** Assume a busy centre: 40 children × 6 photos/week × 48 weeks ≈ 11,500 photos/yr. Client-side re-encode (2560 px long edge, q≈85, EXIF stripped except capture time) ≈ 0.7 MB each → **~8 GB/centre/yr**. On Supabase that's inside Pro's included 100 GB for the first ~12 centre-years, then $0.021/GB/mo ≈ **17¢/mo per centre-year of photos**. Egress is controlled structurally: feeds and stories serve thumbnails; the stored original moves only on explicit download/zoom. The "full-resolution, dated, lifetime archive" brand promise costs pennies *because* the resize-before-upload rule is enforced in the client.

**AI (Phase 2, optional).** Daily-story polish on a Haiku-class model ($1/M input, $5/M output): 40 stories/day × ~1,200 tokens round trip ≈ 1.4M tokens/mo ≈ **$3–4/mo per centre**, less with caching of the system prompt. Translation is per-request and labelled. Guardrails: drafts only (never compliance records — see never-do list), graceful no-AI fallback (the template-drafted story ships without it), and no AI call on any hot path.

## 5. Upgrade triggers (the "never just in case" table)

| Don't pay for | Until |
|---|---|
| Supabase Pro | The first real centre's data exists |
| A second (staging) Supabase project | A destructive-migration near-miss, or a second engineer |
| EAS paid plan | A release actually blocked by the free build queue |
| Vercel Pro | A named Next.js feature Cloudflare can't serve costs real hours |
| Sentry paid | Sustained legitimate volume past 5k events/mo |
| SMS/phone OTP (Twilio et al.) | A pilot family genuinely can't use email magic links — **phone OTP is the only "optional" auth feature with per-use cost; keep it off by default** |
| Any analytics/monitoring/flag SaaS | Never — Postgres event counts, a `settings` table, and `pg_cron` do these jobs |
| Dedicated support tooling | Past ~10 centres, a shared inbox stops working |

## 6. Engineering rules that keep the bill flat

1. **One multi-tenant Supabase project.** Tenancy is RLS rows; a new centre is an INSERT, not infrastructure.
2. **No servers, queues, or schedulers** outside Postgres + Edge Functions + `pg_cron`.
3. **Resize on the client, thumbnail on read, original on demand.**
4. **EAS Update for every JS-only change**; store builds are batched and rare.
5. **Postgres before SaaS**: analytics = event counts; search = FTS; flags = a table; audit = append-only table; cron = `pg_cron`.
6. **No per-interaction third-party calls** in any daily flow (the only external hot-path service is Expo push, which is free).
7. **Local-first development**: the Supabase CLI stack means a full day's work costs $0 and works offline.
8. **Every new vendor needs a line in this file first** — if it can't name its trigger, it doesn't get added.

## 7. What we deliberately do *not* economise on

- **Backups and no-pause database** the moment real records exist (Supabase Pro) — regulated data on a pausing free tier would be malpractice.
- **Canadian region** even if another region were cheaper — the brand promise wins.
- **Apple/Google developer accounts** — real store apps are a plan commitment (parents expect them; web push on iOS is not dependable enough).
- **Same-business-day human support** — it costs founder time, not money, and it's a sales promise from the plan.

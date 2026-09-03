# 06 — Gaps, risks and what to do next

*The honest counterpart to everything else in this folder. An honest gap list is worth more than a decorative feature list: it is what stops a pilot centre discovering a hole at the wrong moment, and it is where the next work comes from.*

**Read this before writing code.** It is faster to learn here that the airplane-mode runbook has never been run on hardware than to discover it in a pilot.

*Last reviewed: 2026-09-03.*

---

## Contents

1. [Deliberate non-goals — Won't](#1-deliberate-non-goals--wont)
2. [The ordered backlog — what to do next](#2-the-ordered-backlog--what-to-do-next)
3. [The full gap register](#3-the-full-gap-register)
4. [Needs a human — confirm before a real inspection](#4-needs-a-human--confirm-before-a-real-inspection)
5. [Known limitations in what IS built](#5-known-limitations-in-what-is-built)
6. [Risk register](#6-risk-register)
7. [The airplane-mode runbook](#7-the-airplane-mode-runbook)
8. [How to use this file](#8-how-to-use-this-file)

---

## The five kinds of "not built"

They are not the same thing, and conflating them is how a gap list stops being useful.

| Kind | Meaning |
|---|---|
| **Won't** | A deliberate non-goal. We are not going to build it, and the reason matters |
| **Not yet** | Genuinely missing. Nobody has built it |
| **Written, not wired** | The code exists but nothing calls it, deploys it, or schedules it |
| **Partial** | Some of it works; the rest is named here so nobody assumes the whole |
| **Needs a human** | Built, but a person with the regulation in front of them must confirm a value before a real inspection |

---

## 1. Deliberate non-goals — Won't

Decisions, not omissions. Changing one is a business decision, not a backlog item.

| Not building | Why |
|---|---|
| **Payment processing** | Tucked records money; it does not move it. No card rails, no PCI scope in a database holding children's photographs, and — the point — **no parent-side payment fee**. Wiring a processor is a real cost and liability decision and belongs to the founders, not to a migration |
| **Storing a social insurance number** | An individual provider's CRA receipt carries a SIN; a licensed centre's carries a business number. We serve centres. **We will not put a SIN beside a photograph of a child.** A home provider who needs one writes it on the printed receipt |
| **Payroll** | A solved, crowded, high-liability market. Integrate one day; never build |
| **Advertising or analytics SDKs anywhere near children's data** | Standing order. No third-party SDK sees a child, a photo, or a room |
| **Facial recognition or any biometric on a child** | Standing order |
| **Marketing websites for centres** | Competitors sell this. It is not compliance and it is not calm |
| **Filing anything with a regulator automatically** | CCLS serious occurrences, College reports, City returns: Tucked prepares and reminds, **a human files.** The clock and the evidence are ours; the submission is theirs |

---

## 2. The ordered backlog — what to do next

Ordered by *what would hurt most in a pilot next month*, not by size.

### Tier 1 — would break a pilot

| # | Work | Why it is first |
|---|---|---|
| 1 | **Verify the story publishing** — migration 0039 composes in SQL, publishes on `depart`, and sweeps hourly as a floor. Written with 28 pgTAP tests that **have never been run**, because Docker was down when it landed. `pnpm exec supabase db reset && pnpm exec supabase test db` | The fix itself is in; the proof is not. Until the suite runs, the loudest promise in the product is code review rather than evidence |
| 1b | **Give the educator's note a surface.** `save_story_note` is the RPC; no screen calls it, so every story ships with no human voice on top | "The educator's own note always sits on top" is currently true of the schema and false of the product |
| 2 | **Deploy `notify` and set the two `app_setting` rows** per environment, then run remote push to a real device | Now alerts are the safety-critical channel. Everything is built and proven; nothing has ever left the building |
| 3 | **Run pgTAP in CI** | The 634 most valuable tests in the repository are run by hand. One forgotten run ships a regression in regulated behaviour |
| 4 | **Run the airplane-mode runbook** (§7) on a dev build | s. 82(2) is a licensing condition. Everything is proven against a mocked AsyncStorage; a real radio and a real backgrounded app are untested |

### Tier 2 — would embarrass in an inspection or a demo

| # | Work | Why |
|---|---|---|
| 5 | **Document attachments on children's records (s. 72(1))** | A signed application exists as a *status*, not as the scan. The staff file closed exactly this gap in migration 0032; the child side is still open |
| 6 | **Child profile photo upload** | The bucket, the policies and the column all exist and are unused. Rooms show initials |
| 7 | **Allergen cross-check against menus** | s. 43(3) allergies and the ss. 42–44 menu are separate. Nothing warns that Tuesday's lunch contains an allergen a child on the posted list reacts to. The highest-value safety feature not built |
| 8 | **Annual review clock on individualised plans** | ss. 39/39.1/52 require at least annual review. There is no clock and no reminder |
| 9 | **A "give the advisor everything" export bundle** | Exports are per-module and printing is the browser's. There is no single artefact for inspection day |

### Tier 3 — real, not urgent

| # | Work |
|---|---|
| 10 | **Idempotency keys on the write RPCs** — a client command id unique per centre, across ~30 functions. Do this if §7 Q12 finds a duplicate, not speculatively |
| 11 | **A staging Supabase project** — trigger is a destructive-migration near-miss or a second engineer |
| 12 | **Dark mode in the Expo app** — needs a theme context threaded through the component library |
| 13 | **PIPEDA access/deletion workflow** with a 30-day SLA tracker and a consent-withdrawal cascade |
| 14 | **Break `room/[id].tsx` apart** — 1,075 lines doing sign-in, care logs, the nap board, bulk logging and medication |
| 15 | **Wire the nap board to `sleep_placement_options`** so an educator is offered only what the file permits |
| 16 | **PIN rate limiting** — 10,000 possibilities and nothing throttles |
| 17 | **A mechanical check that `careLogSchemas.ts` and `app.validate_care_log_payload` agree** |
| 18 | **A "did last night's sweeps run" signal** — three crons, no reporting, silent failure |

---

## 3. The full gap register

### 3.1 Ontario regulation — Not yet

| Gap | What is missing | Where it would go |
|---|---|---|
| **Service-system-manager reporting** (Toronto Children's Services) | The fee ledger and attendance register hold every number the City asks for, but there is **no export in the City's formats**. Deliberately not invented — the formats must come from discovery with an actual service agreement in hand, not from a plausible-looking CSV | New console export beside Fees & receipts |
| **Annual Child Care Operations Survey** (CCLS, as of 31 December) | Hours, enrolment, fees and agreements are all in the database; nothing assembles the survey's numbers on one page | Console export |
| **Toronto AQI support** | Nothing addresses the 1–5 assessment directly. Documentation that helps exists as a side-effect rather than as a feature | Product decision first |
| **Fee subsidy administration** | A subsidy payment can be *recorded*; the subsidy relationship — eligibility, the City's portion vs the family's, reconciliation — is not modelled | `fee_charge`/`fee_payment` extension |
| **Employer duty to report RECE matters to the College** | Not modelled at all | New workflow |
| **PIPEDA access and deletion requests** | RLS gives every family read access to their own child's record, which covers the spirit. There is no request-and-response record, no 30-day SLA tracker, and **no consent-withdrawal cascade** | New module |
| **Annual review of individualised plans** | ss. 39/39.1/52 require it; no clock exists | `individualised_plan` |
| **Immunisation schedule modelling** | "Which schedule, to which visit" is free text; nothing knows a child is due | `immunisation_record` |

### 3.2 Platform and product — Not yet

| Gap | Notes |
|---|---|
| **Staff scheduling and time clock** | `staff_shift` records who was in ratio and when, which is what the ratio engine needs. Rostering, shift swaps and a punch clock are not built |
| **Learning stories with HDLH tagging** | One story per child per day is built (though unpublished — §3.3). Tagging against *How Does Learning Happen?* and any portfolio view over time are not |
| **Home child care agency mode** | Agency → home visitor → provider → family, per-home records, visitor checklists |
| **Multi-site licensee view** | One centre per console session. `licensee` exists and owns centres; nothing aggregates |
| **Manitoba and Quebec rule packs** | `jurisdiction` seeds both as `planned`/inactive and `admin_create_centre` refuses until a pack is `implemented` (pgTAP-proven). Every rule pack that would need rows already exists as data — handbook sections, outdoor minutes, staff requirements, CWELCC parameters, policy specs, document kinds, statutory holidays — so **a province is largely rows plus a requirements document.** Quebec additionally needs French-first UI and Law 25 workflows |
| **In-app messaging attachments** | Messages are text |
| **Dark mode in the mobile app** | The console has a three-state toggle and a contrast-checked dark palette. The Expo app does not: `tokens.ts` is a TypeScript object and React Native has no CSS custom properties |
| **A parent-facing web app** | Families are mobile-only by design; there is no fallback for a family with no smartphone |
| **An audit reader** | `audit_event` is populated on every regulated write and **nothing surfaces it** |
| **Self-serve centre onboarding** | A platform admin creates every centre by hand |

### 3.3 Written, but not wired or deployed

These exist in the tree and do nothing today.

| Thing | State |
|---|---|
| ~~**The daily story**~~ | **Wired** (migration 0039). Composed by `app.story_compose`, published by a `depart` trigger, with `app.publish_daily_stories()` hourly as the floor. **Not yet run against a database** — see backlog #1 |
| **The educator's story note** | `save_story_note` is written and reachable; no screen calls it. Backlog #1b |
| **Notification opt-up preferences** | `routeNotification` accepts a `prefs.realtimeOptIn` set and is unit-tested. **No table holds it and nothing passes it.** Every family gets the default (quiet), which is why this has stayed invisible |
| **The `photos` storage bucket** | Policies written in migration 0012, consent-gated, never used. No upload surface anywhere |
| **The `photo` care-log type** | Validated, never produced |
| **`sleep_placement_options`** | Written and tested; the nap board does not call it |
| **`notify` Edge Function** | Written and correct. Needs `supabase functions deploy notify` with a `PUSH_SHARED_SECRET` and two `app_setting` rows **per environment**. Until then the dispatcher returns `not configured` — nothing is silently dropped |
| **`staff_document.kind`** values `policy_acknowledgement`, `contract`, `other` | Accepted by the schema; no surface writes them |
| **`credential_type`** value `training` | In the enum, in no requirement row, no surface |

### 3.4 Partial — some of it works

| Area | What works | What does not |
|---|---|---|
| **Children's records (s. 72(1))** | All 11 items typed, parent completion, supervisor verification, and "missing" is never blank | **No document attachments** — the same gap the staff file closed, on the child side |
| **Offline (s. 82(2))** | An AsyncStorage command queue and a zero-network evacuation cache, with 15 automated tests covering ordering, persistence across a restart, offline timestamps, visible refusals and corrupt storage | **The runbook has never been run on a device** (§7). The evacuation cache is per-device with no priming step |
| **Exports** | Attendance CSV, medication registers, printable allergy list, menu, handbook, staff file, CRA receipt, sleep register, the s. 72(6) MOH subset | No single advisor bundle, and no PDF generation — printing is the browser's |
| **Break-glass (s. 82(2))** | Read-only 24-hour unlock, loud to leadership, self-expiring, fully audited | No physical-device fallback if the whole internet is down at the centre; the evacuation cache covers the life-safety case only |
| **Ratios** | A pure, well-tested engine that runs offline | Ratio is **computed, not enforced** — a breach surfaces on a screen and has no other consequence. There is no roster, so "who should be here" does not exist |
| **The compliance calendar** | Twelve tasks, PIN-signed completions that *are* the written record, a repair log, drills that complete themselves | Cadence is "a month since last completion", so a centre that completes late drifts. No assignment to a person |

---

## 4. Needs a human — confirm before a real inspection

Each of these is **data, not code** — a row change, no deployment — but somebody with the source in front of them has to check it.

| Value | Where | What to confirm |
|---|---|---|
| **Outdoor play age floor (18 months) and the 6-hour threshold** | `outdoor_requirement`, migration 0029 | Taken from a summary, not from the s. 47 text. Flagged in the migration header too |
| **CWELCC base fee cap ($22.00/day) and the 30 June eligibility cutoff** | `cwelcc_parameter`, migration 0031 | The programme's funded rate is scheduled to change; check the current guidelines |
| **The illness policy's default exclusion periods** | `illness_policy`, seeded per centre, migration 0030 | s. 36 says the policy is developed *with the local public health unit*. The seeded set is the standard Ontario one; **every pilot centre must review it with their unit** and edit it in the console |
| **The waiting list priority order** | `app.waitlist_rank`, migration 0028 | Sibling → subsidy referral → date joined. This **must** match the waiting-list section of that centre's own handbook (s. 45), because the handbook is what the family was promised. Nothing checks the coupling |
| **Statutory holidays 2031 onward** | `statutory_holiday`, migration 0020 | Seeded 2026–2030. The serious-occurrence and public-health business-day clocks silently get *less accurate* after that. Worth a reminder, not a cron |
| **First aid renewal interval (3 years)** | `staff_requirement`, migration 0032 | Used only to compute "expiring soon"; the certificate's own printed expiry always wins because it is what gets recorded |
| **44 months as the school-age proxy** | `app.immunisation_rules`, migration 0024 | Hard-coded rather than a jurisdiction row |

---

## 5. Known limitations in what IS built

Not gaps exactly — decisions with a consequence somebody should be able to explain.

- **Serious occurrence descriptions are not scrubbed by the child anonymiser.** They are Ministry-filed records with their own lifecycle. The console guidance encourages not naming children in free text; **nothing enforces it.** The anonymisation check on a *posted summary* is name-matching, so it catches "Maya Osei" and not "the little girl in the toddler room whose mum drives the red car".
- **CRA receipts keep names for six years**, outliving the three-year children's-record anonymiser, because O. Reg. 138/15 s. 27.1 requires it. Two retention duties in tension, resolved in favour of both — but **a family asking "delete everything about my child" cannot have the receipts until then**, and somebody should be able to say so out loud.
- **Joining the waiting list is a staff act.** s. 75.1 requires self-serve *position*, which is built and works with no account. Self-serve *joining* would need a public write endpoint and rate limiting.
- **The evacuation cache is per-device.** A device that has never been online has nothing cached, and nothing warns about it.
- **One centre per console session.** A supervisor of two centres signs out and back in.
- **A lost response on a flaky connection can duplicate a regulated record.** The offline queue only learns "network error" — it cannot tell "the write never arrived" from "the write succeeded and the reply was lost", so it retries, and the RPCs carry no idempotency key. Marginal signal is exactly the condition that produces this, which is why §7 step 4 exists. The fix is a client command id unique per centre on the write RPCs — roughly thirty functions, which is why it is written down here rather than done speculatively.
- **A push is "delivered" when Expo's receipt says so** — as far as any sender can see. Tucked reads tickets *and* receipts, sets `delivered_at` from the first ok receipt, and surfaces `push_never_arrived` when every device's receipt failed. **What no receipt can tell you is whether a human looked at the phone**; for that, a Now alert still asks to be acknowledged in the app, and the console shows what is unacknowledged.
- **Release to somebody not on the authorised list is permitted and recorded.** Only an explicit `pickup_restriction` blocks anything. A centre expecting Tucked to *stop* an unauthorised pickup will be disappointed.
- **Attestation is a button, not comprehension.** It matches what s. 46 asks for; nobody should mistake it for training.

---

## 6. Risk register

| Risk | Likelihood | Impact | Mitigation today | Gap |
|---|---|---|---|---|
| **A database regression ships because pgTAP was not run** | Medium | **High** — regulated behaviour | 634 tests exist and are fast | They do not run in CI. Backlog #3 |
| **A migration breaks every centre at once** | Low | **High** | One project is one blast radius; pgTAP + local reset | No staging environment. Backlog #11 |
| **`create or replace function` drops an earlier amendment** | Medium | High | Happened once, caught by the suite | Nothing prevents it. [04 §9.2](04-data-security-and-platform.md) |
| **A `security_invoker` view reasons about absence and lies** | Medium | Medium | Hit three times, each fixed with a definer helper and a tombstone test | No lint. [04 §9.1](04-data-security-and-platform.md) |
| **A duplicate regulated record on marginal signal** | Unknown | Medium | Documented; §7 step 4 hunts for it | No idempotency key |
| **A `pg_cron` sweep fails silently** | Medium | Medium | `stuck_push_alerts` covers push only | No general sweep-health signal. Backlog #18 |
| **Push never reaches a device in production** | Medium | **High** — the safety channel | Tickets, receipts, retries, dead-token retirement, three console views | Never tested on hardware. Backlog #2 |
| **The evacuation screen is empty on a never-online device** | Low | **High** — life safety | Cache refreshed whenever Room mode loads | No priming step, no staleness warning |
| **A seeded regulatory value is wrong at inspection** | Medium | Medium | Every one is listed in §4 and flagged in its migration header | Needs a human, not code |
| **The waiting-list order contradicts the handbook** | Medium | Medium | Both are recorded | Nothing compares them |
| **A PIN is guessed on a device inside the centre** | Low | Medium | bcrypt, care-role check, full audit trail | No rate limiting. Backlog #16 |
| **Cost model meets reality and is wrong** | Low | Low | Conservative, with named upgrade triggers | Never measured against a real centre |

---

## 7. The airplane-mode runbook

*The scripted quality pass on a real device, owed since the offline work landed. Everything the queue's own logic can be held to is automated in `apps/mobile/test/queue.test.ts`. **This runbook is only for what a test cannot see**: a real radio, a real OS killing a backgrounded app, a real basement.*

O. Reg. 137/15 **s. 82(2)** is the reason. Records kept electronically must be available to staff at all times, and the Licensing Manual specifically contemplates a phone used for attendance working off-site. **A screen that says "no connection, try later" during an evacuation is the failure this runbook exists to catch.**

### Already proven without a device — do not spend device time here

| Proven | Test |
|---|---|
| An online write goes straight through, unqueued | `s82_2_an_online_write_goes_straight_through_and_is_not_queued` |
| A refused write (bad PIN, broken rule) is **never** queued — the educator is standing there and can fix it | `s82_2_a_refused_write_is_never_queued_because_the_person_is_standing_there` |
| A write with no signal is kept | `s82_2_a_write_with_no_signal_is_kept_rather_than_lost` |
| Later writes join the line rather than jumping it | `s82_2_later_writes_join_the_line_rather_than_jumping_it` |
| The queue flushes in the order it was written | `s82_2_the_queue_flushes_in_the_order_it_was_written` |
| Every queued write carries the moment it actually happened | `s82_2_every_queued_write_carries_the_moment_it_actually_happened` |
| A flush that hits the network again stops and keeps the order | `s82_2_a_flush_that_hits_the_network_again_stops_and_keeps_the_order` |
| A server refusal becomes visible and does not block what is behind it | `s82_2_a_rule_the_server_refuses_lands_in_front_of_a_human`, `s82_2_a_refusal_does_not_block_the_writes_behind_it` |
| The queue and its failures survive the app being shut | `s82_2_a_queued_write_survives_the_app_being_shut`, `s82_2_a_visible_failure_survives_it_too` |
| Corrupt storage starts empty rather than bricking the room device | `s82_2_corrupt_storage_starts_empty_rather_than_crashing_the_room_device` |

```bash
pnpm --filter @tucked/mobile test
```

### Before you start

- A **dev build** on a real phone. Expo Go cannot do remote push and behaves differently in the background. **Ask before building — no EAS build is made without an explicit go-ahead.**
- The device signed in as the educator, on the room board.
- A second device or a laptop on the console, to watch the other side.
- A stopwatch. Several steps are about how long something takes to *feel* wrong.

### 1. The basic loop (5 minutes)

1. Open a room. Sign one child **in**. Confirm it appears on the console.
2. Airplane mode **on**. Wait for the app to notice. **Watch for** a calm, quiet indication that writes are being kept — not a red error, not a modal, not a spinner that never resolves.
3. Sign a second child **in**, a third **absent**, and record a nappy change.
4. **Q1 — did every action complete without the app arguing?** The educator should not be able to tell the difference except for the pending indicator.
5. Airplane mode **off**. Do not touch the app.
6. **Q2 — how long until the queue drains on its own?**
7. **Q3 — on the console, are the three records in the order they were made, with the times they were made — not the time the signal returned?**

### 2. The evacuation (10 minutes) — the one that matters

1. Airplane mode **on**.
2. **Force-quit the app.** Swipe it away. This is the step most likely to find something.
3. Reopen. **Q4 — does the evacuation screen open with no network at all?**
4. **Q5 — does it show every child currently signed in, their emergency contacts and the allergy list, with no spinner and no empty state?**
5. Walk outside, out of Wi-Fi range, still on airplane mode. **Q6 — does anything change or degrade once you are away from the building?**
6. Record an evacuation headcount, deliberately leaving one child uncounted.
7. **Q7 — does the missing-child prompt appear, and does it name the child?**
8. Airplane mode off. **Q8 — does the headcount arrive on the console with the missing-child snapshot intact?**

### 3. The long outage (20 minutes, mostly waiting)

1. Airplane mode **on**. Record **ten** actions across several children.
2. Leave the app **backgrounded for fifteen minutes**. Use other apps. Let the screen lock. *This is where iOS or Android may kill the process. That is the point.*
3. Reopen. **Q9 — are all ten still pending?**
4. Airplane mode off. **Q10 — do all ten arrive, in order, with their original times?**
5. **Q11 — does the pending indicator return to zero, or does it stick?**

### 4. Flaky signal, not absent signal (10 minutes)

The hardest real case: a basement with one bar, not a plane.

1. Find genuinely marginal signal — a stairwell, a basement, a lift lobby.
2. Record five actions in quick succession while walking in and out of coverage.
3. **Q12 — does anything appear twice on the console?** *(See §5 — if it does, capture exactly what you did.)*
4. **Q13 — does anything go missing entirely?** This must be **no**.
5. **Q14 — does the app ever show an error the educator cannot act on?**

### 5. Refusals from the far side (5 minutes)

1. On the console, exclude a child (Illness & exclusions).
2. On the device, airplane mode **on**, and sign that child **in**.
3. Airplane mode off and let it flush.
4. **Q15 — does the refusal appear as a visible, readable failure naming the child and the reason — rather than disappearing?**
5. **Q16 — can a person dismiss it once they have dealt with it, and does the dismissal stick after a restart?**

### What to watch for at Q12

A command that reached the server but whose **response** was lost — the write succeeded, the reply did not — is retried on the next flush, because the queue only learns "network error". There is no idempotency key on the RPCs, so that retry can create a **duplicate regulated record**.

Marginal signal is exactly the condition that produces it. **If Q12 finds a duplicate, capture the two rows and the sequence of actions** — that evidence is what would justify backlog #10.

### The record

| | Question | Answer | Notes |
|---|---|---|---|
| Q1 | Every offline action completed without argument | | |
| Q2 | Seconds until the queue drained by itself | | |
| Q3 | Order and original times preserved on the console | | |
| Q4 | Evacuation screen opens with no network | | |
| Q5 | Children, contacts and allergies all present | | |
| Q6 | Still works away from the building | | |
| Q7 | Missing-child prompt names the child | | |
| Q8 | Headcount arrives with its snapshot | | |
| Q9 | All ten survive fifteen minutes backgrounded | | |
| Q10 | All ten arrive in order with original times | | |
| Q11 | Pending indicator returns to zero | | |
| Q12 | Anything duplicated on flaky signal | | |
| Q13 | Anything lost on flaky signal | | |
| Q14 | Any error an educator cannot act on | | |
| Q15 | Server refusal is visible and readable | | |
| Q16 | Dismissal sticks across a restart | | |

**Device / OS / build:** \
**Date and tester:** \
**Verdict:** pass / pass with notes / fail

File the completed table in `docs/`. **A pass with an unanswered row is not a pass.**

---

## 8. How to use this file

Add to it whenever you decide *not* to build something, and delete from it the moment something lands — **with the test name that proves it**, in [docs/compliance-test-report.md](../docs/compliance-test-report.md).

A gap that is written down is a plan. A gap that is only known is a surprise.

One more habit worth keeping, from that report: when a verdict turns out to have been wrong, **correct it in a way that says it was wrong** rather than quietly upgrading the row. A report whose ✅ can drift is worth less than one that says where it drifted.

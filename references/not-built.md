# What is NOT built

*Last reviewed: 2026-08-31 (push delivery and its receipts have both landed; see the strikethrough in §4). This is the honest counterpart to [docs/compliance-test-report.md](../docs/compliance-test-report.md), which lists what IS built and proves it. An honest gap list is worth more than a decorative feature list: it is what stops a pilot centre discovering a hole at the wrong moment, and it is where the next work comes from.*

Five kinds of "not built" appear below, and they are not the same thing:

| Kind | Meaning |
|---|---|
| **Won't** | A deliberate non-goal. We are not going to build it, and the reason matters. |
| **Not yet** | Genuinely missing. Nobody has built it. |
| **Written, not wired** | The code exists but nothing calls it, deploys it, or schedules it. |
| **Partial** | Some of it works; the rest is named here so nobody assumes the whole. |
| **Needs a human** | Built, but a person with the regulation or the local rules in front of them has to confirm a value or a wording before a real inspection. |

---

## 1. Deliberate non-goals — **Won't**

These are decisions, not omissions. Changing one is a business decision, not a backlog item.

| Not building | Why |
|---|---|
| **Payment processing** | Tucked records money; it does not move it. No card rails, no PCI scope in a database holding children's photographs, and — the point — **no parent-side payment fee**. The centre records what arrived (pre-authorised debit, e-transfer, cheque). Wiring a processor is a real cost and liability decision and belongs to the founders, not to a migration. |
| **Storing a social insurance number** | An individual provider's CRA receipt carries a SIN; a licensed centre's carries a business number. We serve centres, we hold the business number, and we will not put a SIN beside a photograph of a child. A home provider who needs one writes it on the printed receipt. |
| **Payroll** | A solved, crowded, high-liability market. Integrate one day; never build. |
| **Advertising or analytics SDKs anywhere near children's data** | Standing order. No third-party SDK sees a child, a photo, or a room. |
| **Facial recognition, or any biometric on a child** | Standing order. |
| **Marketing websites for centres** | Competitors sell this. It is not compliance and it is not calm. |
| **Filing anything with a regulator automatically** | CCLS serious occurrences, College reports, City returns: Tucked prepares and reminds, a human files. §9.14. The clock and the evidence are ours; the submission is theirs. |

---

## 2. Ontario regulation — **Not yet**

Everything in O. Reg. 137/15 that the [compliance test report](../docs/compliance-test-report.md) marks ✅ is built and machine-proven. What follows is what is not.

| Gap | What is missing | Where it would go |
|---|---|---|
| **Service-system-manager reporting** (Toronto Children's Services) | The fee ledger and the attendance register hold every number the City asks for, but there is **no export in the City's formats**. Deliberately not invented — the formats have to come from discovery with an actual service agreement in hand, not from a plausible-looking CSV. | New console export beside Fees & receipts |
| **Annual Child Care Operations Survey** (CCLS, as of 31 December) | Hours, enrolment, fees and agreements are all in the database; nothing assembles the survey's numbers on one page. | Console export |
| **Toronto AQI support** | Nothing addresses the 1–5 assessment directly. Documentation that helps (observations, programming records) exists as a side-effect rather than as a feature. | Product decision first |
| **Fee subsidy administration** | A subsidy payment can be *recorded* (`fee_payment.method = 'subsidy'`), but the subsidy relationship itself — eligibility, the City's portion vs the family's, reconciliation — is not modelled. | `fee_charge`/`fee_payment` extension |
| **Inspection reports kept on the premises** (Ministry, public health, fire) | s. 36 and the Licensing Manual require these on site. There is no store for them. The `evidence` bucket and `staff_document` pattern would extend cleanly to a centre-level document shelf. | New `centre_document` table + bucket path |
| **Employer duty to report RECE matters to the College** | Not modelled at all. | New workflow |
| **Program statement review and prohibited-practices attestation** (s. 46) | The program statement is a handbook section, and the handbook is versioned and acknowledged by parents — but there is no annual review cycle for the statement itself, and **no record that each staff member has read the prohibited practices**, which is what an advisor asks for. | `compliance_task` + a staff acknowledgement, mirroring the handbook |
| **Policy acknowledgements by staff** | Police record check policy, staff training policy, volunteer/student supervision policy. `staff_document.kind` already has a `policy_acknowledgement` value; nothing writes it. | Staff files page |
| **s. 33.1 parent-requested sleep variations** | Back-to-sleep and the check cadence are enforced; a physician's or parent's written variation is not modelled the way the s. 47 outdoor exemption is. | Copy the `outdoor_exemption` shape |
| **PIPEDA access and deletion requests** | The 30-day SLA workflow noted in the plan. RLS gives every family read access to their own child's record, which covers the spirit; there is no request-and-response record, and no consent-withdrawal cascade. | New module |

---

## 3. Platform and product — **Not yet**

| Gap | Notes |
|---|---|
| **Staff scheduling and time clock** | `staff_shift` records who was in ratio and when, which is what the ratio engine needs. Rostering, shift swaps and a punch clock are not built. P2 bundle in the plan. |
| **Child profile photo upload** | `child.photo_path` exists and rooms fall back to initials, but there is **no upload UI on any surface**. The `photos` bucket and its consent-gated policies are in place and unused. |
| **Learning stories with HDLH tagging** | One story per child per day is built. Tagging against *How Does Learning Happen?* domains, and any portfolio view over time, are not. |
| **Home child care agency mode** | Agency → home visitor → provider → family, per-home records, visitor inspection checklists. P3. |
| **Multi-site licensee view** | One centre per console. `licensee` exists and owns centres; nothing aggregates across them. P3. |
| **Manitoba and Quebec rule packs** | `jurisdiction` seeds CA-MB and CA-QC as `planned`/inactive, and `admin_create_centre` refuses to create a centre in a jurisdiction whose pack is not `implemented` (pgTAP-proven). Every rule pack that would need rows already exists as data — handbook sections, outdoor minutes, staff requirements, CWELCC parameters, statutory holidays — so a province is largely rows plus a requirements document. Quebec additionally needs French-first UI and Law 25 workflows. |
| **In-app messaging attachments** | Messages are text. |
| **A parent-facing web app** | Families are mobile-only by design; there is no web fallback if someone has no phone. Worth revisiting with a pilot centre. |

---

## 4. Written, but not wired or deployed

These exist in the tree and do nothing today. Each is a small piece of work, and each is a real hole until it is done.

| Thing | State |
|---|---|
| ~~**Push notification delivery**~~ | **Built** (migration 0033). The selection rule lives in `app.notifications_to_push` and is pgTAP-proven; pg_cron dispatches every two minutes through pg_net; failures are retried and never marked as sent; dead tokens are retired; unreachable and stuck alerts surface on the console home. **Two things remain per environment**: `supabase functions deploy notify` with a `PUSH_SHARED_SECRET`, and the two `app_setting` rows the migration's footer spells out. Until those exist the dispatcher returns `not configured` and nothing is silently dropped. Remote push still needs the EAS dev build to reach a real device. |
| **The `photos` storage bucket** | Policies written in migration 0012, consent-gated, never used. |
| **`staff_document.kind` values `policy_acknowledgement`, `contract`, `other`** | Accepted by the schema; no surface writes them. |
| **`credential_type` value `training`** | In the enum, not in the requirement pack, no surface. |

---

## 5. Partial — some of it works

| Area | What works | What does not |
|---|---|---|
| ~~**Daily written record (s. 37)**~~ | **Complete.** `app.dwr_compose` drafts the day from its own rows and quotes every cross-reference verbatim; the console previews and redrafts; a closed day refuses both. The second drafter that lived in `packages/domain` and nothing called has been removed — one implementation, not two. | — |
| **Children's records (s. 72(1))** | All 11 items typed, parent completion, supervisor verification, and "missing" is never blank. | No document attachments against a record item — the same gap the staff file just closed, on the child side. |
| **Offline (s. 82(2))** | AsyncStorage command queue and zero-network evacuation cache, now with **15 automated tests** covering ordering, persistence across a restart, offline timestamps, visible refusals and corrupt storage. The device script is written: [airplane-mode-runbook.md](airplane-mode-runbook.md). | **The runbook has not been run on a device.** It needs a dev build, which nobody has asked for yet. |
| **Exports** | Attendance CSV, medication registers, printable allergy list, printable menu, printable handbook, printable staff file, printable CRA receipt, s. 72(6) medical-officer subset. | No single "give the advisor everything" bundle, and no PDF generation — printing is the browser's. |
| **Break-glass (s. 82(2))** | Read-only 24-hour unlock, loud to leadership, self-expiring, fully audited. | No physical-device fallback if the whole internet is down at the centre; the evacuation cache covers the life-safety case only. |

---

## 6. Needs a human — confirm before a real inspection

Each of these is **data, not code** — a row change, no deployment — but somebody with the source in front of them has to check it.

| Value | Where | What to confirm |
|---|---|---|
| **Outdoor play age floor (18 months) and the 6-hour threshold** | `outdoor_requirement`, migration 0029 | Taken from the summary in [tucked-ontario-requirements.md](tucked-ontario-requirements.md) §9, not from the s. 47 text. Flagged in the migration header too. |
| **CWELCC base fee cap and eligibility cutoff** | `cwelcc_parameter`, migration 0031 | $22.00/day and the 30 June cutoff. The programme's funded rate is scheduled to change; check against the current guidelines. |
| **The illness policy's default exclusion periods** | `illness_policy`, seeded per centre, migration 0030 | s. 36 says the policy is developed *with the local public health unit*. The seeded set is the standard Ontario one; every pilot centre must review it with their unit and edit it in the console. |
| **The waiting list priority order** | `app.waitlist_rank`, migration 0028 | Sibling → subsidy referral → date joined. This **must** match the waiting-list section of that centre's own handbook (s. 45), because the handbook is what the family was promised. |
| **Statutory holidays 2031 onward** | `statutory_holiday`, migration 0020 | Seeded 2026–2030. The serious-occurrence and public-health business-day clocks silently get less accurate after that. Worth a reminder, not a cron. |
| **First aid renewal interval (3 years)** | `staff_requirement`, migration 0032 | Used to compute "expiring soon"; the certificate's own printed expiry always wins because it is what gets recorded. |

---

## 7. Known limitations in what IS built

Not gaps exactly — decisions with a consequence somebody should know about.

- **Serious occurrence descriptions are not scrubbed by the child anonymiser.** They are Ministry-filed records with their own lifecycle. The console guidance encourages not naming children in free text; nothing enforces it.
- **CRA receipts keep names for six years**, outliving the three-year children's-record anonymiser, because O. Reg. 138/15 s. 27.1 requires it. The names are snapshots on the receipt and are redacted by `app.run_financial_sweep` at six years. Two retention duties in tension, resolved in favour of both — but a family asking "delete everything about my child" cannot have the receipts until then, and somebody should be able to explain that.
- **Joining the waiting list is a staff act.** s. 75.1 requires self-serve *position*, which is built and works with no account. Self-serve *joining* would need a public write endpoint and rate limiting.
- **The evacuation cache is per-device.** A device that has never been online has nothing cached.
- **One centre per console session.** A supervisor of two centres signs out and back in.
- **A lost response on a flaky connection can duplicate a regulated record.** The offline queue only learns "network error" — it cannot tell "the write never arrived" from "the write succeeded and the reply was lost", so it retries, and the RPCs carry no idempotency key. Marginal signal is the condition that produces this; §4 of the [airplane-mode runbook](airplane-mode-runbook.md) exists to hunt for it. The fix, if a device pass finds one, is a client command id unique per centre on the write RPCs — a change across roughly thirty functions, which is why it is written down here rather than done speculatively.
- **A push is "delivered" when Expo's receipt says so** — which is as far as any sender can see. Tucked reads tickets *and* receipts (migration 0035), sets `delivered_at` from the first receipt that comes back ok, and surfaces `push_never_arrived` when every device's receipt failed. What no receipt can tell you is whether a human looked at the phone; for that, a Now alert still asks to be acknowledged in the app, and the console shows what is unacknowledged.

---

## How to use this file

Add to it whenever you decide *not* to build something, and delete from it the moment something lands — with the test name that proves it, in [docs/compliance-test-report.md](../docs/compliance-test-report.md). A gap that is written down is a plan; a gap that is only known is a surprise.

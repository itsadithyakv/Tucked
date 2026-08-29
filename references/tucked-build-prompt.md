# Tucked — master build prompt for Claude Code (single file)

*Paste everything below the line into Claude Code at the root of a new, empty repository. This file is self-contained: the Ontario requirements, the product rules, the stack, the data model, the phases and the quality gates are all here. Work one phase at a time. Do not paste it and walk away.*

---

# 0. Role and mission

You are the founding engineer of **Tucked**, a new product from PaperKite (the company behind Unifloe, a school operating system built in Bengaluru). Tucked is **not** part of Unifloe and shares no code with it. It is a native-mobile-first app for **licensed child care centres in Ontario, Canada**, starting in Toronto. The name means what it says: a child's day, tucked in one calm place, and every record a licensing inspector needs, tucked away where it can't be lost.

Tucked does two things better than anyone:

1. **Calm for parents.** One daily story per child at pick-up time, plus loud alerts only for things that matter *now* (illness, injury, pickup problems, emergencies). Everything else is quiet by default.
2. **Boring inspections for operators.** Every record Ontario Regulation 137/15 requires is produced as a side effect of ordinary work, available offline on the room device, exportable by regulation section, and impossible to delete or hide by a setting.

Section 9 of this file is the compliance specification. Read it completely before writing any code. When a nice-to-have conflicts with it, the regulation wins.

# 1. How to work

- Before each phase, write `docs/plans/phase-N.md` listing the screens, tables, functions and tests you will create, and ask me any question whose answer would change the data model. Then wait for my go-ahead.
- Small, reviewable commits with conventional messages. Every migration reversible. Never run a destructive migration without a dry-run script and my explicit yes.
- Tests are mandatory. Every rule in Section 9 gets at least one test that fails if the rule is broken, named after the regulation section (`s72_attendance_requires_actual_times`, `s40_blanket_items_are_logged`).
- Maintain `docs/decisions.md` (why, not what) and `docs/compliance-map.md` (regulation section → table / function / screen / test).
- Use Ontario's words in the UI: *supervisor* (not director), *RECE*, *program advisor* (not inspector), *licensee*, *age group* (not class), *children's record*, *daily written record*, *serious occurrence*. Canadian spelling (centre, enrolment, colour, licence as the noun). Dates `29 Aug 2026`; 24-hour times for staff, 12-hour for families; currency CAD.
- Never invent a compliance requirement. If unsure, leave `TODO(reg)` and ask.
- Nothing is "done" until it has been exercised end-to-end on a simulator or device and its tests pass.

# 2. Stack (decided — do not relitigate)

**Why native, not a PWA:** parents open this several times a day and rely on the "Now" alert channel; web push on iPhones is not dependable enough, and Toronto parents expect a real App Store listing. Room tablets need the camera, offline storage and long sessions.

**Why Expo, not Capacitor:** native UI and gestures; EAS Build produces iOS and Android binaries in the cloud (no Mac needed); EAS Update ships fixes without store review; Expo push covers APNs and FCM; React and TypeScript skills carry over. Capacitor would wrap a web page in a webview, needs Xcode or paid CI for iOS, and risks App Store rejection as a thin wrapper.

**Why Supabase in Canada, not Mongo:** compliance records are relational (child × room × day × record type); Row Level Security enforces per-centre isolation in the database itself; Auth, Storage, Realtime and Edge Functions come built in; the project lives in **`ca-central-1` (Canada Central)** so data and photos stay in Canada; it removes weeks of auth and file plumbing.

### Layout
- **Monorepo:** pnpm workspaces + Turborepo, TypeScript strict everywhere.
  - `apps/mobile` — Expo (latest SDK), Expo Router. One app, two modes: **Family** (household adults) and **Room** (educators, PIN-locked, on a shared tablet or their own phone). Supervisor essentials (alerts, ratios, approvals) also in-app.
  - `apps/web` — Next.js (App Router) supervisor and licensee console: settings, records, exports, billing, reports. Plain CSS with custom properties (no Tailwind, no CSS-in-JS), sharing the mobile token file.
  - `packages/domain` — pure TypeScript: types, Zod schemas, the **Ontario rule engine** (ratios, reduced-ratio windows, age-group presets, retention clocks, notification routing, daily-record drafting), province and room presets, i18n strings (en-CA now, fr-CA scaffolded). No React, no Supabase imports. Fully unit-tested.
  - `packages/ui-tokens` — colours, type scale, spacing, radii, motion durations for mobile (StyleSheet) and web (CSS vars).
  - `supabase/` — migrations, RLS policies, SQL functions, Edge Functions (regional invocation `ca-central-1`), `pg_cron` schedules, seed scripts, pgTAP tests.
- **Backend:** Supabase Postgres + Auth + Storage + Realtime + Edge Functions in `ca-central-1`. Anything that must not run on a client (daily-record drafting, notification fan-out, exports, retention, billing) lives in Postgres functions or Edge Functions. Clients never hold a service-role key.
- **Auth:** families — email magic link, optional phone OTP; staff — email + password, MFA for supervisor/licensee roles; Room mode — device session bound to a centre, plus a 4–6 digit staff PIN on every write that becomes a record (the PIN is who logged it).
- **Mobile essentials:** `expo-notifications`, `expo-image` (resize before upload), `expo-image-picker` / `expo-camera`, `expo-secure-store`, `expo-sqlite` (offline queue), `react-native-reanimated`, `expo-localization`. Styling: `StyleSheet` + tokens (no NativeWind).
- **Payments (Phase 2):** Stripe Canada — cards and pre-authorised debit (ACSS/PAD). Interac e-Transfer is "record and reconcile" against per-invoice reference codes (no receiving API exists). No parent-side fees, ever.
- **Observability:** Sentry with PII scrubbed (no request bodies, no child names), structured logs, `/health` function.
- **AI (optional, Phase 2):** Anthropic API for translating routine family content and polishing the daily story. Machine-translated content is labelled. **Never** for accident reports, serious occurrences, medication or the daily written record.

# 3. Product principles

1. **Lead with the current decision.** Family home: "Maya is in the Toddler room, napping since 12:40. Pick-up by 6:00." Room home: "12 children, 3 staff, ratio OK — 2 sleep checks due." Supervisor home: today's exceptions only (missing arrivals, ratio at risk, unacknowledged accident reports, expiring credentials).
2. **Calm surfaces.** Neutral canvas, one accent, green = fine, red = act now. No decorative rails, no mood emoji anywhere.
3. **Smart cards.** Each card answers: what changed, what needs attention, what's next, what can I do here.
4. **Legible actions.** `Sign in Maya`, `Record sleep check`, `Send accident report`, `Close today's record`. Confirmation before anything becomes a regulated record.
5. **Every state designed:** loading without layout shift, empty-but-valid, offline, denied, pending acknowledgement, success with the saved result visible.
6. **Purposeful motion;** `prefers-reduced-motion` honoured on both platforms.
7. **One product language.** Product terms, not internal keys. Lucide icons.

# 4. Domain model (create first; names are final)

Tenancy: `centre` (the licensed location) belongs to a `licensee` (legal operator, may have several centres). **Every data table carries `centre_id` and is protected by RLS.**

- `licensee`, `centre` (licence number, licensed capacity per age group, province preset, address, service system manager e.g. Toronto Children's Services, CWELCC enrolment status, hours, holidays)
- `age_group` per centre (preset from Schedule 1 — see §9.0: ratio, max group, qualified proportion, mixed-age approval flag and cap)
- `room` (belongs to an age_group; physical space; devices)
- `person` (any human) + `person_role` rows: `licensee_admin`, `supervisor`, `designate`, `rece`, `staff`, `student`, `volunteer`, `resource_consultant`, `family_adult`
- `household` ↔ `child` via `child_household`; `household_member` (person, relationship, permissions: view, message, pickup, consent, billing); `pickup_authorisation` (person or named non-user, photo, PIN, active dates); `pickup_restriction` (court-order reference, document, restricted person, visibility rules)
- `child` (name, DOB, admission/discharge dates, current room, attends-school flag), `child_record_item` (each s. 72(1) item as a typed row with `status: provided | not_applicable | parent_declined`), `immunisation_status`, `exemption_form`
- `consent` (type, purpose, granted_by, granted_at, expires_at, revoked_at, evidence) — types: care_required, photo_internal, photo_group, photo_third_party, social_media, field_trip (dated), sunscreen_blanket, diaper_cream_blanket, medication (per authorisation), data_sharing_professional
- `individualised_plan` (anaphylaxis | medical_needs | special_needs; versions; consulted parties; evacuation/field-trip section)
- `medication_authorisation` (drug, DIN, dose, schedule or symptoms, label photo, expiry, storage, designate) → `medication_administration` (who, when, dose, outcome; includes blanket items)
- `attendance_event` (child, room, type: arrive | depart | absent | room_transfer, actual_time, recorded_by, device, offline_synced_at, correction_of, reason)
- `staff_shift` (person, room, in/out, `counted_in_ratio` derived from role)
- `care_log` (child, room, type: meal | bottle | nap_start | nap_end | sleep_check | diaper | toilet | outdoor | health_observation | activity | note | photo; payload JSONB validated per type by the domain package; recorded_by)
- `daily_written_record` (scope centre or room, date, draft_text, final_text, closed_by, closed_at, references[]) — one per scope per operating day; never deleted
- `accident_report`, `incident`, `serious_occurrence` (category, awareness_at, ministry_due_at, filed_at, filed_by, ccls_reference, posted_summary, posting_start, posting_end, updates[])
- `health_exclusion` (child, reason, start, return_criteria, cleared_by)
- `menu_week` (posted_at, items, substitutions[]), `feeding_instruction` (infants, parent-signed)
- `credential` (person, type: rece_registration | first_aid_cpr | vsc | offence_declaration | health_assessment | immunisation | training; issued, expires, evidence) — the free wedge
- `compliance_task` (fire_drill | alarm_test | equipment_test | playground_daily | playground_monthly | playground_annual | policy_review | program_statement_review | operations_survey; due, done_at, done_by, evidence)
- `message_thread`, `message` (explicit `audience`; parent-visible recipient list), `announcement`
- `story` (per child per day: generated draft, educator note, published_at, read_at), `notification` (channel: now | later; delivery receipts)
- `invoice`, `payment`, `subsidy_split`, `tax_receipt` (Phase 2)
- `audit_event` (append-only; every regulated write; references only, never photos or free-text health details)
- `retention_clock` (row-level: what, since, purge-after; enforced by a scheduled function that anonymises only after the legal period)

Enforce in the database, not just the app:
- `depart` requires a prior same-day `arrive`; `actual_time` is required; corrections reference the original.
- A `daily_written_record` draft exists for every operating day (created 06:00 local by `pg_cron`); closing requires a human.
- `sleep_check` is valid only for children under 24 months in infant/toddler/family rooms and requires `recorded_by`.
- `pickup_restriction` blocks sign-out to that person at SQL level.
- Turning any bundle off never drops or hides rows in regulated tables.

# 5. Modules (invisible; configured by three setup answers)

Setup asks: **(1) which province?** (Ontario now; Manitoba and Quebec presets scaffolded) **(2) which age groups/rooms?** **(3) do you bill families directly?** Everything else is a bundle with a sensible default.

**Core, always on:** Families & children · Attendance & rooms · Daily care log · Safety records · Family communication · Compliance calendar & credentials.

**Bundles (console toggles, default shown):** Billing & receipts (per answer 3) · Learning documentation (off) · Enrolment & free waitlist (off) · Staff scheduling & time (off) · Kitchen & menus (on) · Translation (off) · Home child care agency mode (off, Phase 3).

**Room presets** change care-log types and prompts: infant (bottles, solids, diapers, back-to-sleep, timed sleep checks), toddler (diapers + toileting plan, sleep checks), preschool (toileting, rest ≤ 2 h), kindergarten/school-age (before/after only, no naps), family (mixed; under-24-month rules apply per child).

**Province preset** changes: age-group table, reduced-ratio windows, retention periods, forms, terminology, language, tax-receipt format, regulator names.

# 6. Notifications — the Now / Later rule

- **Now** (always pushes, sound on, bypasses quiet hours, requires acknowledgement): illness / sent home, accident report, pickup problem, missing expected arrival, emergency or evacuation, medication issue, supervisor message marked urgent.
- **Later** (never interrupts; batched into the daily story and a badge): meals, naps, diapers/toileting, photos, activities, menus, general announcements.
- Families may opt *up* to real-time per category; the default is quiet. Educators see delivery/read receipts on Now items; the supervisor home lists unacknowledged Now items.

# 7. Offline

- Room mode works fully offline for attendance, care logs, sleep checks, medication logs, accident reports and the evacuation screen. Writes queue in SQLite with a device timestamp and sync in order; conflicts keep both versions with the later human edit winning; the sync record is part of the audit trail.
- Family mode caches the last 7 days and the child's record summary.
- The **evacuation screen** (attendance list, emergency contacts, allergies and medication, headcount tally) opens in one tap from any Room screen and never needs the network.

# 8. Phases

### Phase 0 — Foundation (1–2 weeks)
Monorepo, tokens, domain package with the Ontario rule engine and fixtures (a synthetic "Maple Leaf Early Learning" centre: infant, toddler and preschool rooms, 40 children, 9 staff), Supabase project in `ca-central-1` with migrations, RLS, pgTAP tests, Auth roles, seed script, CI (lint, typecheck, unit, pgTAP, Expo prebuild), EAS project with dev/preview/production profiles, Sentry.
*Done when:* a fresh clone seeds the demo centre and both apps sign in as supervisor, educator and parent.

### Phase 1 — Record-keeping core + calm family app (6–8 weeks)
Households and enrolment (invite → parent completes the s. 72(1) record → supervisor verifies; s. 73 respected) · consents · authorised pickups and restrictions · Room mode: sign-in/out with PIN/QR, live ratios with reduced-ratio windows, room transfers, safe-arrival prompts, evacuation screen · care log by room preset incl. timed sleep checks, bottles and feeding instructions, diapers with remaining-count nudges, outdoor time with weather reason, arrival health observation · medication authorisations and administrations incl. blanket items · accident reports with parent acknowledgement · daily written record auto-draft and human close · Family mode: today screen, one daily story at pick-up, Now/Later notifications, photos (full-resolution download, dated, consent-enforced), messaging with visible recipients, siblings in one feed, household members with per-person access · credential ledger (works standalone, free) · supervisor console: exceptions home, records, staff files, attendance and daily-record exports (PDF and CSV by regulation section) · audit and retention clocks.
*Done when:* the demo supervisor can answer a program advisor's requests for attendance, daily written record, accident reports, medication logs, sleep checks and staff credentials in under a minute each, and a demo parent gets exactly one push per day plus a Now alert when the demo child is marked sick.

### Phase 2 — Why they switch (6–8 weeks)
Serious-occurrence helper (24-hour clock, anonymised summary, 10-business-day posting, updates) · immunisation and exemptions · individualised plans and posted allergy lists · health exclusions and public-health line-list export · compliance calendar (drills, tests, playground inspections, reviews, operations-survey figures) · inspection binder export (one PDF bundle by regulation section) · menus (current + next week, substitutions, 30-day retention) · parent handbook builder with acknowledgement and CWELCC status · billing bundle: invoices, Stripe PAD and cards, Interac e-Transfer reference matching, City subsidy splits, CWELCC fee-cap display, late-payment rules, annual CRA tax receipts · learning stories tagged to HDLH foundations (parity only) · graduation export · translation bundle · staff scheduling & time bundle.
*Done when:* a real pilot centre completes one full month including a billing cycle and one mock licensing visit with zero paper.

### Phase 3 — Agencies and provinces (later)
Home child care agency mode (agency → home visitor → provider → family; per-home attendance and records; visitor inspection checklists) · Manitoba preset · Quebec preset (French-first UI; Law 25 workflows: PIA record, deletion and portability requests, Quebec hosting decision) · multi-site licensee view.

# 9. Ontario compliance specification

*Derived from the Child Care and Early Years Act, 2014 (CCEYA), Ontario Regulation 137/15, and the Ministry's Child Care Centre Licensing Manual (2025). Section numbers are O. Reg. 137/15. Treat every line as an acceptance criterion.*

## 9.0 Age groups (Schedule 1) — the room presets

| Age group | Age range | Staff : children | Max group | Qualified staff |
|---|---|---|---|---|
| Infant | under 18 months | 3 : 10 | 10 | 1 in 3 |
| Toddler | 18 – 30 months | 1 : 5 | 15 | 1 in 3 |
| Preschool | 30 months – 6 years | 1 : 8 | 24 | 2 in 3 (17+ children ⇒ at least 2 qualified) |
| Kindergarten | 44 months – 7 years | 1 : 13 | 26 | 1 in 2 |
| Primary/junior school age | 68 months – 13 years | 1 : 15 | 30 | 1 in 2 |
| Junior school age | 9 – 13 years | 1 : 20 | 20 | 1 in 1 |
| Family age group | 0 – 13 years | 1 : 8 | 16 | — (max 6 under 24 months) |

## 9.1 Children's records (s. 72)
Every child's record must contain, and be able to show an inspector at any time: (1) a signed application for enrolment; (2) name, date of birth, home address; (3) parents' names, addresses, phone numbers; (4) an emergency address and phone reachable during care hours; (5) **names of persons to whom the child may be released**; (6) admission date; (7) discharge date; (8) previous communicable diseases, conditions needing medical attention, and — for children not yet in school — immunisation or the official exemption form (medical exemption signed by a doctor or NP; conscience/religious exemption notarised); (9) an ongoing log of symptoms of ill health; (10) signed parent instructions for any medical treatment or medication; (11) signed parent instructions on special diet, rest or physical activity. Plus any individualised plan, any written permission for a child to leave unsupervised at a set time (s. 50), custody orders and pickup restrictions.

Rules: missing information is stored as `not_applicable` or `parent_declined`, never blank. Records are kept "on the premises" — a Canadian-hosted app with offline access satisfies this, and electronic records are allowed (s. 82(2)) **only if** staff and Ministry officials can always get in; never a screen that says "contact your admin to unlock." **Retain 3 years after discharge** (s. 72(5)); financial records 6 years; nothing hard-deletes before then. The **medical officer of health** may inspect and copy items 2, 3, 8 and 9 (s. 72(6)) — provide a per-child export of exactly those. **Parents may not be required to consent to release of information as a condition of enrolment (s. 73)** — enrolment must complete with every optional consent declined. Parents have access to their child's record; the household view is that access.

## 9.2 Attendance (s. 72(3)) and safe arrival & dismissal (s. 50)
Per licensed age group, every day: each child present with actual arrival and departure times, or "absent." Missing record penalty $750, escalating. Times are captured at the event, not typed later; corrections carry who/when/why. Room moves keep one continuous history. Sign-out only when the child actually leaves the centre's care — "on my way" is not a sign-out. **Offline on the room device**: the manual specifically requires that attendance still works off-site during an evacuation or field trip; evacuation mode shows the day's list, emergency contacts, medication and allergy list with no network. **Safe arrival**: if an expected child hasn't arrived by the centre's cut-off, prompt staff to contact the parent and record the attempt and outcome. **Safe dismissal**: release only to persons on the child's authorised list with identity confirmation recorded; late pickup and no-authorised-person flows follow the centre's written policy (which must be in the parent handbook). Custody orders: a restricted person is a hard block, explained to staff, invisible to the restricted person. Public-health export: who was in which room with whom on which dates, with symptom onset where logged.

## 9.3 Ratios and group size (ss. 8–11)
Live per-room count of children present versus staff counted in ratio, against the room's age group. **Reduced ratios** only for programs of 6+ hours during arrival (first 90 min), departure (last 60 min) and rest (up to 2 h); never below two-thirds of the ratio; **never for infants; never outdoors**; floors: toddler 1:8, preschool 1:12, kindergarten 1:20, primary/junior 1:23 (programs under 6 hours: 30-minute windows). **Resource consultants, volunteers and students are never counted.** With 6+ children in attendance, at least 2 staff. Adult supervision at all times (s. 11). Mixed-age approvals are director-issued exceptions modelled as a per-room setting with the 20% / 25% caps. Ratios still apply off-site.

## 9.4 Daily health observation and illness (ss. 32, 36)
Each child is observed on arrival before joining others; symptoms and anything the parent reports at drop-off are recorded in the child's record and the daily written record. Sick child: separated, parent contacted, taken home; if urgent and no parent, seen by a doctor or RN — all recorded. Exclusion and return follow the centre's illness policy (developed with the public health unit): record reason, date, return criteria. Communicable disease exposure: notify the public health unit; keep any orders on file; forward orders to the program advisor within 2 business days. Ministry, public-health and fire inspection reports are kept on the premises.

## 9.5 Accidents, the daily written record, serious occurrences (ss. 36(4), 37, 38)
**Accident report**: child's name, who completed it, date/time, location, what happened, injury and severity, first aid given, and **evidence the parent received a copy** — an in-app acknowledgement with timestamp counts. Any hard hit to the head is recorded as an accident even without symptoms. **Daily written record**: a dated entry **every operating day, no exceptions**, even "uneventful"; must summarise any incident affecting a child's or staff member's health, safety or well-being, every fire drill, every accident ("see child's file"), every serious occurrence, every self-administered medication; may be per centre or per room, and if per room each room completes it daily. **Serious occurrence** (death, serious injury, abuse/neglect allegation, missing child, unplanned disruption, etc.): reported through **CCLS within 24 hours** of the licensee or supervisor becoming aware (if CCLS is down, phone/email the program advisor within 24 hours); late-reporting penalty $2,000, escalating; an **anonymised summary posted for 10 business days** (weekends and statutory holidays excluded), updated if new information arrives; suspected abuse or neglect also triggers the duty to report to a Children's Aid Society. Tucked never files to CCLS itself: it drafts, times, reminds and records what was filed and when. Accidents auto-cross-reference into the daily written record; the record cannot close without human confirmation.

## 9.6 Sleep (s. 33.1)
Children under 12 months are placed on their backs unless a physician's note says otherwise, wherever they sleep. **Direct visual checks** of every sleeping child under 24 months in infant, toddler or family groups — physically going to the child — at the interval set in the centre's sleep policy, **documented per child with timestamps**; electronic monitors never replace them and, if used, are checked daily. Sufficient light in sleep rooms; a way to know immediately who is in the sleep area. Toddler and preschool rest periods **no longer than 2 hours**; children may sleep, rest or do quiet activities according to need. The room device prompts sleep checks at the policy interval; nap start/end logged; printable sleep-check sheet; rest-length warnings.

## 9.7 Anaphylaxis, medical needs, special needs, medication (ss. 39, 39.1, 40, 52)
An **anaphylaxis policy** is required even with no allergic child; each anaphylactic child has an **individualised plan** with emergency procedures, developed with the parent. **Allergy and food-restriction list posted** in every cooking/serving area and every play room (s. 43(3)). **Medical needs**: individualised plan covering exposure reduction, devices and instructions, emergency procedure, supports, evacuation and field-trip procedures; developed with the parent and any regulated health professional; sensitive diagnoses confidential unless the parent consents in writing. **Special needs (s. 52)**: individualised support plan developed with the parent, the child where appropriate, and professionals; parental agreement (preferably written) before implementing or involving outsiders. **Medication (s. 40)**, where the licensee chooses to administer it: written procedure; one designated person (or designate); parent's written authorisation with a **schedule or specific symptoms** and **dose** ("as needed" alone is insufficient); original container labelled with child's name, drug, dosage, purchase and expiry dates, storage and administration instructions; locked and inaccessible to children (except self-carried asthma or epinephrine with written permission); **every administration logged — including blanket-authorised items** (sunscreen, moisturiser, lip balm, insect repellent, hand sanitiser, diaper cream); parent instructions must match the label or a doctor's note resolves the difference; expired medication flagged; accidental administration recorded and escalated; breach penalty $2,000, escalating. **Immunisation (s. 35)**: children not in school are immunised per the local medical officer of health or hold one of the two standard exemption forms; school-age children are noted as attending school.

## 9.8 Nutrition (ss. 42–44)
Menus for the **current and following week** posted where parents can see them; **substitutions noted at the time**; posted menus **kept 30 days**. Meals provided for children under 44 months at each meal time; **at least two snacks** when in care 6+ hours. Infants under 1 fed **per the parent's written instructions**; special dietary arrangements per written instructions (s. 44). Food from home labelled with the child's name. Menu module: posting date, substitution log, 30-day retention; infant feeding instructions on the child's record and visible in the infant room; quantity-eaten logs feed the daily story.

## 9.9 Program and parent handbook (ss. 45–52)
A **program statement** referencing *How Does Learning Happen?* (HDLH) with goals and approaches, reviewed annually, implemented by staff, listing prohibited practices, with a parent issues-and-concerns policy and response timelines. **Outdoor play** at least **2 hours a day** (weather permitting) for 6+ hour programs; **30 minutes** for before/after-school; a child kept indoors needs a physician's or parent's written instruction on file. Infants and toddlers separated from older children during active play. **Parent handbook (s. 45)** must include: services and age groups; hours and holidays; **base fee and non-base fees**; **whether the licensee is enrolled in CWELCC**; admission and discharge policy; off-premises activities; volunteer/student supervision policy; payment methods and schedule; refund circumstances; safe arrival and dismissal policy; waiting-list policy; anaphylaxis policy; issues-and-concerns policy; program statement. **Waiting lists (s. 75.1)**: no fee or deposit; the policy explains admission order and how a family learns its position without seeing others. Tucked provides a handbook builder assembled from settings, versioned, with parent acknowledgement; an outdoor-time log with weather reason; HDLH-tagged learning stories (parity); a free waitlist with self-serve position.

## 9.10 Staff files (ss. 53–64)
For every employee (and volunteers and placement students where noted): **RECE status** on the College's public register (supervisor, and the qualified staff per age group); **standard first aid incl. infant/child CPR** (WSIB-approved) for the supervisor and every staff member who may be counted in ratio, with valid dates; **health assessment and immunisation** records or the objection form for staff, volunteers and students; **vulnerable sector check** obtained before starting (or documented as required "as soon as possible"), conducted by a police service, no more than 6 months old when obtained, **renewed on or before the 5th anniversary**, refreshed after a 6+ month break; **offence declaration** every year a VSC isn't obtained; 18-year-olds provide a YCJA statement, 19+ a VSC; a police-record-check policy; a staff training and development policy; a volunteer/student supervision policy (never counted in ratio, never alone with children); employer duty to report certain RECE matters to the College. Tucked keeps a per-person credential and expiry ledger with reminders, evidence uploads and an inspection-ready staff-file view — the free wedge product.

## 9.11 Emergency preparedness and premises (Parts 4 and 10)
A working phone accessible at all times; an emergency contact list (incl. poison control where no 911). **Fire procedure approved by the local fire chief**, posted in every room; **fire drills** (monthly once staff are practised), alarm and equipment tests — all with **written records**. **Emergency management policy** (or the Ministry's standard one, or the school's if in a school) covering lockdown, hold-and-secure, evacuation, shelter-in-place; debrief with staff, and children where appropriate, after an emergency. **Emergency records readily accessible for every child**: at least one parent phone number and an alternate contact. **Playground**: safety policy; daily, monthly and annual inspections (annual by a certified inspector where there are fixed structures) against CSA Z614; a repair log with hazards restricted until fixed. Recurring checklist items (temperature, water, hazards, first-aid kit) hosted as compliance tasks with evidence.

## 9.12 CWELCC, fees, subsidy and Toronto
For eligible children (under 6, or turning 6 before June 30) in enrolled centres, the **base fee is capped at $22/day** (or lower where the prior fee was lower); non-base fees are restricted; the parent handbook states enrolment status. Disenrolling from CWELCC requires **30 days' written notice to every eligible child's parent and every employee** — Tucked must prove delivery. Funding is cost-based and administered by the service system manager — in Toronto, **Toronto Children's Services** — which also runs fee subsidy and requires attendance and financial reporting under service agreements; exports must match what the City asks for (confirm formats in discovery). **Toronto AQI**: centres with City service agreements are assessed 1–5 (minimum 3) on programming, environment, interactions, health and safety, results public. **Toronto Public Health** inspects, manages outbreaks and assesses immunisation records. **Annual Child Care Operations Survey** in CCLS (as of Dec 31): hours, enrolment, fees, agreements — Tucked produces these numbers. **Tax receipts**: annual receipts for the CRA showing payer, child, amount, period and the provider's identity (business name and number; an individual provider's SIN) — one-tap generation every February.

## 9.13 Privacy and data
**PIPEDA** governs a private Ontario centre: meaningful consent, minimum collection, purpose limitation, safeguards, access and correction rights, breach reporting where there's a real risk of significant harm. Ontario has no private-sector privacy statute; municipal centres fall under MFIPPA (out of scope for Phase 1). The Licensing Manual tells licensees to keep a privacy policy covering minimum collection, parental access, **informed consent before sharing children's information or photos with third parties or on social media**, secure storage, and dated time-limited consents for trips and events. **Data residency**: not legally required for private centres, but Tucked hosts all data and photos in Canada as a matter of policy. Photos are personal information: consent per child and per purpose; a child without group-photo consent is excluded or obscured automatically; no advertising SDKs, no third-party analytics touching content, no facial recognition, no live streaming. **Quebec later**: Law 25 adds GDPR-style rights, a privacy impact assessment before data leaves Quebec, a private right of action and French-first obligations — the province preset must be able to turn these on.

## 9.14 Tucked must never
Let a required record be deleted, hidden or locked by a bundle toggle, a lapsed subscription or a lost admin password · treat a photo or update as delivered without evidence where the regulation requires evidence (accident reports, CWELCC notices) · count a volunteer, student, resource consultant or off-shift supervisor in a ratio · sign a child out on a parent's "on my way" · block enrolment on an optional consent · substitute a monitor, camera or AI summary for a direct visual sleep check or a human-confirmed daily written record · file anything to CCLS, the City, the College or the CRA without a named human pressing the button.

# 10. Competitive decisions (so you don't build the wrong thing)

The incumbents — Brightwheel (parent feed, billing), Procare (deep billing, subsidy, ratio alerts), Lillio (Toronto-born; learning stories, curriculum, offline check-in), Playground (billing, payroll, scheduling), myKidzDay (small-centre all-in-one), Storypark (learning documentation, endorsed by the Canadian Child Care Federation), Mitten.care (small BC white-label app) — all share the same three modules: feed, check-in, billing. Parity there is table stakes.

**Build (nobody has it):** quiet-by-default Now/Later notifications · one daily story · full-resolution dated photo archive with graduation export · consent-enforced group photos · household model with per-person access and custody-aware pickup · safe-arrival prompts · Ontario reduced-ratio logic · evacuation/offline mode · auto-drafted daily written record · serious-occurrence clock · sleep-check prompts · diapers-remaining nudge · outdoor-time weather log · credential expiry ledger (free) · inspection binder by regulation section · public-health line list · Interac e-Transfer reconciliation and fee-free PAD · CWELCC cap display · CRA tax receipts · Canadian hosting · published CAD pricing.

**Parity only:** daily sheets, messaging, check-in/out kiosk, basic invoicing, immunisation tracking, HDLH-tagged learning stories, menus, staff scheduling.

**Do not build:** payroll · curriculum kits or lesson-plan marketplaces · CRM and lead nurture · marketing websites · live classroom cameras · US subsidy (CCDF/CACFP) logic · mood emoji.

# 11. Security and privacy requirements

All data and files in `ca-central-1`; private buckets; short-lived signed URLs; photos re-authorised on every read; EXIF stripped except capture time. RLS on every table, tested with pgTAP for every role including "wrong centre," "removed household member" and "restricted pickup person." Minimum collection; every optional field labelled optional. Consent explicit, per purpose, dated, revocable, evidenced; enrolment completes with all optional consents declined. No third-party analytics or ad SDKs in the mobile app; crash reporting scrubbed. Retention: 3 years post-discharge for children's records and attendance, 6 years financial; nothing purged earlier; purge is anonymisation with an audit trail. Secrets never in the repo or in `EXPO_PUBLIC_*`; service role only in Edge Functions. PIPEDA access and deletion requests handled through a supervisor workflow with a 30-day SLA tracker.

# 12. Quality gates (every phase)

Typecheck, lint; unit tests for the domain package (≥ 90% of rule-engine branches); pgTAP RLS and rule tests; EAS preview builds succeed for iOS and Android; accessibility (contrast, touch targets ≥ 44 pt, screen-reader labels on all controls); offline script (airplane mode: sign in 5 children, 3 sleep checks, 1 accident report; reconnect; verify order and audit); performance (Family home < 1.5 s on a 2019 mid-range Android over 4G; Room sign-in in ≤ 3 taps).

# 13. Deliverables at the end of each phase

1. `docs/compliance-map.md` updated.
2. A five-minute click-through script for a supervisor demo.
3. Release notes in plain English for a supervisor, not a developer.
4. A list of everything you were unsure about, with your best guess and the regulation section.

Start with Phase 0. Before writing code, produce `docs/plans/phase-0.md` and ask me your questions.

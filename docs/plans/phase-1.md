# Phase 1 — Record-keeping core + calm family app

*Per [tucked-build-prompt.md](../../references/tucked-build-prompt.md) §8 (target 6–8 weeks). Status: **substantially built and verified locally** (see [compliance-map.md](../compliance-map.md) for per-section state, [demo-script.md](../demo-script.md) for the click-through, [release-notes-phase-1.md](../release-notes-phase-1.md) for the plain-English summary).*

**Remaining before the phase closes:** real push on a device (needs the founder's `npx eas login`, then `eas init` + a dev build; the notify Edge Function and token registration are written), the airplane-mode quality-gate script run on that device, an accessibility sweep (screen-reader labels are in place; contrast is enforced by tokens), photo capture/story publishing from the room device, and the enrolment invite email path (invites exist; email sending joins the notify plumbing).

## Uncertainties (build prompt §13.4 — best guesses, flagged in code as TODO(reg))

1. **Reduced ratios for junior/family groups** — the engine allows reduction only where the Manual lists a floor (toddler/preschool/kindergarten/primary-junior); junior and family groups are conservatively never reduced. `packages/domain/src/ratios.ts`.
2. **Family-group qualified proportion** — Schedule 1 lists none; the engine requires zero qualified staff for family groups pending Manual confirmation. `ageGroups.ts`.
3. **Financial retention clock start** — 6 years from the record date (conservative) rather than fiscal-year end. `retention.ts` (O. Reg. 138/15 s. 27.1).
4. **Daily written record after close** — late-arriving cross-references are written into the *next* operating day's record with a `late_for` marker; the Manual's expectation for post-close additions should be confirmed with a program advisor. Migration 0007.
5. **PIN as signature** — a 4–6 digit PIN verified server-side is treated as the "who logged it" signature for regulated writes; confirm a program advisor accepts this as the electronic-records control (s. 82(2)).
6. **s. 72(6) content boundary** — the medical-officer copy renders items 2, 3, 8, 9 as stored; whether the symptoms log must include full care-log history or recent entries only is interpreted as "the ongoing log" (all of it is available; the print shows the recent 30).

**Done when** (verbatim from the spec): the demo supervisor can answer a program advisor's requests for **attendance, daily written record, accident reports, medication logs, sleep checks and staff credentials in under a minute each**, and a demo parent gets **exactly one push per day** plus a **Now alert** when the demo child is marked sick.

---

## 1. Scope and non-goals

Phase 1 turns the Phase 0 skeleton into a working centre: Room mode does the day's work offline-first, every regulated record fills itself in as a side effect, and the family app stays calm. Everything maps to a compliance-map row; each slice ends with the relevant rows flipping to ✅.

**Non-goals (Phase 2+):** serious-occurrence helper, immunisation/exemptions, full individualised plans, menus, billing, handbook builder, learning stories, translation, staff scheduling, agencies. **One deliberate pull-forward:** the child's allergies/medical conditions (s. 72(1) item 8) land in Phase 1 because the **evacuation screen requires allergies and medication offline** — full anaphylaxis *plans* stay Phase 2.

## 2. Migrations (0005–0012)

All tables carry `centre_id` + RLS; regulated tables get the `app.audit_row` trigger and no client `delete`. Names from build prompt §4 are final.

| Migration | Tables / objects |
|---|---|
| `0005_attendance` | `attendance_event` (child, room, type `arrive/depart/absent/room_transfer`, `actual_time` not null, `recorded_by_person_id` + `recorded_by_pin_ok`, device, `offline_recorded_at`, `offline_synced_at`, `correction_of`, reason). Constraints in SQL: depart requires same-day arrive (trigger); corrections reference the original; **sign-out to a restricted person blocked at SQL level** (trigger against `pickup_restriction`). `staff_shift` (person, room, in/out, `counted_in_ratio` **derived from role by trigger** — volunteers/students/RCs can never be flagged in). |
| `0006_care_log` | `care_log` (child, room, type from the room-preset enum, `payload` jsonb **validated per type by a SQL check calling a validation function generated from the Zod schemas**, recorded_by, offline columns as above). Sleep-check rows valid only for under-24-month children in infant/toddler/family rooms (trigger using `date_of_birth`). |
| `0007_daily_record` | `daily_written_record` (scope centre/room, date, draft_text, final_text, closed_by, closed_at, `references` jsonb). One per scope per operating day (unique index); **draft created 06:00 centre-local by `pg_cron`**; close requires a human (`closed_by` not null enforced on update); never deleted. Cross-reference triggers: accident/med/fire-drill rows append to `references`. |
| `0008_safety` | `accident_report` (child, completed_by, occurred_at, location, description, injury, severity, first_aid, parent_ack_person_id, parent_ack_at — **the s. 36(4) delivery evidence**), `health_observation` fields fold into care_log; `pickup_authorisation` (person or named non-user, photo, PIN, active dates), `pickup_restriction` (restricted person, court-order ref, document, staff-visible note; **invisible to the restricted person via RLS**). |
| `0009_medication` | `medication_authorisation` (drug, DIN, dose, **schedule or symptoms — "as needed" alone rejected by check**, label photo, expiry, storage, designated person, parent signature evidence, incl. blanket types sunscreen/diaper-cream/etc.), `medication_administration` (who, when, dose, outcome; **blanket items logged too** — s. 40). |
| `0010_enrolment_consent` | `child_record_item` (each s. 72(1) item as typed row, `status: provided / not_applicable / parent_declined` — **never blank**), `consent` (type, purpose, granted_by, granted_at, expires_at, revoked_at, evidence; **enrolment completes with every optional consent declined** — s. 73 enforced by having no NOT NULL dependency), `enrolment_invite` (token, household, expiry). |
| `0011_family_surface` | `story` (per child per day: generated draft, educator note, published_at, read_at), `notification` (channel now/later, event type, recipient, delivery receipts, acknowledged_at — **unacknowledged Now items feed the supervisor exceptions view**), `device_push_token`, `message_thread` + `message` (explicit `audience`; **parent-visible recipient list**), `photo` (storage path, captured_at, uploaded_by, consent-gated visibility). |
| `0012_credentials_retention` | `credential` (person, type: rece_registration / first_aid_cpr / vsc / offence_declaration / health_assessment / training; issued, expires, evidence upload) — the free wedge. `retention_clock` (what, since, purge-after) + the scheduled anonymisation function (**anonymise only after the legal period**, audit-trailed). Storage buckets: `photos`, `evidence` (private; signed URLs; EXIF stripped except capture time on upload). |

## 3. Domain package additions

- `careLog` payload Zod schemas per type (meal, bottle, nap, sleep_check, diaper incl. remaining-count, toilet, outdoor + weather reason, health_observation, activity, note, photo) — shared by clients and the SQL validation function.
- `dailyRecord.draft(logs, incidents) → text` — the auto-drafter (pure, template-based, **no AI**), unit-tested against fixture days including "uneventful".
- `story.build(childDay) → story` — the calm daily story assembler (meals eaten, naps, photos, "what was different"), en-CA voice rules applied.
- `safeArrival.due(expected, arrived, cutoff)` — s. 50 prompt logic.
- `sleepChecks.schedule(policyIntervalMin, napStart)` — prompt timing.
- Extended Maple Leaf fixture: one demo day of logs (arrivals, naps with checks, meals, one accident, one blanket-item administration) powering seeds, tests and the demo script.

## 4. Offline (the hard part — built first, once)

Per build prompt §7: a small sync engine in `apps/mobile` used by every Room-mode write:

- `expo-sqlite` queue: every write lands locally with `offline_recorded_at` + staff PIN check result, then posts in order; server acks set `offline_synced_at`. Conflicts keep both rows; later human edit wins; sync metadata is part of the audit trail.
- Read cache: today's roster, attendance state, authorisations, allergy/medical list, emergency contacts — refreshed opportunistically, never required to be fresh for the **evacuation screen** (one tap from any Room screen: attendance list, contacts, allergies + medication, headcount tally; zero network).
- Family mode caches last 7 days + child record summary (read-only).
- The **airplane-mode script** from the quality gates (sign in 5 children, 3 sleep checks, 1 accident report; reconnect; verify order + audit) becomes an automated Maestro/manual checklist run before the phase closes.

## 5. Notifications (Now/Later made real)

- `notify` Edge Function: regulated events → `packages/domain` routing → rows in `notification` + Expo push (Now: sound, iOS time-sensitive, Android high-importance channel; Later: **no push** — batched into the story + badge). Delivery receipts stored; **accident-report acknowledgement timestamps recorded** as the s. 36(4) evidence.
- Two Android notification channels created on app start; families opt *up* per Later category in settings.
- Story publishes **at the child's sign-out** (their day is complete), fallback at centre close for no-shows — one push per child per day, on the Later channel's single daily exception (the story itself is the one scheduled push).
- Requires real dev builds (Expo Go cannot receive remote push since SDK 53) — see Q2.

## 6. Screens

**Room mode (offline-first):** PIN gate · room board (present list, live ratio badge via `assessRoomRatio`, sleep-checks-due strip) · sign-in/out flow (arrival health observation prompt + "parent reported" note; departure with authorised-pickup confirmation; restricted person hard-block with staff-visible explanation) · safe-arrival prompt queue (s. 50: expected-but-absent → contact parent → record attempt + outcome) · room transfer · care-log quick entry per preset (bulk per-room where sensible; diapers-remaining nudge) · sleep board (nap start/end, timed check prompts, per-child timestamps) · medication flow (authorisation checklist → administer → log; blanket items one-tap) · accident report flow (mandatory head-bump concussion note) · **evacuation screen** · day close (review auto-draft → confirm → `Close today's record`).

**Family mode:** today screen ("Maya is in the Toddler room, napping since 12:40. Pick-up by 6:00.") · the daily story (letter layout, photos inline with dates, full-res download) · Now alert screen with explicit `Acknowledge` action · messaging (recipient picker: teacher / supervisor / both — **shown on every message**) · notification settings (opt-up per category) · household view = the parent's s. 72 record access (children's record summary, consents with revoke, household members) · siblings in one feed (already proven in Phase 0).

**Supervisor console (web):** exceptions home (missing arrivals, ratio at risk, unacknowledged accident reports/Now items, expiring credentials, unclosed daily records) · children's records (s. 72(1) item checklist view; per-child export incl. the s. 72(6) medical-officer subset) · attendance browser + corrections (who/when/why) · daily written records archive · accident/medication registers · staff files + **credential ledger with expiry reminders** (the free wedge — usable standalone) · enrolment (invite → parent completes → supervisor verifies; s. 73 optional consents clearly separated) · exports: **PDF + CSV by regulation section** (attendance per age group per day, daily written record, accident reports with ack evidence, medication log, sleep checks, staff credentials).

## 7. Edge Functions & jobs

`notify` (fan-out) · `export` (per-section PDF via pdf-lib + CSV, signed URL result) · `story-publish` (assemble + push at sign-out / close) · `pg_cron`: 06:00 daily-record drafts, credential-expiry scan, retention-clock scan, safe-arrival cutoff sweep.

## 8. Tests

- **pgTAP:** every new table's RLS (family sees own children's logs only; restricted person sees nothing incl. the restriction row; educator scoped to own centre), `s72_attendance_requires_actual_times`, `s72_depart_requires_arrive`, `s50_restricted_pickup_blocked_at_sql`, `s33_1_sleep_check_only_under_24m`, `s40_blanket_items_are_logged`, `s40_as_needed_alone_rejected`, `s37_close_requires_human`, `s37_one_record_per_scope_per_day`, `s36_4_ack_evidence_recorded`, `s73_enrolment_completes_with_consents_declined`, `never_regulated_rows_deleted`.
- **Domain:** drafter, story builder, payload schemas, safe-arrival, sleep-check scheduling (≥ 90% branches held).
- **Offline:** the airplane-mode script; ordering + audit assertions on reconnect.
- **Notification routing:** integration test that a "sick" event pushes Now and a photo does not.

## 9. Build order

Offline sync engine → attendance + ratios + evacuation (slice A) → care logs + sleep (B) → daily written record + accident reports (C) → medication (D) → family surface + notifications + story (E) → enrolment/consents/pickups (F) → console + credential ledger + exports (G) → quality gates + five-minute demo script. Each slice: migration → pgTAP → domain logic → screens → seed-day extension → commit.

## 10. Risks

Push requires EAS dev builds (Q2 gates the Phase 1 done-when). PDF layout time-sinks — keep exports tabular and boring. Offline conflict edge cases — the queue is built once, early, and everything reuses it. JSONB payload validation drift between Zod and SQL — generated from one source. Scope: Phase 1 is the longest phase; slices keep it demoable throughout.

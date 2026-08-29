# Compliance map

*Regulation section → where it lives in the product. Every row must eventually name its table(s), function(s), screen(s) and at least one test that fails if the rule is broken (tests are named for their section, e.g. `s72_attendance_requires_actual_times`). Sections are O. Reg. 137/15 unless noted. Source requirements: [tucked-ontario-requirements.md](../references/tucked-ontario-requirements.md); acceptance criteria: [build prompt §9](../references/tucked-build-prompt.md).*

Status: ⬜ planned · 🔶 in progress · ✅ built & tested. Phase = when it lands per the build plan.

| Section | Requirement (short) | Tables / functions | Screens | Tests | Phase | Status |
|---|---|---|---|---|---|---|
| Sched. 1 | Age-group presets: ratios, max group, qualified staff | `age_group`; `domain/ageGroups` | Room setup | `sched1_*` | 0 | ✅ |
| ss. 8–11 | Live ratios; reduced-ratio windows & floors; never count volunteers/students/RCs; 6+ children ⇒ 2 staff | `staff_shift`, `attendance_event`; `domain/ratios` | Room home, supervisor home | `s8_*`, `s11_*` | 0 (engine) / 1 (live) | ✅ engine + live room board |
| s. 32 | Daily health observation on arrival, incl. parent-reported symptoms | `care_log(health_observation)` | Sign-in flow | `s32_*` | 1 | ✅ observed-on-arrival prompt inside the sign-in flow, parent-reported notes, DB-validated |
| s. 33.1 | Back-to-sleep under 12 mo; direct visual sleep checks < 24 mo, per-child timestamped; rest ≤ 2 h | `care_log(sleep_check, nap_*)` | Room sleep board | `s33_1_*` | 1 | ✅ DB gating, room nap board with due prompts, console register |
| s. 35 | Immunisation or official exemption forms | `immunisation_status`, `exemption_form` | Children's record | `s35_*` | 2 | ⬜ |
| s. 36 | Sick child: separate, contact parent, record; exclusion & return | `health_exclusion` | Room + supervisor | `s36_*` | 2 | ⬜ |
| s. 36(4) | Accident report with evidence parent received a copy | `accident_report` + acknowledgement | Report flow, family ack | `s36_4_*` | 1 | ✅ full loop: on-device report form, auto Now alert (DB trigger), parent ack in-app = delivery evidence, console register |
| s. 37 | Daily written record: dated entry every operating day, auto-cross-referenced, human-closed | `daily_written_record`; 06:00 `pg_cron` draft | Close-the-day flow | `s37_*` | 1 | 🔶 cron drafts, human close, cross-refs, console ✅ |
| s. 38 | Serious occurrence: 24 h CCLS clock, anonymised 10-business-day posting, updates; human files | `serious_occurrence` | Guided flow | `s38_*` | 2 | ⬜ |
| ss. 39, 39.1, 52 | Anaphylaxis / medical needs / special needs individualised plans; posted allergy list (s. 43(3)) | `individualised_plan` | Plans, room postings | `s39_*`, `s52_*` | 1–2 | ⬜ |
| s. 40 | Medication: authorisation with dose + schedule/symptoms; label checklist; designated staff; **blanket items logged** | `medication_authorisation`, `medication_administration` | Med flows | `s40_*` | 1 | 🔶 DB rules + registers ✅; room med flow pending |
| ss. 42–44 | Menus posted (current + next week), substitutions at the time, kept 30 days; infant feeding per written instructions | `menu_week`, `feeding_instruction` | Kitchen bundle | `s42_*`–`s44_*` | 2 | ⬜ |
| ss. 45–52 | Parent handbook contents; program statement (HDLH); outdoor play 2 h; waitlist policy | handbook builder, `compliance_task` | Console | `s45_*`+ | 2 | ⬜ |
| s. 50 | Safe arrival & dismissal: expected-but-absent prompt; release only to authorised persons; restrictions hard-block | `pickup_authorisation`, `pickup_restriction` (SQL-level block) | Sign-in/out | `s50_*` | 1 | ✅ SQL hard block, identity-confirmed release flow, safe-arrival chase prompts with recorded outcomes |
| ss. 53–64 | Staff files: RECE, first aid/CPR, VSC 5-year renewal, offence declarations, health assessments | `credential` ledger | Staff files (free wedge) | `s53_*`+ | 1 | 🔶 credential ledger + expiry states live in console |
| s. 72(1) | Children's record: all 11 items; missing = `not_applicable`/`parent_declined`, never blank | `child`, `child_record_item` | Enrolment | `s72_*` | 1 | 🔶 11 typed items, parent completion, verification ✅ |
| s. 72(3) | Attendance per age group: actual times or "absent"; offline; corrections carry who/when/why; continuous across room moves | `attendance_event` | Room sign-in/out, evacuation screen | `s72_attendance_*` | 1 | 🔶 DB + console + room sign-in/out + offline queue + evacuation ✅; corrections UI pending |
| s. 72(5) | Retention: 3 y post-discharge; financial 6 y (O. Reg. 138/15 s. 27.1); purge = anonymise-after | `retention_clock`; scheduled fn | — | `s72_5_*` | 0 (clocks) / 1 | 🔶 clocks ✅ in domain, scheduled fn P1 |
| s. 72(6) | Medical officer of health export: items 2, 3, 8, 9 exactly | export fn | Console exports | `s72_6_*` | 1 | ⬜ |
| s. 73 | Enrolment never blocked on an optional consent | `consent` model | Enrolment | `s73_*` | 1 | ✅ DB-enforced, pgTAP-proven |
| s. 75.1 | Waitlist: no fees; self-serve position without exposing others | waitlist (bundle, off) | — | `s75_1_*` | 2 | ⬜ |
| s. 82(2) | Electronic records: staff & Ministry can always get in; offline on premises | offline queue; break-glass access | Room mode | `s82_2_*` | 1 | 🔶 offline queue + zero-network evacuation cache ✅; break-glass access pending |
| Parts 4, 10 | Fire drills, alarm tests, playground inspections, emergency policy — with written records | `compliance_task` | Compliance calendar | `part4_*`, `part10_*` | 2 | ⬜ |
| CWELCC / municipal | $22/day cap display; 30-day disenrolment notices with delivery proof; Toronto reporting; CRA receipts | billing bundle | Console | `cwelcc_*` | 2 | ⬜ |
| PIPEDA | Minimum collection; consent per purpose; access/deletion workflow, 30-day SLA; Canadian hosting | `consent`, RLS, `ca-central-1` | Console | `pipeda_*` | 0–1 | 🔶 RLS on every table + pgTAP isolation written (run in CI); consent model P1 |
| §9.14 never-dos | No delete/hide of required records by toggle, lapse, or lost password; no ratio counting of volunteers; no "on my way" sign-out; nothing auto-filed | DB constraints + RLS | — | `never_*` | every phase | ⬜ |

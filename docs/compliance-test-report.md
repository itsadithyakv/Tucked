# Compliance test report — O. Reg. 137/15 full sweep

*Audit date: 2026-08-30. Scope: every section of [tucked-ontario-requirements.md](../references/tucked-ontario-requirements.md) checked against the schema, the RPCs, the screens, and the automated proof. Test evidence: **127 pgTAP tests across 9 suites** (`supabase/tests/`), 79 domain tests (`packages/domain/test/`), all green on this date. Verdicts: ✅ built and machine-proven · 🔶 built, partially proven or partially built · ⬜ not built (phased per the build plan) — an honest ⬜ beats a decorative ✅.*

Run the proof yourself:

```bash
pnpm exec supabase test db
```

## The verdict table

| Rule | What the regulation demands | Where it lives | Machine proof | Verdict |
|---|---|---|---|---|
| Sched. 1 | Age-group ratios, max group, qualified staff | `age_group` + `domain/ageGroups` | `sched1_*` (domain, 10) | ✅ |
| ss. 8–10 ratios | Live counts; reduced-ratio windows and floors; volunteers/students/RCs never counted; 6+ children ⇒ 2 staff | `staff_shift` via `record_staff_shift`; `domain/ratios` | `s8_no_direct_shift_inserts`, `s8_volunteer_never_counted_in_ratio`, `s8_rece_counted_in_ratio`, `s8_volunteer_cannot_record_attendance` + 21 domain ratio tests | ✅ |
| s. 11 supervision | Adult supervision; face-to-name headcounts at moments that matter | `headcount_check` + `record_headcount` | `s11_transition_headcount_records_with_valid_pin`, `s11_missing_snapshot_names_the_child`, `s11_volunteer_cannot_record_headcounts`, `s11_parents_never_see_headcounts` | ✅ |
| s. 32 health obs | Observed on arrival before joining others; parent-reported symptoms recorded | sign-in flow prompt → `care_log(health_observation)` | `s32_health_observation_with_parent_report` | ✅ |
| s. 33.1 sleep | Back-to-sleep; direct visual checks < 24 mo in infant/toddler/family rooms only; rest ≤ 2 h | DB-gated `care_log(sleep_check)`; nap board | `s33_1_sleep_check_under_24m_in_toddler_room_ok`, `s33_1_sleep_check_rejected_at_24_months_plus`, `s33_1_sleep_check_rejected_in_preschool_room` | ✅ |
| s. 35 immunisation | Immunisation or official exemption forms | `child_record_item` holds the answer; dedicated exemption-form registry | s. 72(1) item tests cover the record slot | 🔶 registry P2 |
| s. 36 sick child | Separate, contact parent, record; exclusion and return | illness view on room device | — | 🔶 recording exists, exclusion workflow P2 |
| s. 36(4) accident | Report with **evidence the parent received a copy** | `accident_report` + ack RPC; DB trigger creates the Now alert | `s36_4_accident_report_recorded`, `s36_4_head_injury_requires_concussion_note`, `s36_4_parent_acknowledges_copy`, `s36_4_acknowledgement_names_the_parent_with_timestamp`, `s36_4_stranger_cannot_acknowledge`, `s36_4_acknowledged_report_never_changes` | ✅ |
| s. 37 DWR | Dated entry every operating day; incidents/drills/accidents cross-referenced; human close | `daily_written_record`, 06:00 pg_cron draft | `s37_draft_created_for_operating_day`, `s37_accident_cross_referenced_into_daily_record`, `s37_drill_cross_referenced_into_dwr`, `s37_human_close_with_entry`, `s37_close_names_the_human`, `s37_closed_record_never_changes`, `s37_empty_entry_rejected` | ✅ |
| s. 38 serious occurrence | CCLS within 24 h; anonymised 10-business-day posting; human files | — | — | ⬜ P2 |
| ss. 39, 39.1, 52 plans | Anaphylaxis / medical / special-needs individualised plans; posted allergy list | — | — | ⬜ P1–2 |
| s. 40 medication | Dose + schedule/symptoms required ("as needed" alone invalid); blanket items logged; revocation; expiry | `medication_authorisation`, `medication_administration` | `s40_as_needed_alone_is_insufficient`, `s40_dose_plus_schedule_authorised`, `s40_blanket_items_are_logged`, `s40_no_administration_after_revocation`, `s40_expired_medication_never_administered`, `s40_administrations_never_edited` + 5 more | ✅ |
| ss. 42–44 nutrition | Menus posted and kept 30 days; infant feeding per written instructions | — | — | ⬜ P2 |
| ss. 45–49 program | Handbook, program statement, outdoor 2 h | outdoor skip records weather reason | `s46_outdoor_skip_records_weather_reason` | 🔶 handbook builder P2 |
| s. 50 safe arrival/dismissal | Expected-but-absent chase; release only to authorised persons; restrictions hard-block | `pickup_restriction` SQL block inside `record_attendance` | `s50_restricted_pickup_blocked_at_sql`, `s50_release_to_authorised_parent_ok` | ✅ |
| ss. 53–64 staff files | RECE, first aid/CPR, VSC 5-year renewal, declarations; volunteers never alone / never in ratio | `credential` ledger; RLS denies volunteers standing access | `s60_supervisor_records_vsc`, `s60_vsc_five_year_renewal_flagged`, `s53_volunteer_sees_no_children` | 🔶 ledger ✅, evidence uploads P2 |
| s. 72(1) children's record | All 11 items; missing = never blank | `child_record_item` typed items | `s72_1_enrolment_incomplete_until_items_answered`, `s72_1_never_blank`, `s72_1_no_item_left_blank`, `s72_1_supervisor_verifies_every_item` | ✅ |
| s. 72(3) attendance | Actual times or "absent"; corrections carry who/when/why; continuous across rooms; offline | `attendance_event` append-only + corrections | `s72_arrive_records_with_valid_pin`, `s72_depart_requires_same_day_arrive`, `s72_actual_time_always_present`, `s72_no_updates_only_corrections`, `s72_correction_must_reference_same_child` | ✅ |
| s. 72(5) retention | 3 y post-discharge; financial 6 y (O. Reg. 138/15 s. 27.1) | domain retention clocks; every regulated table append-only; `billing_event` append-only | `never_*_deleted` in every suite; `oreg138_billing_ledger_never_deleted`; 4 domain retention tests | 🔶 clocks ✅, scheduled anonymise-after fn pending |
| s. 72(6) MOH export | Items 2, 3, 8, 9 exactly | child-record print view | manual print check | 🔶 |
| s. 73 consent | Enrolment never blocked on an optional consent | `consent` model | `s73_enrolment_completes_with_every_optional_consent_declined`, `s73_care_consent_still_required`, `s73_consent_reversible_later`, `s73_superseded_consent_rows_are_kept` | ✅ |
| s. 75.1 waitlist | No fees; position without exposing others | — | — | ⬜ P2 |
| s. 82(2) electronic records | Staff and Ministry can always get in; offline on premises | offline queue; zero-network evacuation cache | field-verified on device; airplane-mode script pending | 🔶 |
| Part 4 drills | Fire drills with written records | drill headcounts auto-entered in DWR | `part4_drill_recorded_centre_wide`, `s37_drill_cross_referenced_into_dwr` | 🔶 record ✅, compliance calendar P2 |
| PIPEDA | Minimum collection; access scoped to need; Canadian hosting | RLS everywhere; **platform admins see tenancy and money, never children** | `rls_enabled_on_every_public_table`, `pipeda_platform_admin_sees_no_children`, `pipeda_platform_admin_sees_no_attendance`, `pipeda_platform_admin_sees_no_households`, `s72_parent_sees_own_children_only`, `s53_volunteer_sees_no_children` | ✅ for what's built |

## The never-do list (§9.14), proven

| Never | Proof |
|---|---|
| A required record deleted, hidden, or locked by a lapsed subscription or module toggle | `never_cancelled_billing_hides_records` and `never_cancelled_billing_blocks_writes` — the platform suite cancels a centre's subscription and then proves the supervisor still reads children and still records attendance. **No RLS policy anywhere reads `centre_subscription`.** Plus per-table `never_*_deleted` tests. |
| Delivery claimed without evidence | `s36_4_acknowledgement_names_the_parent_with_timestamp` |
| Volunteer/student/RC counted in ratio | `s8_volunteer_never_counted_in_ratio` (DB) + domain ratio tests |
| "On my way" sign-out | No API accepts it: `record_attendance` records only arrive/depart/absent at actual times (`s72_actual_time_always_present`) |
| Enrolment blocked on optional consent | `s73_enrolment_completes_with_every_optional_consent_declined` |
| Monitor/AI substitutes for direct checks or the human close | Sleep checks are per-child rows recorded by a PIN-signed human; `s37_close_names_the_human` |
| Auto-filing to CCLS/City/College/CRA | Nothing files anywhere; the DWR close and every regulated write names a human |

## Jurisdictions beyond Ontario

The `jurisdiction` table (0019) declares which regulator's rule pack a centre runs under. **CA-ON is the only implemented pack**; CA-MB and CA-QC are seeded as `planned`/inactive and `admin_create_centre` refuses to create a centre in a jurisdiction until its pack is `implemented` — proven by `planned_jurisdictions_reject_centres_until_implemented`. Adding a province or US state means: a requirements document like the Ontario one, a preset in `packages/domain/src/presets.ts`, jurisdiction-gated DB rules where they differ (sleep-check ages, ratios), and flipping the row to `implemented`/active. Nothing about tenancy, billing, or the app shell changes.

## Gaps that matter next (in order)

1. **s. 38 serious occurrence** — highest-penalty unbuilt item ($2,000 late-filing).
2. **s. 39/43(3) anaphylaxis plans + posted allergy list** — safety-critical, currently paper.
3. **Retention scheduler** — clocks exist in domain; the anonymise-after job isn't scheduled yet.
4. **s. 82(2) break-glass access** — Ministry access path when a supervisor is unavailable.
5. **Menus (ss. 42–44), handbook (s. 45), waitlist (s. 75.1), compliance calendar (Parts 4/10)** — Phase 2 per plan.

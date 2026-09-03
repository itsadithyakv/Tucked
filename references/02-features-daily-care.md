# 02 — Features: the child's day

*Everything that happens between arrival and pickup, and everything the day is required to leave behind. Each section gives the regulation, what Tucked does, **every case including the refusals**, where it lives in the schema, and where it is weak.*

The refusal tables are the important part. Almost every rule in Tucked is a `raise exception` in a trigger or an RPC, and the message an educator sees is the specification. They are quoted verbatim.

**Companion:** [03](03-features-records-and-obligations.md) covers what must be *on file*. [04](04-data-security-and-platform.md) covers how the write model, RLS and audit actually work.

---

## Contents

1. [Attendance — the three-layer model](#1-attendance--the-three-layer-model)
2. [Safe arrival and dismissal (s. 50)](#2-safe-arrival-and-dismissal-s-50)
3. [Ratios and supervision (ss. 8–11, Schedule 1)](#3-ratios-and-supervision-ss-811-schedule-1)
4. [Headcounts and evacuation (s. 11, Part 4)](#4-headcounts-and-evacuation-s-11-part-4)
5. [The care log (s. 32 and the daily sheet)](#5-the-care-log-s-32-and-the-daily-sheet)
6. [Sleep (s. 33.1)](#6-sleep-s-331)
7. [Outdoor play (s. 47)](#7-outdoor-play-s-47)
8. [Menus, substitutions and feeding (ss. 42–44)](#8-menus-substitutions-and-feeding-ss-4244)
9. [Illness, exclusion and public health (s. 36)](#9-illness-exclusion-and-public-health-s-36)
10. [Medication (s. 40)](#10-medication-s-40)
11. [Accident reports (s. 36(4))](#11-accident-reports-s-364)
12. [Serious occurrences (s. 38)](#12-serious-occurrences-s-38)
13. [The daily written record (s. 37)](#13-the-daily-written-record-s-37)
14. [The family surface — stories, alerts, messages](#14-the-family-surface--stories-alerts-messages)

---

## 1. Attendance — the three-layer model

### The single biggest design decision

**Attendance is not one thing.** Ontario's rules imply three distinct record layers, and mixing them corrupts the one an inspector reads.

| Layer | Question it answers | Records | Regulation |
|---|---|---|---|
| **Legal attendance** | Was the child in our care today, from when to when? | `arrive` / `depart` / `absent`, actual times, corrections | s. 72(3) — the inspectable record; $750 penalty per missing entry |
| **Location** | Which room's ratios does this child count against right now? | `room_transfer` (one continuous history), `staff_shift` | ss. 8–11 ratios, licensed capacity |
| **Supervision** | Did a named person just count faces against the list? | `headcount_check` | s. 11, Part 4 drill records, safe-arrival policy |

### Why sessions do NOT take attendance

A compliance position, not a shortcut. s. 72(3) demands *actual* arrival and departure times captured at the event. If going to the playground wrote a `depart` and coming back wrote an `arrive`:

- the legal record would show a child "departing" at 10:00 who was in the centre's care the whole time — **false on its face to an inspector**;
- real pickup times would drown in session noise, and the one time that matters in a dispute ("when did she actually leave?") becomes ambiguous;
- sign-out is legally meaningful — release to an authorised person under s. 50. A transition to the yard must never share a record type with that.

So: going outside is a `transition_out` headcount plus an `outdoor` period. Moving rooms is a `room_transfer`. Neither touches the legal attendance day.

### What Tucked does

Every attendance write goes through `record_attendance(p_centre, p_child, p_event_type, p_room, p_actual_time, p_recorder, p_pin, …)` — a `SECURITY DEFINER` RPC. (Note the order: the event type comes before the room.) There are **no client insert policies** on `attendance_event`. The PIN resolves *who* is recording, so a shared room tablet still produces individually attributable records.

Rows are **append-only**. A mistake is fixed by inserting a correction row that points at the original with a reason; the original stays. Every read that reasons about the register ignores an event that has a correction pointing at it.

### Every case

| Situation | What happens |
|---|---|
| Valid arrive, correct PIN | Recorded. `attendance_date` derived from the centre's timezone, not the server's |
| Recorder has no care role here | `recorder has no care role at this centre` |
| Wrong PIN | `invalid staff PIN` |
| PIN not 4–6 digits (when setting) | `PIN must be 4-6 digits` |
| Setting somebody else's PIN | `not authorised to set this PIN` |
| Any `UPDATE` of an attendance row | `attendance events are never updated; record a correction` |
| Child belongs to a different centre | `child is not enrolled at this centre` |
| `depart` with no `arrive` that day | `depart requires a same-day arrive` |
| Correction pointing at another child's event | `correction must reference an event for the same child` |
| Sign-out to a restricted person | `release blocked: this person is restricted for this child` |
| **Sign-in of an excluded child** | `sign-in blocked: {name} is excluded ({reason}). Before they come back: {criteria}` — see §9 |
| Sign-in of an excluded child **as a correction** | **Allowed.** The register must always be able to state what actually happened |
| A volunteer or student attempts to record | Refused — they hold no care role for this purpose |
| Recorded offline | Queued on the device with `offline_recorded_at`; `offline_synced_at` is stamped on arrival. Both are part of the audit trail |

### Where it lives

`attendance_event`, `staff_pin`, `pickup_authorisation`, `pickup_restriction`, `staff_shift`, `safe_arrival_check`. RPCs: `record_attendance`, `set_staff_pin`, `record_staff_shift`, `close_staff_shift`, `record_safe_arrival_outcome`. Trigger: `app.attendance_event_rules()` — **amended twice**, by 0030 (illness block) and reasoned about by 0038.

Console: **Attendance** (register, CSV, print). Room app: the sign-in board.

### Where this is weak

- **A lost response on a flaky connection can duplicate a record.** The offline queue only learns "network error" — it cannot distinguish "the write never arrived" from "the write succeeded and the reply was lost", so it retries, and the RPCs carry no idempotency key. The fix is a client-generated command id unique per centre on the write RPCs; that is a change across roughly thirty functions, which is why it is written down rather than done speculatively. See [06](06-gaps-risks-and-roadmap.md).
- **`app.attendance_event_rules()` is now a shared choke point** amended by a later migration. Every future edit must start from the live definition, not from 0005.
- **Absences are recordable but nothing chases them.** `safe_arrival_check` exists and the domain package has the timing logic; the "expected but not arrived" sweep is thin compared with the illness and push sweeps.

---

## 2. Safe arrival and dismissal (s. 50)

### What the regulation demands

A policy that ensures a child who is expected and does not arrive is followed up, and that a child is released only to a person the parent has authorised.

### What Tucked does

- `pickup_authorisation` lists who may collect a child.
- `pickup_restriction` is the harder record: a person who **must not** be given the child. It blocks at SQL level inside `app.attendance_event_rules()`, in the same block as the illness exclusion — so it cannot be bypassed by a client, an import, or a well-meaning educator on a tablet.
- `safe_arrival_check` records the outcome of following up an expected non-arrival, via `record_safe_arrival_outcome`.
- `packages/domain/src/safeArrival.ts` holds the pure timing logic shared by the room device and any sweep.

### Every case

| Situation | What happens |
|---|---|
| Release to an authorised person | Recorded as a `depart` with the person named |
| Release to a restricted person | `release blocked: this person is restricted for this child`. No override exists in any UI |
| Release to somebody not on the list | Permitted at schema level and recorded — the regulation requires a *policy*, and a real centre sometimes releases to a person authorised verbally. The record names them, which is the compliance-relevant part |
| Expected child has not arrived | The room board surfaces it; following up is recorded through `record_safe_arrival_outcome` |

### Where this is weak

- **The "not on the list" case is a judgment call the schema does not make.** That is deliberate — but a centre that expects Tucked to *stop* an unauthorised pickup will be disappointed. Only an explicit restriction stops anything.
- **There is no automatic escalation** when an expected child does not arrive. The information is present; the chase is human.

---

## 3. Ratios and supervision (ss. 8–11, Schedule 1)

### What the regulation demands

Age-group ratios and maximum group sizes from Schedule 1; specific rules for reduced-ratio windows (opening, closing, rest periods); volunteers, students and resource consultants **never** counted toward ratio; a floor of two adults once six or more children are present.

### What Tucked does

The engine is **pure TypeScript** in `packages/domain/src/ratios.ts` and `ageGroups.ts`, with 21 tests named `s8_*` / `s11_*`. It runs identically on a room tablet with no network, in a test fixture, and against seeded data.

Schedule 1's numbers live in `AGE_GROUPS` with a comment that says they are regulation, not configuration, and are pinned by `sched1_*` tests.

Who is *in* ratio comes from `staff_shift` rows recorded through `record_staff_shift` — which is why a volunteer's presence is recorded but never counted.

### Every case

| Situation | What happens |
|---|---|
| RECE on shift in an infant room | Counted |
| Volunteer on shift | Recorded, **never counted** (`s8_volunteer_never_counted_in_ratio`) |
| Student on placement | Recorded, never counted |
| Volunteer tries to record attendance | Refused (`s8_volunteer_cannot_record_attendance`) |
| Six or more children present with one adult | Ratio breach surfaced |
| Reduced-ratio window (open/close/rest) | Applied per Schedule 1's windows and floors |
| **Outdoors** | Full ratio. Reduced ratios never apply outdoors, and the room board's engine treats it that way |
| Mixed-age or family grouping | Handled by the family preset in `presets.ts` |

### Where this is weak

- **Ratio is computed, not enforced.** Nothing in the database refuses a write because the room is out of ratio — and it should not, because the record of a breach is exactly what an inspector needs. But that means ratio is a *display*, and the only consequence of a breach is that somebody looks at a screen.
- **Reduced-ratio windows are time-based, not event-based.** A centre whose rest period genuinely runs at an unusual hour needs its window configured; nothing detects the mismatch.
- **Staff shifts are recorded, not scheduled.** There is no roster, so "who should be here" does not exist and cannot be compared to "who is".

---

## 4. Headcounts and evacuation (s. 11, Part 4)

### What Tucked does

`headcount_check` records **who counted** (PIN-signed), **when**, which room or the whole centre, **expected vs counted**, and a snapshot of anyone unaccounted for at that moment.

Kinds: `transition_out`, `transition_in`, `spot`, `evacuation_drill`, `evacuation`.

Headcounts are append-only, audited, and offline-queued like every regulated write. They deliberately **do not modify presence** — a missing child at a headcount is an emergency to act on, and the snapshot proves what was known when. It is not a data edit.

### The evacuation sequence

This is the reason the architecture is offline-*first* rather than offline-tolerant.

1. **Alarm.** Any staff device opens the Evacuation screen in one tap. It renders **entirely from the on-device cache**, refreshed opportunistically whenever Room mode loads: every enrolled child, present/absent state, room, allergies, medications, an emergency contact. **No sign-in wall, no network, ever** — s. 82(2)'s "never locked away" rule applied literally.
2. **Muster.** Staff tap each child as they physically count them. Face-to-name, not memory. The tally reads "Headcount 17 of 18" until it does not.
3. **Account or act.** Anyone uncounted is visible by name with their room; the family contact is one line away.
4. **Record.** One button records the muster as a `headcount_check`, PIN-signed, with the missing snapshot — queued offline and synced later.
5. **Cross-reference.** `app.headcount_cross_reference()` writes the drill into the daily written record, which is the written record Part 4 demands.
6. **Schedule.** The compliance calendar tracks drill *cadence*; `app.headcount_completes_drill` closes the scheduled task when a real drill is recorded, so a centre never records the same drill twice.

### Every case

| Situation | What happens |
|---|---|
| Everyone counted | Recorded, cross-referenced into the day's record |
| Someone missing | Recorded **with the snapshot of who** — the record is the evidence of what was known at that minute |
| Recorded with no network | Queued; the evacuation screen itself never needed the network |
| Device has never been online | **The cache is empty and the screen is useless.** See below |
| A drill is due on the compliance calendar | Recording a real drill completes the task automatically |

### Where this is weak

- **The evacuation cache is per-device.** A tablet that has never been online has nothing cached. There is no seeding mechanism, no "prime this device" step in setup, and nothing warns that the cache is stale or absent.
- **The runbook has never been run on real hardware.** Everything above is proven by 15 automated tests against a mocked AsyncStorage. The device script exists ([06](06-gaps-risks-and-roadmap.md)) and needs an EAS dev build nobody has asked for.
- **A headcount cannot be corrected.** Append-only is right, but there is no correction shape here the way there is for attendance, so a miscounted drill stays miscounted with no linked amendment.

---

## 5. The care log (s. 32 and the daily sheet)

### What Tucked does

One table, `care_log`, carries every daily-sheet event: `meal`, `bottle`, `nap_start`, `nap_end`, `sleep_check`, `diaper`, `toilet`, `outdoor`, `health_observation`, `activity`, `note`, `photo`.

Each type has a **typed payload validated in SQL** by `app.validate_care_log_payload`, mirrored (imperfectly — see below) by Zod schemas in `packages/domain/src/careLogSchemas.ts`.

`record_care_log_bulk` is the educator time-saving wedge: one tap logs the same event for many children in a room.

**s. 32** — a child is observed for symptoms of ill health on arrival, before joining the others — is a `health_observation` log whose payload can carry a parent-reported symptom ("restless night").

### Payload rules, by type

| Type | Required | Optional |
|---|---|---|
| `meal` | `meal` ∈ breakfast/lunch/snack_am/snack_pm, `eaten` ∈ none/some/most/all | `notes` |
| `bottle` | `amount_ml` (number), `kind` ∈ breast_milk/formula/milk/water | `finished` |
| `nap_start` | — | `position` ∈ back/side/front *(required by the rules trigger under 12 months — §6)* |
| `nap_end` | — | — |
| `sleep_check` | `breathing_ok` (boolean) | `position`, `repositioned` (boolean), `intervention` |
| `diaper` | `kind` ∈ wet/soiled/both/dry | `cream_applied`, `supplies_remaining` |
| `toilet` | `kind` ∈ urine/bm/attempt/accident | — |
| `outdoor` | `minutes` **or** `skipped_reason` | `weather_reason` |
| `health_observation` | `observation` (non-empty) | `parent_reported`, `symptoms[]` |
| `activity` | `description` (non-empty) | — |
| `note` | `text` (non-empty) | — |
| `photo` | `storage_path`, `captured_at` | — |

### Every case

| Situation | What happens |
|---|---|
| Valid log with a valid PIN | Recorded; `log_date` derived from the centre's timezone |
| Any `UPDATE` | `care logs are never updated; record a correction` — **except** when `app.is_anonymising()` is true, the s. 72(5) retention path |
| Payload fails its type's schema | `invalid payload for care log type {type}` |
| Child at another centre | `child is not enrolled at this centre` |
| Correction pointing at another child's log | `correction must reference a log for the same child` |
| Sleep check in a preschool room | `sleep checks apply to infant, toddler or family rooms only` |
| Sleep check on a child 24 months or older | `sleep checks apply to children under 24 months` |

### Where this is weak

- **The two faces of the payload schema drifted for the entire life of the project.** `position` was an enum in TypeScript and completely unvalidated in SQL until migration 0038. The header comment on 0006 said "change both together"; nothing tested it. **There is still no mechanical check** that the Zod schemas and `app.validate_care_log_payload` agree.
- **`payload jsonb` is flexible to a fault.** Unknown keys are accepted silently. A client typo (`positon`) writes successfully and disappears.
- **No per-room configuration of which types are offered** beyond the room preset — a centre wanting a custom log type has no path.

---

## 6. Sleep (s. 33.1)

### What the regulation demands

- A child under 12 months is **placed on their back** for sleep unless the child's physician recommends otherwise **in writing**.
- **Direct visual checks** of every sleeping child under 24 months in infant, toddler or family groups — by physically going to the child, at the frequency set in the centre's sleep policy, **documented**. Electronic monitors, if used, are checked daily and **never replace** direct checks.
- Toddler and preschool rest periods are **no longer than two hours**.

### The line this module draws

> **Placing** a child is an act. It is regulated, and it can be refused.
> **Finding** a child somewhere is an observation. It is never refused.

`nap_start` is the placing, so that is where a write can fail. A sleep check records what an educator saw after walking to the crib — and babies roll. Refusing to record a baby found on her front would not make her safer; it would delete the only evidence that somebody noticed. **Checks always write**, and the system raises a finding instead of swallowing the fact.

### What Tucked does

- **The check cadence** lives in `room.sleep_check_interval_minutes` (5–30, default 15). The room device prompts at that interval.
- **`sleep_direction`** is the written direction, shaped after the s. 47 outdoor exemption, with one difference that is the regulation's difference:
  ```sql
  constraint only_a_physician_varies_sleep_position
    check (kind <> 'position' or source = 'physician')
  ```
  A family may ask for a great deal about their child's rest — `kind = 'rest'`, source `parent` — and the centre should hear all of it. But **a parent cannot authorise a baby onto their front.** The row will not store, so no screen can offer it and no import can smuggle it in.
- **Back is always permitted.** `app.permitted_sleep_positions(child, date)` unions `'back'` with whatever a live direction adds. A physician's note **widens** the choice; it can never narrow it to something unsafe.
- **Two findings, as views** — derived, not recorded, because there is no human input beyond what the log already holds, so a table could drift from the logs and a view cannot:
  - `sleep_position_finding` — under 12 months, found off their back, nothing on file permitting it.
  - `long_rest_finding` — a toddler or preschool rest past two hours.
  Both cross-reference into the s. 37 record at the moment they happen.
- **`sleep_placement_options(child)`** tells the nap board which positions to offer, so an educator is never offered a choice the write will then refuse.

### Every case

| Situation | What happens |
|---|---|
| Under 12 months, `nap_start` with no position | `record how {Name} was placed for sleep (back, side or front) — under 12 months it is the regulated fact` |
| Under 12 months, placed on back | Recorded |
| Under 12 months, placed on front, no direction | `under 12 months, {Name} is placed on their back unless a physician has recommended otherwise in writing. Record the physician's direction first.` |
| Under 12 months, placed on side, physician's direction permits side | Recorded |
| Under 12 months, placed on front, direction permits **side only** | Refused — a direction permits exactly what it says |
| Direction has expired or been superseded | No longer permits; back only |
| **A correction** to a `nap_start` | **Allowed through.** A register that cannot state a breach is worth less than one that can |
| 12 months or older, `nap_start` with no position | Fine — the rule does not apply |
| Sleep check finds a baby on her front | **Always recorded.** Appears in `sleep_position_finding`, on the console sleep screen, as a **Now** line on the console home, and as a sentence in the day's written record |
| That check also says `repositioned: true` | The day's record says "and was placed back". Without it: "The record does not say whether they were repositioned" |
| Parent tries to authorise a position | Constraint violation `23514` — the console form does not even offer the combination |
| Physician direction with no practitioner named | `a physician's direction names the physician` |
| Direction permitting an invented position | Constraint violation — the array must be a subset of back/side/front |
| Parent rest request from a non-consenting member | `the direction must come from a consenting household member` |
| A new direction of the same kind | Supersedes the old one. **The other kind is untouched** — a physician's position note and a family's rest request are different things |
| Toddler rest runs 150 minutes | `nap_end` is **never refused**. `long_rest_finding` shows 150 minutes; the day's record says "s. 33.1 sets the rest period at no longer than two hours" |
| Client `DELETE` of a direction | Matches no rows and **raises nothing** (no delete policy). The rows survive |
| A `DELETE` that gets past RLS | `audit_event is append-only` |

### Where it lives

`sleep_direction`, `care_log(nap_start, nap_end, sleep_check)`, views `sleep_position_finding` / `long_rest_finding`, functions `app.permitted_sleep_positions`, `app.sleep_cross_reference`, RPCs `record_sleep_direction`, `end_sleep_direction`, `sleep_placement_options`. Migration 0038. **40 pgTAP tests.**

Console: **Sleep** — findings card, the register, the directions card with a PIN-gated form. Room app: the nap board.

### Where this is weak

- **The room device does not yet call `sleep_placement_options`.** The function exists and is tested; the nap board still offers positions generically and relies on the refusal. That is safe but it is a bad interaction — an educator learns the rule by being told no.
- **`long_rest_finding` uses `lead()` over the day's logs** and assumes naps do not interleave. A child with two overlapping nap records in one day produces a confusing pair.
- **The compliance calendar has a `sleep_monitor_check` task** for the daily electronic-monitor check, but nothing links a monitor to a room, so it is a reminder rather than a record of *which* monitor.
- **Nothing enforces the check cadence.** The interval is configured and the device prompts, but a missed check produces no finding. The register shows what was done; it does not show what was skipped.

---

## 7. Outdoor play (s. 47)

### What the regulation demands

Two hours outdoors for a child in care six hours or more, **weather permitting**; thirty minutes for a shorter day. Both numbers are **data, keyed by jurisdiction** (`outdoor_requirement`), so another province is a row.

### What Tucked does

- `outdoor_period` is a **measurement**: the room goes out, the room comes in. An open period counts up to now, so the room device shows a live total.
- `outdoor_day` (view) sums the room's periods.
- **`outdoor_by_child(centre, date)`** is the one the regulation actually asks about. A child gets credit only for periods that overlap their own attendance in that room. Corrected attendance rows are ignored, exactly as the register ignores them.
  - It reports `hours_expected` as *hours so far plus hours left before the centre closes* — because asking only "how long have they been here" would tell a supervisor at 3 p.m. that a full-day child is owed thirty minutes and has met it.
  - Expected hours are capped at the operating day, so a 10.5-hour centre never reads "13.5 h expected".
- `outdoor_shortfall` is the **written reason** a day fell short. "Weather permitting" is only a defence if it was written down.
- `outdoor_exemption` is a physician's or parent's written instruction that a child stays in.

### Every case

| Situation | What happens |
|---|---|
| Room goes out | `start_outdoor_period`; the board shows a live counter |
| Room is already outside | `this room is already outside — record coming in first` |
| Recording a period starting in the future | `outdoor time is recorded when the group goes out, not ahead of it` |
| Room comes in when it is not out | `this room is not outside` |
| Editing a closed period | `this outdoor period is already closed; record a new one` |
| Editing the time the group went out | `the time the group went out is never edited` |
| A short day with no reason | Surfaces on the console home once the day is winding down — *before* that it is simply not done yet |
| Recording the shortfall | `record_outdoor_shortfall` → cross-references into the day's written record with the reason |
| Shortfall with no reason | `say why the day was short — "weather permitting" is only a defence if it was written down` |
| Shortfall dated in the future | `a day that has not happened yet cannot have fallen short` |
| Child kept in on a physician's note | `record_outdoor_exemption`; the child is `exempt` in `outdoor_by_child` |
| Exemption with no instruction text | `record the written instruction — that is the whole of the exemption` |
| Physician exemption with no physician named | `a physician's instruction names the physician` |
| Parent exemption from a non-consenting member | `the instruction must come from a consenting household member` |

Block times render in the **centre's** timezone via `hhmm(iso, centre.timezone)`, not the reader's.

### Where this is weak

- **The age floor (18 months) and the 6-hour threshold are seeded from a summary, not from the s. 47 text.** Flagged in the migration header and in [06 §4](06-gaps-risks-and-roadmap.md). A row change, but somebody must confirm it.
- **Weather is manual.** No weather API by design (a dependency and a cost), so "weather permitting" is whatever the educator typed.
- **`outdoor_by_child` is a heavy function** run per page load. Fine for one centre; unexamined at scale.

---

## 8. Menus, substitutions and feeding (ss. 42–44)

### What the regulation demands

The menu for the **current and the following week** must be planned and posted where parents can see it. What is actually served, if it differs, is recorded **on the day**. Feeding instructions from a parent are followed.

### What Tucked does

- `menu_week` and `menu_item` hold the plan. Posting freezes it.
- `menu_substitution` records what was served instead, and why — **at the time**, not before.
- `feeding_instruction` carries a parent's instruction and must come from a consenting household member.
- Posted weeks are readable by **every centre member, families included** — that is what "posted where parents can see them" means here.
- The console flags a missing following week.

### Every case

| Situation | What happens |
|---|---|
| Editing a posted week | `this week is posted — record a substitution on the day instead of editing the menu` |
| Menu item with no description | `a menu item needs a description` |
| Posting a week with nothing on it | `there is nothing on this menu to post` |
| Posting a week already posted | `that week is already posted` |
| Posting a week with no plan | `no menu planned for that week yet` |
| Substitution with no reason | `a substitution records what was served instead and why` |
| Substitution dated before the day | `substitutions are noted at the time — not before the day` |
| Feeding instruction with no parent named | `record the parent` |
| Feeding instruction from a non-consenting member | `feeding instructions must come from a consenting household member` |
| Ending an already-ended instruction | `already ended` |
| Next week not posted | Console home: **Due** — "Menus (s. 42): next week's menu is not posted" |

Substitutions are quoted verbatim into the day's written record.

### Where this is weak

- **Allergy cross-checking is not automatic.** The allergy list (s. 43(3)) and the menu are separate; nothing warns that Tuesday's lunch contains an allergen a child on the posted list reacts to. This is the most valuable unbuilt feature in the module.
- **No nutrition validation** against Canada's Food Guide, which the Manual expects a menu to follow. Menus are free text.
- **Menus are centre-wide.** A centre with a separate infant menu has no shape for it.

---

## 9. Illness, exclusion and public health (s. 36)

### What the regulation demands

A child who becomes unwell is **separated** from the others, the **parent is contacted**, and the child **goes home** — and every part of that is recorded. If the situation is urgent and no parent can be reached, the child is seen by a **physician or registered nurse**. Exclusion and return follow the centre's **illness policy, developed with the local public health unit**. Public health orders are kept and **forwarded to the program advisor**.

### What Tucked does

**The load-bearing piece:** an excluded child **cannot be signed in**. This is enforced inside `app.attendance_event_rules()`, beside the s. 50 restricted-person block:

```sql
if new.event_type = 'arrive' and new.correction_of is null then
  select * into excl from public.health_exclusion
  where child_id = new.child_id and returned_at is null;
  if excl.id is not null then
    raise exception 'sign-in blocked: % is excluded (%). Before they come back: %', …
  end if;
end if;
```

Note the `correction_of is null` — **a correction may still be recorded**, because the register must always be able to say what actually happened.

**The return criteria are copied from the policy, never typed freehand.** `illness_policy` is auto-seeded per centre and leadership-editable; every exclusion's return criteria come from it. That is what makes "what the family was told" a stable fact rather than an educator's paraphrase.

`health_exclusion_contact` is **append-only and records every attempt**, not just the successful one — an unanswered call is evidence of diligence and belongs in the record.

`public_health_notification` carries a **computed advisor deadline** (two business days, using the same `statutory_holiday` table as the serious-occurrence clock).

### Every case

| Situation | What happens |
|---|---|
| Recording an illness | `record_illness`: symptom, where the child is waiting, return criteria copied from the policy |
| Symptom not in the centre's policy | `that symptom is not in this centre's illness policy` |
| No separation location recorded | `record where the child is waiting — s. 36 separates them from the others` |
| Illness dated in the future | `a child cannot have become unwell in the future` |
| Child already excluded | `this child is already excluded and has not been cleared to return` |
| Editing the reason or the return criteria | `the reason and the return criteria are what the family was told; they are never rewritten` |
| Recording a contact attempt | `record_illness_contact` — every attempt, answered or not |
| Contact with nobody named | `record who was contacted` |
| **An unanswered call** | Recorded as an attempt; it does **not** count as a parent reached (`s36_an_unanswered_call_is_not_a_parent_reached`) |
| Urgent, no parent reachable | `record_illness_practitioner` names the physician or RN who saw the child |
| Practitioner with no name | `name the physician or registered nurse who saw the child` |
| Clearing for return | `clear_for_return` with a note saying how the criteria were met — **that note is the clearance** |
| Clearing with no note | `say how the return criteria were met — that note is the clearance` |
| Returning **earlier** than the policy allows | `the policy says not before {date} — record why they may come back sooner (a physician's note, for example)` |
| Clearing an already-cleared child | `this child has already been cleared` |
| Sign-in while excluded | Blocked, naming the child and the criteria |
| **Going home** while excluded | **Never blocked** (`s36_going_home_is_never_blocked`) |
| Setting the illness policy as a non-leader | `the illness policy is the licensee's` |
| A policy symptom with no return criteria | `every symptom needs its return criteria — that is what families are told` |
| Recording a public health order | `record_public_health_notification` with the unit named |
| Order with no detail | `record what happened and which public health unit it involves` |
| Forwarding to the program advisor | `forward_to_program_advisor` with **how it was sent** — the evidence is the point |
| Forwarding with no method | `record how it was sent — the evidence is the point` |
| Forwarding twice | `this order has already gone to the program advisor` |
| Closing before forwarding | `send the order to the program advisor before closing this — that is the duty, not the paperwork` |
| Deadline approaching | `app.public_health_reminders()` runs daily at 08:20 |

### Where this is weak

- **The seeded exclusion periods are the standard Ontario set, not this centre's.** s. 36 says the policy is developed *with the local public health unit*. Every pilot centre must review and edit it. Flagged in [06 §4](06-gaps-risks-and-roadmap.md).
- **No outbreak concept.** A public health order is a single record; "we are in an outbreak, these are the rules this week" has no shape.
- **Exclusion is per child, not per cohort.** A room-wide closure is recorded as N exclusions.

---

## 10. Medication (s. 40)

### What the regulation demands

**Written parent authorisation** with the **dose** and either a **schedule** or **specific symptoms** — "as needed" alone is insufficient. Medication in its **original container** with the child's name and the instructions. **One designated person** administers. **Every administration is logged**, including blanket-authorised items (sunscreen, diaper cream). **Expired medication is never administered.**

### What Tucked does

`medication_authorisation` carries the dose, the schedule or symptoms, the container checklist, and the expiry. `medication_administration` logs every dose. Blanket items are identified by `app.medication_is_blanket` and still produce a log line each time.

Authorisations are **never edited** — revoke and record a new one. Administrations are **never updated** — record a correction.

### Every case

| Situation | What happens |
|---|---|
| Dose + schedule | Authorised |
| Dose + specific symptoms | Authorised |
| **"As needed" with no dose or symptoms** | Refused (`s40_as_needed_alone_is_insufficient`) |
| Authorisation from a non-consenting household member | `authorisation must come from a consenting household member` |
| Editing an authorisation | `a medication authorisation is never edited; revoke it and record a new one` |
| Administering with no authorisation | `administration requires an authorisation for this child` |
| Administering after revocation | `authorisation has been revoked` |
| Administering expired medication | `medication is expired; do not administer` |
| Updating an administration | `medication administrations are never updated; record a correction` |
| Sunscreen under a blanket authorisation | **Still logged**, every time (`s40_blanket_items_are_logged`) |
| Any administration | Cross-references into the day's written record |

### Where this is weak

- **"One designated person" is not enforced.** The regulation names a designated person per centre; Tucked records *who* administered (the PIN) but does not restrict administration to a designated role.
- **The original-container checklist is a boolean, not evidence.** Nobody photographs the label.
- **No dose-interval guard.** Two doses ten minutes apart are both recorded with no warning.
- **Self-administered medication** (an older child with an inhaler) is summarised in the daily record but has no distinct authorisation shape.

---

## 11. Accident reports (s. 36(4))

### What the regulation demands

A report of the accident, and **evidence that the parent received a copy**.

### What Tucked does

`accident_report` records the child, the completer, what/where/when, the injury, the severity and the first aid given. A **hard head hit is recorded even without symptoms** and carries a mandatory concussion-watch note.

**The acknowledgement is the evidence.** A database trigger (`app.accident_notify`, migration 0015) creates a **Now** alert per viewing household adult, carrying the report id, so **one acknowledgement closes both records**. That is deliberate: the parent should not have to acknowledge twice, and the compliance evidence should not depend on app goodwill.

Every report cross-references into the day's written record.

### Every case

| Situation | What happens |
|---|---|
| Report recorded | Now alerts fan out to every viewing household adult automatically |
| Hard head hit, no symptoms | Still recorded; concussion note required (`s36_4_head_injury_requires_concussion_note`) |
| Parent acknowledges | Timestamped; **this is the s. 36(4) evidence**. The recipient's alert settles at the same time |
| Somebody who is not a household member acknowledges | `only a household member of this child may acknowledge` |
| Editing a report | `accident reports are never edited; only the parent acknowledgement may be added` |
| Editing an acknowledged report | `an acknowledged accident report never changes` |
| Child at another centre | `child is not enrolled at this centre` |
| The parent has no phone signed in | Console home: **Due** — "An urgent alert is waiting in the app for {name}, who has no phone signed in — so it will not ring. Call them." |

### Where this is weak

- **Acknowledgement in-app is the only evidence shape.** A parent who is handed a paper copy and signs it has nowhere to record that, so a centre doing it the old way gets no credit.
- **No photo attachment** on an accident report.
- **Severity is a free choice**, with no escalation rule linking a severe injury to the serious-occurrence path. A supervisor must notice.

---

## 12. Serious occurrences (s. 38)

### What the regulation demands

The most expensive record in the regulation. Report through **CCLS within 24 hours** of the supervisor or licensee becoming aware ($2,000 penalty, escalating). Post an **anonymised summary for 10 business days** (weekends and Ontario statutory holidays do not count). Keep updating as information arrives. Abuse or neglect allegations carry a **CYFSA duty to report to a Children's Aid Society**.

### What Tucked does

The 24-hour clock runs from `aware_at`, not from the occurrence. `statutory_holiday` + `app.add_business_days` compute the 10-business-day posting window. `app.serious_occurrence_reminders()` runs hourly and sends a deadline warning and an overdue notice **exactly once each**.

**Tucked does not file with CCLS.** It prepares, reminds, holds the evidence, and records the CCLS number a human received. §9.14.

### Every case

| Situation | What happens |
|---|---|
| Recorded by an educator | `serious occurrences are recorded by the supervisor, a designate, or the licensee` |
| No description | `describe what happened — this record goes to the Ministry` |
| Occurrence dated in the future | `occurrence times cannot be in the future` |
| A named child at another centre | `child {id} is not enrolled at this centre` |
| Filing with no CCLS number | `the CCLS serious occurrence number is the evidence of filing — it cannot be blank` |
| Filing twice | `already filed in CCLS — record further information as an update` |
| Filing time in the future | `the filing time cannot be in the future` |
| Filing time before `aware_at` | `filed before the supervisor became aware — check the times` |
| **CCLS is down** | `record_serious_occurrence_fallback` records that the program advisor was phoned or emailed within the 24 hours, and who was contacted and how |
| Fallback with nobody named | `record who was contacted and how` |
| CAS report on a non-abuse occurrence | `the CAS duty applies to abuse or neglect allegations` |
| Update with no content | `an update needs content` |
| **Posting an abuse allegation** | `abuse or neglect allegations are never posted` |
| Blank posted summary | `the posted summary cannot be blank` |
| Summary that names a child | `the posted summary must be anonymised — it contains a child's name` |
| Closing before filing | `cannot close before the CCLS filing is recorded` |
| Closing an abuse allegation with no CAS report | `an abuse or neglect allegation cannot close without a recorded Children's Aid Society report` |
| Closing before the summary is posted | `cannot close before the anonymised summary has been posted` |
| Closing twice | `already closed` |
| Deadline within warning distance | One warning, exactly once |
| Deadline passed | One overdue notice, exactly once |

### Where this is weak

- **Statutory holidays are seeded 2026–2030.** After that both the serious-occurrence and public-health business-day clocks silently get *less accurate* rather than failing. Worth a reminder, not a cron.
- **Serious occurrence descriptions are not scrubbed by the child anonymiser.** They are Ministry-filed records with their own lifecycle. The console guidance encourages not naming children in free text; **nothing enforces it.**
- **The anonymisation check on a posted summary is name-matching**, so it catches "Maya Osei" and not "the little girl in the toddler room whose mum drives the red car".
- **No attachment or evidence bundle** on an occurrence.

---

## 13. The daily written record (s. 37)

### What the regulation demands

A **dated entry every operating day**, no exceptions, summarising the day and cross-referencing incidents, drills and accidents. Closed by a named human.

### What Tucked does

**The database writes the draft, not a person and not a model.**

- `pg_cron` creates the day's draft at 06:00 centre-local.
- `app.dwr_compose(centre, date)` builds it as **arithmetic over the day's own rows**: attendance counts, outdoor minutes per room, menu substitutions, sleep checks, medication doses, headcounts.
- Every incident is **quoted verbatim** from the cross-reference its own trigger wrote at the time — so the summary and the reference cannot disagree.
- The result is **deterministic, never generated**. `never_the_daily_record_draft_is_deterministic_not_generated` is a §9.14 test.
- The console shows a live preview and a **Redraft** button. A closed day refuses both.

Every module in this document writes into it: accidents, headcounts and drills, medication, outdoor shortfalls, illness cross-references, sleep findings, long rests.

### Every case

| Situation | What happens |
|---|---|
| 06:00 centre-local | Draft appears |
| The day changes after drafting | Console shows **Moved on** — "The day has changed since this draft was written. Redraft to pick up what has happened since" |
| Redrafting | Recomposes from current rows |
| Closing | Requires a named human (`closed_by`) and a written entry |
| Closing with an empty entry | `the daily written record needs a written entry` |
| Editing after close | `a closed daily written record never changes` |
| **Redrafting** after close | Also refused (`s37_and_a_closed_record_cannot_even_be_redrafted`) |
| A quiet day | Says so in one line (`s37_a_quiet_day_says_so_in_one_line`) |
| One of something | Never reads "1 childs" (`s37_one_of_something_never_reads_as_1_childs`) |

### Where this is weak

- **Nothing forces the close.** An unclosed record surfaces on the console home as **Due**, and that is the entire enforcement. A centre that ignores the console accumulates open days.
- **Per-centre by default.** Per-room records are supported by the same table (`room_id` set) but no surface creates them.
- **The composer is one function** doing string assembly in plpgsql. It is readable and tested, but every new module means editing it, and there is no registry of contributors.

---

## 14. The family surface — stories, alerts, messages

### The Now / Later rule

Routing lives in `packages/domain/src/notifications.ts` — **a table, not scattered `if`s**, so it can be shown to a supervisor and tested exhaustively.

| Channel | Behaviour | Contents |
|---|---|---|
| **Now** | Pushes immediately, sound on, **bypasses quiet hours**, requires acknowledgement | Illness/sent home, accident report, pickup problem, missing expected arrival, emergency, medication issue, supervisor-urgent |
| **Later** | **Never pushes.** Batched into the single daily story plus a badge | Meals, naps, diapers, photos, activities, menus, announcements |

Families may opt **up** per category. Quiet is the default.

Android gets two notification channels (Now = high importance with sound; Later = low, no sound) so OS behaviour matches the product promise. iOS uses time-sensitive interruption level for Now.

### The daily story

One calm, specific letter per child per day, composed by **`app.story_compose(child, date)`** as arithmetic over the day's own rows: the opening line from the day outside or the first activity, then meals in the order they were eaten, rest periods in 12-hour times, the rest of the activities, the photo count, and — if the child went home unwell — a plain sentence saying so rather than carrying on as though the day had been ordinary. A day with nothing in it still says something kind.

**Deterministic, never generated.** The same day composes to the same words; no model is involved.

**It publishes at pick-up**, which is what the family screen has always promised in its empty state. A `depart` fires `app.story_on_depart` and the story lands as the parent is collecting. `app.publish_daily_stories()` runs hourly as the floor: once a centre has closed, any child who arrived and has no published story gets one, so a forgotten sign-out costs a family a late story rather than no story.

**The publish trigger can never block a departure.** It runs inside the sign-out transaction, and a child being released to their parent must not depend on a story composing cleanly, so anything that goes wrong there is swallowed on purpose and left to the sweep. A late story is a disappointment; a sign-out that will not complete is an incident.

**The educator's own note always sits on top, untouched.** `save_story_note` writes it and publishes if the story has not gone yet; a recomposition never overwrites it.

AI polish is a labelled, optional Phase 2 add-on and **never a dependency** — the template-drafted story ships without it.

*(Composed in SQL rather than in `packages/domain`, for the reason `app.dwr_compose` is: it has to run when no client is present. The `buildStory()` that nothing called has been deleted and its voice tests ported to pgTAP — one implementation, not two.)*

### Messages and announcements

`message_thread` / `message` with an **explicit audience** and `app.can_see_thread`. `announcement` is the quiet centre-wide notice: Later channel, **never pushed**, appears in the family app's home.

Family adults can see the **workforce** of their centre by name — a parent must know which educator wrote back — while other **families stay invisible** to them. Adults within one household see each other.

### Every case

| Situation | What happens |
|---|---|
| An accident report is recorded | Now alert per viewing household adult, automatically, by trigger |
| A Now alert is unacknowledged | Surfaces on the supervisor's console home |
| The recipient has no device registered | `undeliverable_now_alerts` — console home says to call them |
| Somebody who is not the recipient acknowledges | `only the recipient may acknowledge` |
| A meal is logged | Later. Nothing rings. It appears in tonight's story |
| An announcement is posted | Later. Appears in the family home with no push |
| A family opts up on photos | Photos push for that family only |

### Where this is weak

This is the weakest module in the product relative to how central it is to the pitch. Three of the four items below are **written, not wired**.

- **The educator's note has no surface.** `save_story_note` is the RPC and nothing on either app calls it, so in practice every story is the composed draft with no human voice on top. The publishing itself is fixed; the note is not.
- **`long_rest_finding` and the story's own nap pairing both use `lead()`** over the day's logs and assume naps do not interleave. A child with two `nap_start` rows before one `nap_end` produces a pair measured from the *second* start. This was a live flake in the sleep suite for a while: an unrelated `now()`-anchored nap landed between a fixture's noon and 14:30 pair, and the long-rest test read 149 minutes instead of 150 — but only when the suite ran shortly after local noon.
- **The opt-up preference has no storage.** `routeNotification` takes a `prefs` argument with a `realtimeOptIn` set, and it is unit-tested, but **no table holds it and nothing passes it**. Every family therefore gets the default: quiet. The default is the right one, which is why this has stayed invisible.
- **Quiet hours are a property of the Now channel, not a per-family window.** Now bypasses quiet hours by design; there is no way for a family to say "nothing before 7 unless it is urgent", because there is no per-family window at all.
- **Messages have no attachments.**

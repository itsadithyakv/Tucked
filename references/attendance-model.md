# Tucked — the attendance model

*How attendance, sessions, transitions and evacuations fit together under
O. Reg. 137/15 — the reasoning behind what Tucked records and, just as
deliberately, what it refuses to record. Companion to
[tucked-ontario-requirements.md](tucked-ontario-requirements.md) §2.*

---

## 1. Three layers, three purposes

The single biggest design decision: **attendance is not one thing.** Ontario's
rules imply three distinct record layers, and mixing them corrupts the one an
inspector reads.

| Layer | Question it answers | Records | Regulation |
|---|---|---|---|
| **Legal attendance** | Was the child in our care today, from when to when? | `arrive` / `depart` / `absent`, actual times, corrections | s. 72(3) — the inspectable record; $750 penalty per missing entry |
| **Location** | Which room's ratios does this child count against right now? | `room_transfer` (one continuous history), staff shifts | ss. 8–11 ratios; licensed capacity |
| **Supervision** | Did a named person just count faces against the list? | `headcount_check` — transitions, spot checks, drills, evacuations | s. 11 supervision; Part 4 drill records; safe-arrival policy |

## 2. Why sessions do NOT take attendance

Should an outdoor session take its own attendance? **No — and this is a
compliance position, not a shortcut.** s. 72(3) demands *actual* arrival and
departure times, captured at the event. If heading to the playground wrote a
`depart` and coming back wrote an `arrive`:

- the legal record would show a child "departing" at 10:00 who was in the
  centre's care the whole time — false on its face to an inspector;
- real pickup times would drown in session noise, and the one time that
  matters in a dispute ("when did she actually leave?") becomes ambiguous;
- sign-out is legally meaningful (release to an authorised person, s. 50) —
  a transition to the yard must never share a record type with that.

What a transition *actually* requires is supervision evidence: **everyone who
went out came back in.** That is a headcount, not attendance. So in Tucked:

- Going outside = a `transition_out` headcount (face-to-name against the
  present list) + the `outdoor` care log (which doubles as the s. 46(6)
  outdoor-play evidence: minutes, or the weather reason it was skipped).
- Coming back = a `transition_in` headcount.
- Moving rooms = `room_transfer` (keeps one continuous history, per the
  requirements doc) — the child's ratio home changes; their legal
  attendance day does not.
- Ratios still apply outdoors, and reduced ratios never do — the room
  board's ratio engine already treats outdoors as full-ratio.

## 3. Headcounts: the face-to-name discipline

Every `headcount_check` records: **who counted** (PIN-signed), **when**, which
room (or the whole centre), **expected vs counted**, and a snapshot of anyone
not accounted for at that moment. Kinds:

- `transition_out` / `transition_in` — leaving for and returning from the
  yard, a walk, the gym;
- `spot` — any moment a staff member wants "I counted, we're whole" on the
  record;
- `evacuation_drill` / `evacuation` — see below.

Headcounts are append-only, audited, offline-queued like every regulated
write. They deliberately do **not** modify presence — a missing child at a
headcount is an emergency to act on (and the snapshot proves what was known
when), not a data edit.

## 4. How evacuation actually works

The sequence Tucked is built around, matching the Manual's requirement that
attendance works off-site with no network:

1. **Alarm.** Any staff phone/tablet opens the Evacuation screen in one tap —
   it renders **entirely from the on-device cache** (refreshed opportunistically
   whenever Room mode loads): every enrolled child, present/absent state,
   room, allergies, medications, an emergency contact. No sign-in wall, no
   network, ever — s. 82(2)'s "never locked away" rule applied literally.
2. **Muster.** Staff tap each child as they physically count them —
   face-to-name, not memory. The tally reads "Headcount 17 of 18" until it
   doesn't.
3. **Account or act.** Anyone uncounted is immediately visible by name with
   their room — the missing-child response starts from the screen, with the
   family contact one line away.
4. **Record.** One button records the muster as a `headcount_check`
   (`evacuation_drill` or `evacuation`), PIN-signed, with the missing
   snapshot — queued offline and synced later like everything else. The
   record **cross-references itself into the daily written record** (s. 37
   requires every drill summarised there), giving the drill the written
   record Part 4 demands.
5. **After.** The compliance calendar (Phase 2) tracks drill *scheduling*
   (monthly cadence, alarm tests); the headcount record is the evidence each
   drill happened and how it went. A real serious occurrence (unplanned
   disruption, missing child) additionally follows the s. 38 CCLS path —
   Phase 2's serious-occurrence helper.

## 5. What the inspector sees

- **Attendance register** (console): pure s. 72(3) — arrivals, departures,
  absences, actual times, corrections with who/when/why. No session noise.
- **Daily written record**: every drill and evacuation summarised
  automatically, closed by a named human.
- **Audit trail**: every headcount, who counted, expected vs counted.

## 6. Decisions locked here

1. Sessions/transitions never write attendance events (§2).
2. Headcounts never mutate presence (§3).
3. The evacuation screen stays outside authentication and off the network
   (§4.1); recording the muster is the only part that needs a PIN, and the
   offline queue carries it.
4. Drill scheduling is Phase 2 (`compliance_task`); drill *evidence* ships
   now via `headcount_check` → daily-written-record cross-reference.

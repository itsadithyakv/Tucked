# Airplane-mode runbook

*The scripted quality pass on a real device, owed since the offline work landed. Everything the queue's own logic can be held to is now automated in [`apps/mobile/test/queue.test.ts`](../apps/mobile/test/queue.test.ts) and runs in CI. **This runbook is only for what a test cannot see**: a real radio, a real OS killing a backgrounded app, a real basement.*

O. Reg. 137/15 s. 82(2) is the reason. Records kept electronically must be available to staff at all times, and the Licensing Manual specifically contemplates a phone used for attendance working off-site — an evacuation, a field trip. A screen that says "no connection, try later" during an evacuation is the failure this runbook exists to catch.

---

## What is already proven without a device

Do not spend device time on these; they run on every commit:

| Proven in CI | Test |
|---|---|
| An online write goes straight through, unqueued | `s82_2_an_online_write_goes_straight_through_and_is_not_queued` |
| A refused write (bad PIN, broken rule) is **never** queued — the educator is standing there and can fix it | `s82_2_a_refused_write_is_never_queued_because_the_person_is_standing_there` |
| A write with no signal is kept | `s82_2_a_write_with_no_signal_is_kept_rather_than_lost` |
| Later writes join the line rather than jumping it | `s82_2_later_writes_join_the_line_rather_than_jumping_it` |
| The queue flushes in the order it was written | `s82_2_the_queue_flushes_in_the_order_it_was_written` |
| Every queued write carries the moment it actually happened | `s82_2_every_queued_write_carries_the_moment_it_actually_happened` |
| A flush that hits the network again stops and keeps the order | `s82_2_a_flush_that_hits_the_network_again_stops_and_keeps_the_order` |
| A server refusal becomes visible rather than vanishing, and does not block what is behind it | `s82_2_a_rule_the_server_refuses_lands_in_front_of_a_human`, `s82_2_a_refusal_does_not_block_the_writes_behind_it` |
| The queue and its failures survive the app being shut | `s82_2_a_queued_write_survives_the_app_being_shut`, `s82_2_a_visible_failure_survives_it_too` |
| Corrupt storage starts empty rather than bricking the room device | `s82_2_corrupt_storage_starts_empty_rather_than_crashing_the_room_device` |

```bash
pnpm --filter @tucked/mobile test
```

---

## Before you start

- A **dev build** on a real phone (Expo Go cannot do remote push and behaves differently in the background). Ask before building — no EAS build is made without an explicit go-ahead.
- The device signed in as the educator, on the room board.
- A second device or a laptop on the console, so you can watch the other side.
- A stopwatch. Several steps are about how long something takes to feel wrong.

Write the answers in the table at the bottom. An unanswered row is a failed pass, not a skipped one.

---

## 1. The basic loop (5 minutes)

1. Open a room. Sign one child **in**. Confirm it appears on the console.
2. Airplane mode **on**. Wait for the app to notice.
   - **Watch for:** a calm, quiet indication that writes are being kept. Not a red error, not a modal, not a spinner that never resolves.
3. Sign a second child **in**, a third **absent**, and record a nappy change.
4. **Q1 — did every action complete without the app arguing?** The educator should not be able to tell the difference except for the pending indicator.
5. Airplane mode **off**. Do not touch the app.
6. **Q2 — how long until the queue drains on its own?** (The pump runs every 15 s.)
7. **Q3 — on the console, are the three records in the order they were made, with the times they were made — not the time the signal returned?**

## 2. The evacuation (10 minutes) — the one that matters

1. Airplane mode **on**.
2. **Force-quit the app.** Swipe it away. This is the step most likely to find something.
3. Reopen it. **Q4 — does the evacuation screen open with no network at all?**
4. **Q5 — does it show every child currently signed in, their emergency contacts, and the allergy list, with no spinner and no empty state?**
5. Walk outside, out of Wi-Fi range, on cellular-off airplane mode. **Q6 — does anything change or degrade once you are away from the building?**
6. Record an evacuation headcount, deliberately leaving one child uncounted.
7. **Q7 — does the missing-child prompt appear, and does it name the child?**
8. Airplane mode off. **Q8 — does the headcount arrive on the console with the missing-child snapshot intact?**

## 3. The long outage (20 minutes, mostly waiting)

1. Airplane mode **on**. Record **ten** actions across several children.
2. Leave the app **backgrounded for fifteen minutes**. Use other apps. Let the screen lock.
   - This is where iOS or Android may kill the process. That is the point.
3. Reopen. **Q9 — are all ten still pending?**
4. Airplane mode off. **Q10 — do all ten arrive, in order, with their original times?**
5. **Q11 — does the pending indicator return to zero, or does it stick?**

## 4. Flaky signal, not absent signal (10 minutes)

The hardest real case: a basement with one bar, not a plane.

1. Somewhere with genuinely marginal signal — a stairwell, a basement, a lift lobby.
2. Record five actions in quick succession while walking in and out of coverage.
3. **Q12 — does anything appear twice on the console?** *(See the known limitation below — if it does, capture exactly what you did.)*
4. **Q13 — does anything go missing entirely?** This must be no.
5. **Q14 — does the app ever show an error the educator cannot act on?**

## 5. Refusals from the far side (5 minutes)

1. On the console, exclude a child (Illness & exclusions).
2. On the device, airplane mode **on**, and sign that child **in**.
3. Airplane mode off and let it flush.
4. **Q15 — does the refusal appear as a visible, readable failure naming the child and the reason — rather than disappearing?**
5. **Q16 — can a person dismiss it once they have dealt with it, and does the dismissal stick after a restart?**

---

## Known limitation to watch for at Q12

A command that reached the server but whose **response** was lost — the write succeeded, the reply did not — is retried on the next flush, because the queue only learns "network error". There is no idempotency key on the RPCs, so that retry can create a **duplicate regulated record**.

This is recorded in [not-built.md](not-built.md). Marginal signal is exactly the condition that produces it, which is why §4 exists. If Q12 finds a duplicate, capture the two rows and the sequence of actions — that evidence is what would justify adding a client command id to the write RPCs.

---

## The record

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

File the completed table in `docs/`. A pass with an unanswered row is not a pass.

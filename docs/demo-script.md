# Tucked — the five-minute supervisor demo

*Local stack: `pnpm db:start && pnpm db:reset`, console `pnpm --filter @tucked/web dev`, app `pnpm --filter @tucked/mobile start`. Logins: `supervisor@` / `educator@` / `parent@mapleleaf.example`, password `tucked-demo`, staff PIN `1234`. The seed loads a full demo day at Maple Leaf Early Learning.*

**Minute 1 — "A program advisor just walked in."** Sign in to the console as the supervisor. The Today screen already answers the first questions: who is in each room right now, staff in ratio, what needs attention. Click **Attendance** — every child, actual times, who recorded each event, corrections with reasons. Download CSV. *"That's the s. 72(3) record, under ten seconds."*

**Minute 2 — the registers.** Click through **Daily written record** (auto-drafted every morning by the database, closed by a named human — show yesterday's, closed by you), **Accident reports** (the head-injury report with its concussion-watch note and the parent's acknowledgement timestamp — the s. 36(4) delivery evidence), **Medication** (the blanket zinc-cream administration — *"yes, we log those, the regulation says so"*), **Sleep checks** (per-child, timestamped, under-24-months only — the database refuses them anywhere else).

**Minute 3 — a child's record.** **Children's records → Maya Osei.** All 11 items of s. 72(1), each answered (never blank), verified by you. Press **"Medical officer copy (s. 72(6))"** — it prints items 2, 3, 8 and 9 and nothing else. *"The public-health inspector gets exactly what the regulation entitles them to."*

**Minute 4 — the room device.** Open the app as the educator, into the Infant room. Live ratio badge (10 present · requires 3 · OK). **Swipe a child** — sign-in with the arrival-observation prompt; a sleep check that's due shows loud. Record one with your PIN. Tap **Evacuation** — the full roster, allergies, contacts, headcount tally, working with the network off.

**Minute 5 — what the parent feels.** Sign in as the parent. One calm screen: each child, today's story as a short letter with the educator's note on top — and, when it matters, one loud red card: the accident report, acknowledged with one press (which *is* the compliance evidence). Show Messages: the parent chose "supervisor only" and that choice is printed on the thread. *"Quiet by default. Loud only when it matters. And every record an inspector needs, already filed."*

# Tucked — PaperKite's daycare app for Canada

*Plan v1.1 — 29 August 2026 (name updated after trademark/domain check). Toronto first, then the rest of Ontario, then Manitoba, Quebec last.*

---

## 0. The short version

**What:** A daycare app sold to small licensed child care centres in Toronto. Parents get a calm, once-a-day story of their child's day plus instant alerts only for things that matter. Operators get every record an Ontario licensing inspector will ask for, filled in as a side effect of normal work.

**Why this is winnable:** The big players (Brightwheel, Procare, Playground, myKidzDay) are American and built around US problems — filling seats, chasing tuition, US state licensing. In Toronto the problems are different: centres are already full, fees are capped by government, and the pain is *staffing, paperwork, and inspections*. Lillio (the old HiMama) is the one that knows Ontario — and it's headquartered in Toronto, so it's the incumbent to beat, not ignore.

**The wedge:** "Calm for parents. Boring inspections for operators." Nobody in the market owns either of those sentences.

**Name:** **Tucked** (by PaperKite) — confirmed after trademark, domain and app-store checks; see Section 12.

**Biggest honest risk:** You are one student running Unifloe in Bengaluru with two paying schools. This is a second product, in a second country, in a second time zone. Section 11 explains why I'd do discovery now but not write code until Unifloe's pilot schools are stable.

---

## 1. Why Toronto, and why now

### The market is big, dense, and mostly small operators
- Toronto has over 1,000 licensed centres and 24 licensed home child care agencies, with roughly 82,500 centre-based spaces at the end of 2024 — about 42,700 of them for infants, toddlers and preschoolers (the daily-report age group that needs an app the most).
- Ontario as a whole had 5,989 licensed centres and 154 home child care agencies overseeing about 5,860 homes as of March 2025.
- As of mid-2023, about two-thirds of Toronto centres were non-profit, 30% commercial, and 4% run by the City itself. That matters: non-profits buy on value-for-money and trust, not on sales pressure.

### Why the US playbook doesn't fit here
- **Centres are full, not empty.** Nationally, about 60% of Canadian centres were operating at maximum capacity in 2024, and Toronto still has "child care deserts." US apps sell "grow your enrolment, manage your waitlist, market your centre." A Toronto director does not need help finding families — she has a waitlist she isn't allowed to charge for.
- **Fees are capped by government.** Under the Canada-Wide Early Learning and Child Care (CWELCC) system, participating centres have had fees for under-6s capped at $22/day since January 2025 (the provincial average is around $19/day). Funding is confirmed through 2026 and reportedly extended into early 2027 while a longer deal is negotiated. Consequence: the "automated tuition collection" pitch that Brightwheel and Playground lead with is much weaker here. Billing is simpler and smaller; what operators need is clean expense and attendance records for cost-based funding reporting.
- **The pain is staffing and paperwork.** The sector has a well-documented Registered Early Childhood Educator (RECE) shortage. Every minute an educator spends typing into an app is a minute the director can't afford. The app has to *save* staff time, not create documentation homework.
- **Inspections have teeth.** Ontario's licensing manual attaches administrative penalties to missing records — $750 for missing attendance or children's records, $2,000 for a late serious-occurrence report, and up to $100,000 for repeats. That is the fear that opens the door.

### Why now
- CWELCC has pulled thousands of new spaces into the licensed system, and the province wants 86,000 new spaces by end of 2026. New rooms mean new record-keeping headaches and new parents to onboard.
- Toronto is bringing back its Assessment for Quality Improvement (AQI) inspections for centres with City service agreements. Directors will want their documentation in order.
- Canadian privacy law is being rewritten (a replacement for the failed Bill C-27 is expected, with children's privacy flagged as a priority). "Your children's data stays in Canada" will only become a stronger selling line.

---

## 2. Who we sell to first

**Ideal first customer:** an independent, single-site licensed centre in Toronto with 30–90 children across infant/toddler/preschool rooms, run by a supervisor/director who also answers the phone. Non-profit or small commercial. Either on paper + WhatsApp today, or unhappy on an incumbent app.

**Why this profile:**
- One decision-maker (the supervisor or the board chair). Same lesson as Bengaluru: reach the person who can say yes.
- Infant/toddler rooms have the heaviest daily-record load (sleep checks, feeding, diapering, medication) — the biggest time saving to show.
- Small enough that switching is a two-week job, not a procurement process.

**Second wave:** licensed home child care *agencies*. Toronto has 24 of them, each overseeing dozens of home providers through "home visitors." None of the big apps is built for the agency → provider → parent triangle. It's a niche the incumbents ignore, and an agency is one sale that lights up 30–100 homes.

**Not now:** City of Toronto-operated centres (municipal procurement, different privacy law), school-board-attached centres, multi-site chains (they'll want integrations and enterprise reporting you don't have yet).

---

## 3. The competitors, honestly

| | Home base | What they're known for | Where they're weak (from real reviews) |
|---|---|---|---|
| **Brightwheel** | San Francisco | The parent app everyone copies; billing automation; huge review count | Parents charged $30+ fees to pay by bank; can't cancel subscription online; "no human to talk to" when a dispute happens; app crashes; message goes to whoever — parents unsure who receives it; separated/second parent lost access after a location change; must click each child separately for the same message |
| **Procare** | US | Deepest billing and subsidy machinery; strong mobile app ratings | Overkill for a 40-child centre; late-payment chasing is manual; US subsidy logic (CCDF) is irrelevant in Ontario |
| **Lillio (ex-HiMama)** | **Toronto** | Curriculum documentation, developmental observations, Ontario familiarity | Photos hard to download, no dates on photos, low-res downloads; "entries vary by teacher"; too many bathroom updates; slow to load; can't pick which staff member to message; messages always copy the director; staff time-tracking sold as an extra; attendance messy when a child changes rooms |
| **Playground** | US | Automated tuition, staff scheduling, family comms | Built around collecting money — the least relevant problem in a $22/day-capped system |
| **myKidzDay** | US | All-in-one for home daycares and small centres; infant sheets; invoicing | US licensing/CACFP/W-10 reporting baked in; generic UI; no Canadian footprint |
| **Also present in Canada:** Storypark (NZ, popular for learning stories), Kids Note, Tadpoles, Sandbox, TUIO (Canadian, billing-focused). Check which ones your first ten prospects actually use before assuming. |

**Pricing reality:** Brightwheel, Procare and Lillio all make you request a quote. Reported figures (unverified) put Brightwheel at a base fee of roughly $15–30/month plus $2–3 per child, and Lillio around $8–12 per child per month. Setup fees, per-staff fees and paid add-on modules are common. A published, all-in Canadian price is itself a differentiator.

**Strategic read:**
- *Where to differentiate:* calm parent experience, Ontario compliance built in, transparent CAD pricing, Canadian data hosting, co-parent/household handling, photo ownership.
- *Where to reach parity (no more):* daily logs, messaging, photos, sign-in/out, basic invoicing.
- *Where NOT to compete:* tuition automation, US subsidy billing, curriculum marketplaces, staff payroll.
- *Nightmare scenario:* Lillio ships a "CCEYA inspection mode" and a calm-digest setting. They are in Toronto; they could. Speed and focus are your only defence.

---

## 4. What parents and educators actually wish for

*Note: Reddit itself wasn't reachable from my search tools, so this is drawn from Capterra, Trustpilot, SoftwareAdvice and parent essays — the same voices, just a different venue. Worth spending an evening on r/ECEProfessionals, r/daycare, r/askTO and Toronto parent Facebook groups yourself.*

### Parents
1. **Fewer, better updates.** Repeated theme: "all the bathroom updates get overwhelming"; parents describe information overload and guilt about muting notifications. One parent said they stopped reading reports because a bad-nap alert made them treat their toddler as grumpy before she even came home.
2. **The end-of-day story earlier and more consistently.** "Entries vary by teacher"; daily summaries arriving late.
3. **Own the photos.** Download easily, at full size, with the date taken. Keep them after the child leaves. Zoom in. One app "does not archive photos, so you need to screenshot them."
4. **Know who reads my message.** Parents can't tell whether a message goes to the teacher, the director, or both. They want to pick.
5. **Reliable urgent alerts.** A parent missed a sick-child email for hours because no notification fired. Urgent must be loud; routine must be quiet.
6. **Both households.** A second parent lost access after a centre reorganised. Separated parents, grandparents and nannies need proper, revocable access — not a shared login.
7. **Don't gouge me to pay.** Bank-transfer fees of $30+ made parents furious. In Canada people expect Interac e-Transfer or pre-authorized debit at near-zero cost.
8. **Siblings in one place.** Don't make me open each child's page for the same notice.
9. **Menus, sleep, and "what was different today"** — not just logs.

### Educators and directors
1. **Documenting steals time from children.** Every extra tap is resented. Voice or one-tap logging, bulk entry per room, and "log once, appears everywhere."
2. **Lesson plans and observations don't connect** — a photo tagged with a learning goal should land in the child's record automatically.
3. **Room moves break attendance.** When a child moves from toddler to preschool, records get messy.
4. **Support with a human.** Directors describe weeks without a reply from support on a disputed charge.
5. **No surprise fees.** Staff time-tracking, extra modules, per-staff charges.
6. **Consistency across staff** — the app should make an inconsistent teacher look consistent (templates, prompts, gentle nudges).

---

## 5. The wedge: what Tucked does that they don't

Each of these exists because of a specific complaint or rule above.

### For parents — "calm"
- **One daily story, not a firehose.** Default mode: a single end-of-day summary at pick-up time, written by the app from the day's logs (with a teacher-written note on top). Parents can opt *up* to real-time; the default is quiet. *Why:* information overload is the most consistent parent complaint and nobody has made calm the default.
- **Two channels only:** "Now" (sick, injury, pick-up change, emergency) which always pushes loudly, and "Later" (photos, meals, naps) which never interrupts. *Why:* the missed sick-child email.
- **Your photos are yours.** Full-resolution, dated, one-tap download; a lifetime archive that survives the child leaving the centre; a "graduation export" the day they leave. *Why:* the single most repeated Lillio/Tadpoles complaint, and it becomes your lock-in — parents will not want to lose years of dated photos.
- **Household, not account.** A child belongs to a household; each adult has their own login, role and notification settings; the centre can see and revoke each one. Handles separated parents, grandparents, and authorised pick-ups cleanly. *Why:* the Brightwheel co-parent failure; also matches Ontario's rule that parents must have access to their child's record.
- **Message with an address.** Every message shows exactly who will read it, and parents choose the teacher, the supervisor, or both. *Why:* two separate complaints about not knowing who receives messages.
- **Siblings in one feed.** *Why:* obvious, and still unfixed elsewhere.
- **Pay the Canadian way.** Interac e-Transfer reconciliation and pre-authorized debit with no parent-side fee. *Why:* the $30 fee complaint; and fees are small under CWELCC anyway.

### For operators — "boring inspections"
- **Attendance that satisfies section 72.** Per licensed age group, actual arrival and departure time for each child (or "absent"), accessible on the premises at all times — including offline on a phone during an evacuation or field trip, which the manual specifically flags. Room moves preserve history.
- **Daily written record that fills itself.** The regulation requires a dated entry every single day, even if nothing happened. Tucked drafts the entry from the day's logs, and forces a one-line confirmation before closing the day ("uneventful" is a valid answer). Accidents, incidents, fire drills and self-administered medication get cross-referenced automatically because the manual says they must be.
- **Accident and incident reports with proof of delivery.** The inspector wants evidence the parent received a copy — a signature or email verification. Tucked records the parent's in-app acknowledgement with a timestamp. Head-bump reports get a mandatory concussion-watch note.
- **Serious-occurrence helper.** The 24-hour reporting clock, the anonymised summary that must be posted for 10 business days, and the "update if new information arrives" rule — all as a guided flow. (The actual report is still filed by the licensee in the ministry's CCLS system; Tucked prepares it, tracks the deadline and the posting window.)
- **Sleep checks for under-24-month rooms.** Timed direct-visual-check prompts, logged per child, with a printable sheet. Electronic monitors don't count as a substitute — the app should say so.
- **Medication log that matches the rule.** Written parent authorisation with a schedule and dose (or explicit "as needed" symptoms), original-container labelling checklist, one designated staff member, every administration logged — *including* blanket-authorised items like sunscreen and diaper cream, because the manual requires those logged too.
- **Individualised plans and allergy list.** Anaphylaxis plans, medical-needs plans, and the allergy list that must be posted around the centre, kept current in one place.
- **Consent that respects section 73.** A parent cannot be required to consent to release of information as a condition of enrolment. Tucked separates "required for care" from "optional" (photos to third parties, social media) and never blocks enrolment on the optional set.
- **Three-year retention after discharge, and a clean export** for the ministry, the medical officer of health, or a parent asking for their child's record.
- **Live ratios per room** against Ontario's ratio and group-size rules, shown on the supervisor's home screen.
- **AQI-ready documentation** for centres with City of Toronto service agreements — observations tagged to programming areas, so the self-evaluation isn't a scramble.

### For both — "Canadian"
- Data hosted in Canada. Not legally required for private centres under PIPEDA, but it is what directors ask about, and it's a line the American incumbents can't say.
- Published CAD pricing, no per-staff fee, no setup fee.
- Support from a human within the same business day (this is a sales promise you can actually keep at small scale).

---

## 6. Compliance: what the app must respect (Ontario)

Plain-English version of the rules that shape the product. The legal texts are the Child Care and Early Years Act, 2014 and Ontario Regulation 137/15; the Ministry's Child Care Centre Licensing Manual is the readable guide.

**Records the inspector will ask to see (and the app must produce instantly):**
- Children's records with the full set of enrolment information, immunisation proof or the official exemption forms, parent-signed medication instructions, individualised plans.
- Daily attendance per licensed age group with actual times.
- The daily written record — every operating day.
- Accident reports, with evidence parents got a copy.
- Serious occurrence policy and the record of reports made within 24 hours.
- Sleep supervision policy and documented direct visual checks.
- Medication administration procedure and log.
- Anaphylaxis policy and individualised plans.
- Evidence of daily health observation at arrival, including anything the parent reported at drop-off ("restless night").

**Rules that shape design:**
- Records may be kept electronically, but must be accessible to staff and ministry officials at all times; if password-protected, staff on shift must be able to get in. → Offline access on the centre's tablet/phone; a "duty supervisor" access mode; never a screen that says "contact your admin to unlock attendance."
- Retain children's records (including attendance and plans) for 3 years after the child leaves; financial records 6 years.
- The medical officer of health can inspect and request copies of parts of a child's record. → Export per child, per section.
- Parents have a right of access to their child's record. → The household view is the parent's copy, not a marketing feed.
- Licensees are told to collect the minimum information needed, to seek informed consent before sharing photos with third parties or social media, and to never make consent a condition of enrolment.
- Waitlists cannot charge fees; the waitlist policy must be in the parent handbook. → If you build a waitlist, it's free, and it shows the family their position without exposing other families.

**Privacy law:**
- Ontario has no private-sector privacy statute; federal PIPEDA applies to commercial activity, built on meaningful consent and limited collection. Municipal centres fall under MFIPPA (another reason to skip City-run centres early).
- No general data-residency requirement for private centres, but hosting in Canada removes a question every director will ask, and public bodies in some provinces do require it.
- Photos of children are personal information. No advertising SDKs, no analytics that touch photos, no facial recognition.
- Write the privacy policy so a director can attach it to her parent handbook. That's a feature.

**Toronto-specific:**
- Centres with a City service agreement (fee-subsidy) are assessed on the AQI, a 1–5 scale with a minimum of 3 required, results posted publicly. Documentation that supports programming and observations helps them; sell to that anxiety gently.
- Toronto Public Health inspects and runs outbreak management — contact tracing is one of the stated reasons attendance records exist. Make the "who was in the room with whom, when" export trivial.

---

## 7. The provinces around Ontario

Ontario borders Quebec and Manitoba. Here is what changes.

**Manitoba — go second.**
- $10/day flat fee already in place; most funded centres are non-profit or co-op (operating grants require it).
- Requires daily attendance with arrival and departure times, kept for two years — simpler than Ontario.
- Winnipeg is a compact, relationship-driven market; the Manitoba Child Care Association is the channel.
- Product change: a province preset (attendance retention, forms, terminology). Small.

**Quebec — go last, and only deliberately.**
- A different world: the CPE network, a set fee of $9.65/day, and provincial governance that predates CWELCC.
- Law 25 is the strictest privacy law in Canada — GDPR-like rights, a privacy impact assessment before data leaves Quebec, and a private right of action (people can sue). Bilingual privacy policies and French-first service are legally expected, not nice-to-have.
- Product change: full French interface for parents *and* staff, French daily stories, Quebec hosting decisions, and new forms. This is months of work, not a preset.

**Rest of Ontario before either** — Ottawa, Hamilton, Mississauga/Brampton, Kitchener-Waterloo, London. Same rules, same inspectors, same product. Expand within Ontario until you run out of warm referrals.

---

## 8. What to build, in what order

Think in "moments of success" (the same IKEA-effect logic as Unifloe): each phase should end with a moment where the director or a parent feels *relief*.

### Phase 1 — The record-keeping core (pilot with 2–3 centres)
- Household-based enrolment (parent completes the child's record from an invite; centre verifies).
- Sign-in/out with real times, per room, offline-capable, room-move-safe.
- Daily logs (meals, naps with sleep checks, diapers/toileting, activities, mood) with one-tap and per-room bulk entry.
- Daily written record drafted from logs, closed daily.
- Accident/incident reports with parent acknowledgement.
- Medication authorisation and administration log.
- The calm daily story for parents; the "Now/Later" split; photos with dates and full-size download.
- Messaging with a visible recipient.
- Ratio display for the supervisor.

*Moment of success:* the first licensing visit where the director pulls up everything the program advisor asks for in under a minute.

### Phase 2 — The things that make switching worth it
- Serious-occurrence helper; immunisation and exemption tracking; individualised plans; allergy list; sleep policy sheets.
- Invoicing with e-Transfer reconciliation and pre-authorized debit; CWELCC-friendly attendance and fee summaries for the centre's funding reporting.
- Learning stories/observations tagged to programming areas (AQI-friendly), flowing into the child's record and the parent's feed.
- Graduation export for families.

*Moment of success:* a parent's "we're moving centres — can we keep our photos?" answered with yes.

### Phase 3 — Home child care agencies
- Agency → home visitor → provider → parent structure; per-home attendance and daily records; visitor inspection checklists; agency-level oversight.

*Moment of success:* one agency contract that lights up dozens of homes.

**What not to build early:** tuition automation, staff payroll, curriculum marketplaces, live classroom cameras (a real trend, and a privacy and anxiety problem — let others do it), anything US-subsidy-shaped.

---

## 9. Pricing

**Principle:** publish it, keep it flat, price per child, no per-staff fee, no setup fee, free for parents including payments.

- **Centre:** a flat monthly price per enrolled child in CAD, in the same band the incumbents reportedly land in but *visible on the website*, with a small-centre minimum. Annual pre-pay discount for non-profits.
- **Home child care agency:** per active home per month.
- **Pilot offer:** free until the first licensing visit, then half price for the first year in exchange for two referrals and permission to name them.

**Why per child and not per room/site:** matches how directors think, matches CWELCC's per-child funding logic, and scales gently for the 30-child centre that will be your first customer.

**Why not free-forever:** non-profits distrust free (they've been burned by "free until we add fees"). A modest, published price signals you'll still exist next year.

---

## 10. Go-to-market (adapted from what worked in Bengaluru)

**People on the ground.** Your University of Toronto friend is the equivalent of you walking into schools on Fridays. The "student asking for advice" tone works even better in Canada — directors in this sector are generous with time for students. Their job for the first 60 days is discovery, not selling.

**Referral-first.** Toronto's centre community is tight — supervisors know each other through the Association of Early Childhood Educators Ontario (AECEO), the Ontario Coalition for Better Child Care, City of Toronto partner sessions, and RECE Facebook groups. One happy supervisor is worth twenty cold emails.

**Cluster walk-ins.** Same neighbourhood clustering as Bengaluru. Start where the density is: downtown/mid-town has the most centres; the CCPA report says the under-served areas (northwest and south Etobicoke, central/south Scarborough) are where new rooms are opening — new rooms mean new record-keeping pain.

**Timing.** September is intake chaos — don't launch then; be in discovery conversations in September–October, pilot in January (calmer), sign real contracts in April–May before the next September.

**The decision-maker check** (your Bengaluru lesson, ported): the supervisor is usually the decision-maker for an independent centre; for a non-profit, the board approves spending above a threshold — ask early. Verify at the front desk, every time.

**The three-line pitch to a supervisor:**
> "We're a small Canadian-hosted app built around the CCEYA record rules. Parents get one calm summary a day instead of forty pings. When the program advisor visits, everything's one tap away."

**Objection you will hear most:** "We're on Lillio/Brightwheel already." Answer with the three things they can't say — calm default, inspection mode, Canadian hosting — and a one-week parallel run, not a migration.

---

## 11. Honest risks and pushback

1. **Two products, one founder.** Unifloe has two paying schools, a pending third, a 1 GB server, and a PLG wizard still landing. A second product now will slow both. Recommendation: do 20 discovery calls through your friend this autumn, write nothing but notes, and only start building after Unifloe's pilot cohort is on the credit-funded infrastructure and stable.
2. **Lillio is at home.** They know Ontario, they know CWELCC, they have thousands of Ontario centres. Don't out-feature them. Out-focus them on the two sentences above.
3. **Parents expect an app-store app.** In Toronto, a "website you add to your home screen" reads as unfinished, and reliable alerts on iPhones are the whole point of the "Now" channel. Budget for real iOS and Android apps for parents from day one, even if staff use the web version.
4. **The staffing crisis cuts both ways.** Directors are exhausted and wary of new tools; but the same exhaustion makes "less typing, fewer inspection headaches" land. Your onboarding must be under an hour and require nothing from the director between drop-off and nap.
5. **Time zone and trust.** A director in Toronto with a problem at 8 a.m. is calling Bengaluru at 5:30 p.m. Fine — but say so explicitly in your support promise and keep it.
6. **Privacy is a reputation game.** One story about a Canadian daycare app mishandling children's photos ends the company. Canadian hosting, minimal collection, no third-party trackers, and a plain-English policy are not compliance chores; they are the brand.
7. **Payments.** Building Interac and pre-authorized debit properly requires a Canadian payment partner and likely a Canadian entity or bank relationship. Decide early whether PaperKite needs a Canadian company; your friend's involvement may make that natural.

---

## 12. The name — Tucked (confirmed 29 Aug 2026 after three rounds of checks)

**Tucked** — as in tucked in, looked after, everything in one place.

**What the checks found (Canadian Trademarks Database, exact and sound-alike spellings):**
- No live "TUCKED" mark in any class. The only record is a dead 2001 Avon application for "TUCKED IN" (cosmetics), withdrawn. Tuckd / Tukd / Tuckt / Tucked-In / Tuckin: nothing live.
- **Neighbours to know about:** (1) **TUCK** — Tuck Bedding Inc., 18 McMaster Ave, Toronto, filed Nov 2024 for bedding incl. crib sheets and children's towels (classes 24, 35): a Toronto baby-adjacent brand, different class; (2) **TUCK-INS BY YOU** — Hatch Baby Inc. (the baby sleep-machine company), filed Sept 2024 in class 9 for an app that records a parent's voice for bedtime: same broad class as a downloadable app, different purpose; (3) Tuck & Design (pet products, Vancouver) and Tummy Tuck (fitness DVDs) — irrelevant.
- **Domains:** tucked.ca, gettucked.ca and tucked.care available; tucked.com listed for sale on GoDaddy; tucked.app is an empty placeholder (registered).
- **Web and app stores:** no product called "Tucked." Nearest: "tuck" (a UK cashback app), TapTuck (South African school tuck-shop payments), Tucked Trunks (underwear).

**How to file it:** register in Class 42 (software as a service for licensed child care centres: attendance, daily records, family communication) and Class 9 (downloadable app for the same), with that narrow wording. Ask a trademark agent for a 30-minute opinion specifically on Hatch's "Tuck-Ins By You" before spending on brand assets — it is the one neighbour that could draw an examiner's citation. Register tucked.ca and gettucked.ca now; make an offer on tucked.com only if the price is trivial.

**Runners-up kept on file:** Cosset (cleanest of all, but a less familiar word) and Blanket Fort (warmest imagery, two words, US "Blanket" software neighbour).

**Rejected on evidence across the three rounds:** Mitten (live BC childcare app), Parka (Parks Canada official mark + Ontario software trademark), Rainboot (fine legally, didn't sound right), Snuggery, Lovey, Nestled, Toasty, Blankie, Cardigan, Kindnest, Bundle Up, Hushabye, Snowsuit, Cozie, Coddle, Snuggle/Snuggly, Cubby, and the crowded set (Hearth, Fireside, Kindred, Cozy, Teddy, Cocoa, Cabin, Kettle, Pillow, Blanket, Den, Huddle, Swaddle, Quilt, Hygge, Homey, Toque, Tuck, Puddle, Nook, Sprout, Willow, Birch, Pebble, Loon, Boreal, Trillium).

---

## 13. Next 30 days

- [ ] Brief your U of T friend with Sections 2, 4 and 10; agree on the "student asking for advice" script.
- [ ] Build a 40-centre Toronto discovery list (independent, single-site, infant/toddler rooms) using the City's child care locator and the same verification habit you use in Bengaluru.
- [ ] 20 discovery conversations: what app they use, what the last licensing visit asked for, what parents complain about, what they pay. No pitching.
- [ ] Spend one evening in r/ECEProfessionals, r/daycare, r/askTO and two Toronto parent groups; add anything new to Section 4.
- [ ] Read the Licensing Manual Parts 3, 5, 7, 10 and 11 once, end to end (they're readable).
- [ ] CIPO trademark search (exact + phonetic) for Tucked; register getparka.ca, getparka.app, parka.care.
- [ ] Decide the Canadian-entity question with your friend.
- [ ] Do *not* start building until Unifloe's pilots are stable and the discovery notes say the same three things twenty times.

---

## Sources consulted

- City of Toronto — Child Care Services overview; Quality Ratings / AQI pages; Early Years and Child Care Service Plan 2025–2030 (space counts).
- Toronto Workforce Innovation Group — Child Care Industry Statistics (operator mix).
- Government of Ontario — Ontario's Early Years and Child Care Annual Report 2025; Child Care Centre Licensing Manual (Parts 5 and 11); CWELCC agreement page.
- Halton Region and York Region CWELCC pages (fee caps, funding extension, cost-based funding).
- Canadian Centre for Policy Alternatives — "Still building: child care availability in Toronto since 2022."
- Statistics Canada — Child care providers 2024 (capacity), Child care arrangements 2025.
- Government of Manitoba — Licensing Manual for Early Learning and Child Care Centres; Child Care Regulation.
- Childcare Resource and Research Unit — "The $10-a-day divide: child care fees in Canada in 2026."
- Privacy overviews of PIPEDA / Quebec Law 25 (Concentric, DLA Piper, Recording Law, Vucense guides).
- Competitor reviews: Capterra (Lillio, Brightwheel, Tadpoles), Trustpilot (Brightwheel), SoftwareAdvice (Brightwheel); Procare and Brightwheel comparison blogs; pricing guides from MyKidReports, ARDN, Bloomily, Illumine (treat all pricing figures as reported, not verified).
- MaRS Discovery District interview with the HiMama/Lillio CEO (Toronto origin).
- Parent essays on notification overload (Purdue Consumer Corner; The Connected Family newsletter comments).

---

## 14. How it gets built (added 29 Aug 2026)

Three companion documents now sit beside this plan:

- **`tucked-ontario-requirements.md`** — every record, rule and "never do" from O. Reg. 137/15 and the Licensing Manual, written as product requirements. This is the spec.
- **`tucked-competitor-matrix.md`** — feature-by-feature and pricing comparison against Brightwheel, Procare, Lillio, Playground, Storypark, Mitten.care and the long tail, with the "build / parity / skip" call for each row.
- **`tucked-build-prompt.md`** — the single-file master Claude Code prompt: stack, product principles, domain model, module map, Now/Later notifications, offline rules, phases with "done when" criteria, the full Ontario compliance specification embedded, competitive build/parity/skip decisions, and quality gates. Nothing else needs attaching.

**The technical decision, in plain words:** parents will open this several times a day and depend on the urgent-alert channel, so it must be a real App Store / Play Store app, not a website saved to the home screen. The easiest honest way to get there as a solo founder is **Expo** (React Native) — you keep React and TypeScript, the iPhone build happens in Expo's cloud so you don't need a Mac, and bug fixes ship without waiting for Apple's review. The supervisor's console stays a normal website. Data lives in **Supabase's Canada (Central) region** — a managed Postgres with login, file storage and per-centre isolation built in — so "your children's data stays in Canada" is true from the first day and you don't rebuild the auth and file plumbing you already wrote once for Unifloe. Capacitor (wrapping a website in an app shell) was considered and rejected: it feels like a website, iPhone builds need a Mac or paid CI, and Apple sometimes rejects thin wrappers.

**Costs to expect:** Apple Developer Program US$99/yr; Google Play US$25 once; Supabase Pro ~US$25/mo plus usage; Expo EAS free tier to start; Stripe per-transaction fees when billing goes live (absorbed by the centre's plan, never charged to parents).

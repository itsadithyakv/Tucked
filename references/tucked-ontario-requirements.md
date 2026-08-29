# Tucked — Ontario compatibility requirements

*What the app must record, show, and never do, so a licensed Ontario centre can run on it and pass a licensing visit. Written from the Child Care and Early Years Act, 2014 (CCEYA), Ontario Regulation 137/15, and the Ministry's Child Care Centre Licensing Manual (2025). Section numbers refer to O. Reg. 137/15. This is a product document, not legal advice — have a Toronto supervisor and, before launch, a lawyer read it.*

---

## 0. Words the app must use

| Use this | Not this | Why |
|---|---|---|
| **Licensee** | owner, company | the legal holder of the licence |
| **Supervisor** | director, principal | Ontario's title for the person in charge of a centre |
| **RECE** | teacher, ECE | Registered Early Childhood Educator, a College member |
| **Program advisor** | inspector | the Ministry official who inspects and licenses |
| **CCLS** | — | Child Care Licensing System, where serious occurrences and the annual survey are filed |
| **Age group** / **licensed age group** | class, room | the licence is issued per age group |
| **Parent** | guardian | the regulation says parent; it includes guardians |
| **Children's record** | file, profile | the regulated term (s. 72) |
| **Daily written record** | daily log, diary | the regulated term (s. 37) |
| **Serious occurrence** | incident | a defined, reportable category (s. 38) |

**Licensed age groups (Schedule 1)** — these are the room presets:

| Age group | Age range | Staff : children | Max group | Qualified staff |
|---|---|---|---|---|
| Infant | under 18 months | 3 : 10 | 10 | 1 in 3 |
| Toddler | 18 – 30 months | 1 : 5 | 15 | 1 in 3 |
| Preschool | 30 months – 6 years | 1 : 8 | 24 | 2 in 3 (17+ children ⇒ at least 2 qualified) |
| Kindergarten | 44 months – 7 years | 1 : 13 | 26 | 1 in 2 |
| Primary/junior school age | 68 months – 13 years | 1 : 15 | 30 | 1 in 2 |
| Junior school age | 9 – 13 years | 1 : 20 | 20 | 1 in 1 |
| Family age group | 0 – 13 years | 1 : 8 | 16 | — (max 6 under 24 months) |

---

## 1. Children's records (s. 72) — the enrolment form *is* the compliance record

Every child needs an up-to-date record available for inspection at all times containing, verbatim from s. 72(1):

1. A signed application for enrolment.
2. Name, date of birth, home address.
3. Parents' names, home addresses, telephone numbers.
4. Emergency address and phone during care hours (parent or other person).
5. **Names of persons to whom the child may be released.**
6. Date of admission.
7. Date of discharge.
8. Previous communicable diseases, conditions needing medical attention, and — for children not yet in school — immunisation, or the official exemption form (medical exemption signed by a doctor/NP; conscience/religious exemption notarised).
9. Symptoms indicative of ill health (an ongoing log, not a one-time field).
10. Signed parent instructions for any medical treatment, drug or medication to be given during care.
11. Signed parent instructions on special diet, rest, or physical activity.

Plus: any individualised plan (anaphylaxis, medical needs, special needs); written permission if a child may leave unsupervised at a set time (s. 50); custody orders and pickup restrictions (these live under item 5 in practice).

**Product rules**
- Missing information must be recorded as "not applicable" or "parent did not wish to provide" — never a blank. The inspector wants to see the attempt.
- Kept **on the premises** of the centre (a Canadian-hosted app with offline access satisfies this; see §12). Electronic is explicitly allowed (s. 82(2)) *if* staff and Ministry officials can always get in — no "ask your admin to unlock."
- **Retain 3 years after discharge** (s. 72(5)). Financial records 6 years (O. Reg. 138/15 s. 27.1). Nothing hard-deletes before then; discharge starts a retention clock, not a purge.
- The **medical officer of health** may inspect and take copies of items 2, 3, 8 and 9 (s. 72(6)). Per-child export of exactly those sections.
- **Parents may not be required to consent to release of information as a condition of enrolment (s. 73).** Enrolment must complete with every optional consent declined.
- Parents have access to their child's record; the household view is the parent's copy.

---

## 2. Attendance (s. 72(3)) and safe arrival & dismissal (s. 50)

**Attendance record must show, per licensed age group, for every day:** each child present, actual time of arrival, actual time of departure, or "absent." Admin penalty for a missing record: $750, escalating.

**Why it exists (and therefore what it must support):** every child accounted for at any moment; proof licensed capacity isn't exceeded; public-health contact tracing; evacuation headcount; missing-child response.

**Product rules**
- Times are captured when the event happens, not typed later. Late corrections carry who/when/why.
- A child moving between age groups keeps one continuous history.
- Sign-out only when the child has actually left the centre's care (picked up, or left for school). "On the way" is not a sign-out.
- **Offline on the room device.** The manual specifically requires that a phone used for attendance still works off-site during an evacuation or field trip. Evacuation mode: the day's attendance list, emergency contacts, and medication/allergy list on one screen, no network needed.
- **Safe arrival:** if a child is expected and hasn't arrived by the centre's cut-off, the app prompts staff to contact the parent and records the attempt and outcome. **Safe dismissal:** release only to persons on the child's authorised list, with identity confirmation recorded; late pickup and "no authorised person available" flows follow the centre's written policy, which must be in the parent handbook.
- Custody orders: a restricted person is a hard block with an explanation visible to staff and never to the restricted person.
- Public-health export: who was in which room, with whom, on which dates, with symptom onset where logged.

---

## 3. Ratios and group size (ss. 8–11, Schedule 1)

- Live per-room count of children present vs staff counted in ratio, against the room's age group.
- **Reduced ratios** are allowed only for programs of 6+ hours during arrival (first 90 min), departure (last 60 min), and rest (up to 2 h); never below two-thirds of the ratio; **never for infants; never outdoors.** Reduced-period ratio floors: toddler 1:8, preschool 1:12, kindergarten 1:20, primary/junior 1:23. For programs under 6 hours: 30-minute windows.
- The supervisor's time in ratio is limited; **resource consultants, volunteers and students are never counted.**
- Where 6+ children are in attendance, at least 2 staff. Adult supervision at all times (s. 11).
- Mixed-age approvals are director-issued exceptions; the app models them as a per-room setting with the 20%/25% caps, not as a default.
- Off-site (field trips) ratios still apply — the room device must show ratio away from the building.

---

## 4. Daily health observation, illness, and communicable disease (ss. 32, 36)

- Staff observe each child on arrival **before** they join others. Symptoms — and anything the parent reports at drop-off ("restless night," "off her food") — are recorded in the child's record and the daily written record.
- Sick child: separated, parent contacted, taken home; if not possible and urgent, seen by a doctor or RN. Record all of it.
- Exclusion and return: follow the centre's illness policy (developed with the local public health unit). Record the reason, the date, and the return criteria.
- Communicable disease exposure: notify the public health unit; keep any orders/directions on file; send orders to the program advisor within 2 business days; enforcement action notified within 1 business day.
- Ministry, public health and fire inspection reports must be kept on the premises.

---

## 5. Accidents, the daily written record, and serious occurrences (ss. 36(4), 37, 38)

**Accident report** (a child is injured): child's name, who completed it, date/time, location, what happened, the injury and its severity, first aid given, how and when the copy was given to the parent. **There must be evidence the parent received a copy** — an in-app acknowledgement with a timestamp counts as "email verification." Any hard hit to the head is recorded as an accident even without symptoms.

**Daily written record**: a dated entry **every operating day, no exceptions**, even "uneventful." Must summarise any incident affecting the health, safety or well-being of a child *or staff member*, every fire drill, every accident ("see child's file"), every serious occurrence, and every self-administered medication. May be one per centre or one per room; if per room, each room must complete it daily.

**Serious occurrence** (death, serious injury, abuse/neglect allegation, missing child, unplanned disruption, etc. — the CCLS list is longer than the regulation's):
- Report to the Ministry through **CCLS within 24 hours** of the licensee or supervisor becoming aware; if CCLS is down, phone/email the program advisor within 24 hours and file when it's back. Penalty for late reporting: $2,000, escalating.
- Post an **anonymised summary** in a conspicuous place for **10 business days** (weekends and statutory holidays don't count); update it if new information arrives.
- Any suspicion of abuse or neglect also triggers a duty to report to the Children's Aid Society under the CYFSA (individual fine up to $5,000 for not reporting).

**Product rules**: the app never files to CCLS itself; it drafts, times, reminds, and records what was filed and when. Accidents auto-cross-reference into the daily written record. The daily record cannot be "closed" without a human confirmation.

---

## 6. Sleep (s. 33.1)

- Children under 12 months are placed on their backs for sleep unless a physician's note says otherwise (applies wherever the child is, including a toddler or family room).
- **Direct visual checks** of every sleeping child under 24 months in infant, toddler or family groups, by physically going to the child, at the frequency set in the centre's sleep policy; **documented**. Electronic monitors, if used, must be checked daily and **never replace** direct checks.
- Sufficient light in sleep rooms; a system to know immediately which children are in the sleep area.
- Toddler and preschool rest periods: **no longer than 2 hours**; children may sleep, rest, or do quiet activities according to need.

**Product rules**: sleep-check prompts on the room device at the policy interval; per-child timestamped checks; nap start/end; a printable sleep-check sheet; rest-period length warnings.

---

## 7. Anaphylaxis, medical needs, special needs, medication (ss. 39, 39.1, 40, 52)

- **Anaphylaxis policy** required even if no child currently has an allergy. Each anaphylactic child has an **individualised plan** with emergency procedures, developed with the parent.
- **Allergy and food-restriction list posted** in every cooking/serving area and every play room (s. 43(3)).
- **Children with medical needs**: individualised plan covering exposure reduction, devices and instructions, emergency procedure, supports, and evacuation/field-trip procedures; developed with the parent and any regulated health professional; sensitive diagnoses kept confidential unless the parent consents in writing.
- **Children with special needs (s. 52)**: individualised support plan with the parent, the child where appropriate, and professionals; parental agreement (preferably written) before implementing or involving outside professionals.
- **Medication (s. 40)** — only if the licensee chooses to administer it, and then: written procedure; one designated person (or designate) in charge; parent's written authorisation with a **schedule or specific symptoms** and **dose** ("as needed" alone is not enough); original container labelled with child's name, drug, dosage, purchase and expiry dates, storage and administration instructions; locked and inaccessible to children (except self-carried asthma/epinephrine with written permission); **every administration logged — including blanket-authorised items** (sunscreen, moisturiser, lip balm, insect repellent, hand sanitiser, diaper cream); parent instructions must match the label or a doctor's note resolves the difference; expired medication flagged to the parent; accidental administration recorded and escalated. Penalty for breaches: $2,000, escalating.
- **Immunisation (s. 35)**: children not in school must be immunised per the local medical officer of health, or hold one of the two standard exemption forms; school-age children note "attends school" instead.

---

## 8. Nutrition (Part 6, ss. 42–44)

- Menus for the **current and following week** planned, **posted** where parents can see them, **substitutions noted at the time**, and posted menus **kept for 30 days**.
- Meals provided for children under 44 months at each meal time during program hours; at least **two snacks** when in care 6+ hours.
- Infants under 1 fed **per the parent's written instructions**; special dietary arrangements carried out per written instructions (s. 44).
- Food or drink from home labelled with the child's name.

**Product rules**: menu module with posting date, substitution log, 30-day retention; infant feeding instructions on the child's record and visible in the infant room; quantity-eaten logs feed the parent's daily story.

---

## 9. Program (Part 7, ss. 45–52)

- **Program statement** referencing *How Does Learning Happen?* (HDLH) — Ontario's pedagogy — with goals and approaches; reviewed annually; staff implement it; prohibited practices listed; a policy for parent issues and concerns with response timelines.
- **Outdoor play**: at least **2 hours a day** (weather permitting) for programs of 6+ hours; **30 minutes** for before/after-school; a child kept indoors needs written instruction from a physician or parent on file.
- Infants and toddlers separated from older children during active play.
- **Parent handbook (s. 45)** must include: services and age groups; hours and holidays; **base fee and non-base fees**; **whether the licensee is enrolled in CWELCC**; admission and discharge policy; off-premises activities; volunteer/student supervision policy; payment methods and schedule; refund circumstances; safe arrival and dismissal policy; waiting-list policy; anaphylaxis policy; parent issues and concerns policy; program statement.
- **Waiting lists (s. 75.1)**: no fee or deposit to be placed on a list; policy explains admission order and how a family learns its position without exposing others.

**Product rules**: a handbook builder that assembles these sections from settings, versions them, and records parent acknowledgement; outdoor-time log with weather reason; HDLH-tagged learning stories; free waitlist with self-serve position.

---

## 10. Staff files (Parts 8–9, ss. 53–64)

For every employee, and for volunteers and students where noted, the licensee must be able to show:
- **RECE status** on the College's public register (supervisor; the qualified staff per age group).
- **Standard first aid incl. infant/child CPR** (WSIB-approved course) for the supervisor and every staff member who may be counted in ratio; valid dates.
- **Health assessment and immunisation** records (or the objection form) for staff, volunteers, placement students.
- **Vulnerable sector check**: obtained before starting (or documented as required "as soon as possible" if started first), conducted by a police service, no more than 6 months old when obtained, **renewed on or before the 5th anniversary**, and refreshed after a break of 6+ months. **Offence declaration** every year a VSC isn't obtained. 18-year-olds: YCJA statement; 19+: VSC.
- Police record check policy; staff training and development policy; volunteer/student supervision policy (never counted in ratio, never alone with children).
- Employer duty to report certain RECE matters to the College.

**Product rules**: a credential and expiry ledger per person with due-date reminders, evidence uploads, and an inspection-ready "staff file" view. This is the free wedge product in the plan.

---

## 11. Emergency preparedness and premises (Parts 4 and 10)

- Working phone accessible at all times; emergency contact list (incl. poison control where no 911).
- **Fire procedure approved by the local fire chief**, posted in every room; **fire drills** (monthly once staff are practised), alarm and equipment tests — all with **written records**.
- **Emergency management policy** (or the Ministry's standard one; or the school's, if in a school) covering lockdown, hold-and-secure, evacuation, shelter-in-place; debrief with staff, and children where appropriate, after an emergency.
- **Emergency records readily accessible for every child**: at least one parent phone number and an alternate contact.
- **Playground**: a playground safety policy; daily, monthly and annual inspections (annual by a certified inspector where there are fixed structures) against CSA Z614; a repair log with hazards restricted until fixed.
- Temperature, water, hazards, first-aid kit and manual locations, animals' rabies certificates — checklist items the app can host as recurring tasks.

**Product rules**: a compliance calendar (drills, inspections, tests, renewals) with evidence attached; evacuation mode (see §2).

---

## 12. CWELCC, fees, subsidy, and Toronto (Part 2 and municipal)

- For eligible children (under 6, or turning 6 before June 30) in enrolled centres, the **base fee is capped at $22/day** (or lower where the prior fee was lower). Non-base fees are restricted. The parent handbook must state enrolment status.
- Disenrolling from CWELCC requires **30 days' written notice to every eligible child's parent and every employee** — the app should be able to prove delivery.
- Funding is cost-based and administered by the service system manager — in Toronto, **Toronto Children's Services** — which also runs fee subsidy and requires attendance and financial reporting under service agreements. Exports must match what the City asks for (confirm formats in discovery).
- **Toronto AQI**: centres with City service agreements are assessed 1–5 (minimum 3) on programming, learning environment, interactions, health and safety; results are public. Documentation that supports programming and observation helps.
- **Toronto Public Health** inspects centres, manages outbreaks, and assesses immunisation records.
- **Annual Child Care Operations Survey** in CCLS (as of December 31 each year): hours, enrolment, fees, agreements — the app should be able to produce these numbers.
- **Tax receipts**: families claim child care expenses with the CRA; the centre issues annual receipts showing the payer, the child, the amount, the period, and the provider's identity (business name and number; an individual provider's SIN). One-tap generation every February.

---

## 13. Privacy and data (federal and provincial)

- **PIPEDA** governs a private Ontario centre's commercial handling of personal information: meaningful consent, collect the minimum, purpose limitation, safeguards, access and correction rights, breach reporting where there's a real risk of significant harm. Ontario has no private-sector privacy statute; municipal centres fall under MFIPPA (out of scope for phase 1).
- The Licensing Manual itself tells licensees to have a privacy policy covering: minimum collection; the right to privacy; **parental access** to records and who else sees them; **informed consent before sharing children's information or photos with third parties or on social media**; secure storage; dated, time-limited consents for trips and events.
- **Data residency**: not legally required for private centres, but hosting in Canada removes the question every supervisor asks and is required if you ever serve a public body in BC or Nova Scotia. Tucked hosts all data and photos in Canada.
- Photos are personal information about children: consent per child and per purpose; a child without group-photo consent is excluded or obscured automatically; no advertising SDKs, no third-party analytics touching content, no facial recognition, no live streaming.
- **Quebec later**: Law 25 adds GDPR-style rights, a privacy impact assessment before data leaves Quebec, a private right of action, and French-first obligations. Design the data model so a province preset can turn these on.

---

## 14. Things Tucked must *never* do

- Let a required record be deleted, hidden, or locked away by a module being switched off, a subscription lapsing, or an admin password being lost.
- Treat a photo or update as delivered without evidence when the regulation asks for evidence (accident reports, CWELCC notices).
- Count a volunteer, student, resource consultant or off-shift supervisor in a ratio.
- Sign a child out on a parent's "on my way."
- Allow enrolment to be blocked on an optional consent.
- Substitute a monitor, a camera, or an AI summary for a direct visual sleep check or a human-confirmed daily written record.
- File anything to CCLS, the City, the College, or the CRA on the centre's behalf without a named human pressing the button.

---

## Sources
Ontario Regulation 137/15 (General) under the CCEYA, 2014 — ss. 8–11, 32–40, 42–52, 53–64, 68.1, 72–73, 75.1, 77.2, 82, Schedule 1. Child Care Centre Licensing Manual (Ontario Ministry of Education, 2025) — Parts 2–11 and Appendix A. City of Toronto — Children's Services, AQI, Toronto Public Health. Office of the Privacy Commissioner of Canada — PIPEDA. Canada Revenue Agency — child care expenses receipts.

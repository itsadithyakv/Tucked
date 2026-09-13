# 03 — Features: records and standing obligations

*Everything that must be **on file** rather than everything that happens today. Same shape as [02](02-features-daily-care.md): the regulation, what Tucked does, **every case including the refusals**, where it lives, and where it is weak.*

A theme runs through this file and is worth stating once: **rule packs are jurisdiction data, not code.** Handbook sections, staff requirements, policy specs, outdoor minutes, CWELCC parameters, centre-document kinds and statutory holidays are all rows keyed by `jurisdiction_code`. Adding Manitoba is largely rows plus a requirements document — not a fork.

---

## Contents

1. [Children's records (s. 72(1))](#1-childrens-records-s-721)
2. [Consent (s. 73)](#2-consent-s-73)
3. [Immunisation (s. 35)](#3-immunisation-s-35)
4. [Individualised plans and the allergy list (ss. 39, 39.1, 52, 43(3))](#4-individualised-plans-and-the-allergy-list-ss-39-391-52-433)
5. [Families and households](#5-families-and-households)
6. [Staff files (ss. 53–64)](#6-staff-files-ss-5364)
7. [Policies and the record that staff read them (ss. 46, 48)](#7-policies-and-the-record-that-staff-read-them-ss-46-48)
8. [The parent handbook (s. 45)](#8-the-parent-handbook-s-45)
9. [The waiting list (s. 75.1)](#9-the-waiting-list-s-751)
10. [Fees, the CWELCC cap and CRA receipts](#10-fees-the-cwelcc-cap-and-cra-receipts)
11. [Documents on the premises](#11-documents-on-the-premises)
12. [The compliance calendar (Parts 4 and 10)](#12-the-compliance-calendar-parts-4-and-10)
13. [Retention and anonymisation (s. 72(5))](#13-retention-and-anonymisation-s-725)

---

## 1. Children's records (s. 72(1))

### What the regulation demands

Eleven specific items on file for every enrolled child.

### What Tucked does

Every item is a **typed row** whose status is `provided`, `not_applicable`, or `parent_declined` — **never blank**. `missing` is the initial state and is what the console counts.

| # | `record_item_type` | The item |
|---|---|---|
| 1 | `application` | Signed application for enrolment |
| 2 | `identity` | Name, date of birth, home address |
| 3 | `parent_contacts` | Parents' names, addresses, phone numbers |
| 4 | `emergency_contact` | Emergency address and phone during care hours |
| 5 | `release_persons` | Persons the child may be released to |
| 6 | `admission` | Date of admission |
| 7 | `discharge` | Date of discharge (n/a while enrolled) |
| 8 | `health_immunisation` | Health history, conditions, allergies; immunisation or exemption |
| 9 | `symptoms_log` | Ongoing ill-health symptoms log |
| 10 | `medication_instructions` | Signed instructions for medication |
| 11 | `care_instructions` | Signed diet / rest / activity instructions |

`app.ensure_record_items(centre, child)` creates all eleven at `missing` the moment a child is enrolled, so the gap is visible from day one rather than discovered at inspection.

Two completion paths: a **parent** completes their own items through the enrolment flow in the app (`complete_record_item`), or **staff** record them (`staff_record_item`) when a family hands in paper. A supervisor **verifies** the record (`verify_child_record`).

`enrolment_complete` is true when every item has a non-missing status **and** the `care_required` consent is granted.

### Every case

| Situation | What happens |
|---|---|
| Child enrolled | Eleven rows created at `missing` |
| Parent completes an item | Status set; the parent is named |
| Item completed with no status | `an item is completed as provided, not applicable, or parent declined — never blank` |
| A non-consenting household member completes an item | `only a consenting household member may complete the record` |
| Staff record a paper submission | `staff_record_item` — same status rules |
| Supervisor verifies | Recorded with the supervisor named |
| A non-supervisor verifies | `verification is a supervisor action` |
| Child at another centre | `child not found` |
| Discharge item while enrolled | `not_applicable` is the correct status, not blank |

### Where this is weak

- ~~**No document attachments against a record item.**~~ **Built (migration 0042).** Every item can carry documents — the signed page, not just the word "provided". A family photographs the form from the enrolment screen (re-encoded on the phone, so no location leaves it); staff attach a PDF or image from the console child page with their PIN. A document is **replaced, never overwritten** — earlier copies are kept and say what replaced them — and **any new document re-opens that item's verification**, because a supervisor verified what was on file and this is not what was on file. An adult who can only *view* a child's day cannot add to their legal record; only the centre or an adult who may consent can. At retention the files are deleted and the rows keep no name.
- **Families can attach a photo, not a PDF, from the phone.** `expo-document-picker` is not installed, so a form a parent already has as a PDF has to be photographed or emailed to the centre.
- **The consent `purpose` was the word "enrolment" for every consent the app ever recorded.** The enrolment screen passed `p_purpose: 'enrolment'` for photos, sunscreen and data sharing alike, so the record of what a family agreed to said nothing about what they were shown. It now records the label the family actually read. Rows written before this are still "enrolment" and cannot be recovered.
- **Child profile photo upload does not exist.** Gallery photos landed in migration 0041, and the storage policy already governs `photos/{centre}/{child}/profile.jpg` (the child's own family, and only with `photo_internal`), but **no surface uploads a profile photo.** Rooms still fall back to initials.
- **The symptoms log (item 9) is satisfied by the illness module** rather than being its own artefact, which is defensible but means the item's status is a manual assertion.

---

## 2. Consent (s. 73)

### What the regulation demands

Consent is informed, purposeful, and **separable** — a family must be able to decline the optional without losing care.

### What Tucked does

One consent type is required for care (`care_required`); the other eight are genuinely optional:

`photo_internal`, `photo_group`, `photo_third_party`, `social_media`, `field_trip`, `sunscreen_blanket`, `diaper_cream_blanket`, `data_sharing_professional`

Every consent row carries a **`purpose`** — consent without a stated purpose is not consent.

**Enrolment completes with every optional consent declined.** That is a tested invariant, not a hope.

**Photo consent is enforced in the database, twice** (migration 0041). At capture, `record_photo` refuses — by name — a child without `photo_internal`, and a child without `photo_group` when a child from another household is in the picture (two siblings are not a group photo). At read, one `SECURITY DEFINER` function decides visibility for both RLS and the storage policy, so a withdrawn consent takes a photo out of other families' galleries immediately, with no cascade job to forget. **Until 0041 this paragraph claimed enforcement that did not exist:** the three photo consents were collected at enrolment and read nowhere. The other consent types (`field_trip`, `sunscreen_blanket`, …) remain records a person consults; nothing in the schema gates on them.

### Every case

| Situation | What happens |
|---|---|
| Granting or declining | Recorded with the person, the purpose and a timestamp |
| A non-consenting household member acts | `only a consenting household member may give or decline consent` |
| Revoking | `revoke_consent`; effect is immediate at query level |
| Revoking a consent that does not exist | `consent not found` |
| A non-consenting member revokes | `only a consenting household member may revoke consent` |
| All optional consents declined | **Enrolment still completes** |
| `care_required` declined | Enrolment is not complete |

### Where this is weak

- **The withdrawal cascade covers photos only.** Revoking `photo_internal` or `photo_group` hides existing photos at read time (0041). A hidden or taken-down photo is not purged: deleting a `storage.objects` row in SQL does not remove the file from the storage backend, so the bytes stay until a service-role purge exists. No other consent type cascades into anything, and there is still no access-or-deletion request workflow ([06](06-gaps-risks-and-roadmap.md)).
- **`purpose` is free text**, so two centres describe the same consent differently and nothing can compare them.

---

## 3. Immunisation (s. 35)

### What the regulation demands

A child not yet in school is immunised as directed by the local medical officer of health, **or** holds a medical exemption signed by a physician or nurse practitioner, **or** a conscience/religious exemption which **must be notarised**.

### What Tucked does

`immunisation_record` is an **append-only ledger**; `current_immunisation` is a latest-wins view. History is never rewritten — a child's status changing is a new row.

Feeds s. 72(1) item 8 and the **s. 72(6) medical-officer-of-health export**.

### Every case

| Situation | What happens |
|---|---|
| Recording an immunisation status | New ledger row; the view moves |
| Editing a past row | `immunisation records are never edited; record the new status` |
| No detail of what is on file | `say what record is on file (which schedule, to which visit)` |
| Medical exemption with no practitioner | `a medical exemption names the physician or nurse practitioner who signed it` |
| **Conscience or religious exemption without a notarisation date** | `a conscience or religious exemption must be notarised — record the notarisation date` |
| `attends_school` claimed for an infant | `"attends school" applies to school-age children — this child is under 44 months` |
| Child at another centre | `child is not enrolled at this centre` |
| Nothing on file | Console home: **Due** — "N children with no immunisation record or exemption on file (s. 35)" |

### Where this is weak

- **The exemption form itself is not stored.** As with children's records, this is a status without the scan. A notarised objection form is exactly the document an advisor wants to see.
- **No schedule modelling.** "Which schedule, to which visit" is free text; nothing knows a child is due for a booster.
- **44 months is a hard-coded school-age proxy**, not a jurisdiction row.

---

## 4. Individualised plans and the allergy list (ss. 39, 39.1, 52, 43(3))

### What the regulation demands

- **s. 39** — an anaphylaxis plan naming the allergens, the signs of a reaction and the emergency procedure.
- **s. 39.1** — a medical-needs plan with an emergency procedure.
- **s. 52** — a special-needs plan describing supports and strategies.
- All developed **with the parent** and **agreed before implementation**, and kept **up to date**: s. 52's compliance indicator asks for an "up-to-date" plan. **The regulation sets no review frequency.** The licensing manual's best practice for s. 39.1 is that the parent handbook tells families how often plans are reviewed. (Until 2026-09-13 this document said "annually reviewed". That was wrong; checked against Parts 5 and 7 of the Child Care Centre Licensing Manual.)
- **s. 43(3)** — a list of every child's allergies and food restrictions, **posted** where food is prepared and served.

### What Tucked does

`individualised_plan` is **versioned and content-immutable**. A plan is not edited; a new version supersedes it. A plan **cannot be active before a parent agreement is recorded** — that is the "agreed before implementation" rule as a constraint.

The parent agrees **in the app** (`agree_individualised_plan`), or staff record an out-of-band agreement (`record_plan_agreement`).

**Reviews (0043).** How often a plan is reviewed is the **centre's own setting**, `centre.plan_review_months` (1 to 24, default 12), edited on the Plans page. An agreement starts the clock from the centre-local day it was made; for a signed paper, that is the day it was signed, not the day it was typed in. A review is an append-only `individualised_plan_review` row on one **active** version, held with an adult who can consent for the child:

- **Still accurate** moves `review_due_on` to the review date plus the interval. No new version, no new agreement request. A backdated review never moves the clock behind a later one.
- **Changes needed** does not move the clock, and must say what changed. The plan is flagged until a new version supersedes it (which goes to the family to agree, as always), or a later review finds it accurate after all.

Staff record a review held in person, by phone or on signed paper (`record_plan_review`, PIN-signed), or ask in the app (`request_plan_review`). Each consenting adult then gets a Now alert showing the plan in full and answers **"Yes, it is still right"** or **"Something has changed"** with a note (`answer_plan_review`). The answer *is* the review: method `in_app`, named and dated. `plan_reviews_due(centre)` gives the console the list in the centre's calendar: changes waiting on a new version, overdue, and due within 30 days.

Neither the agreement button nor the review buttons appear on the family's alert until the plan itself has loaded. Before 0043 the "I agree to this plan" button rendered while the plan was still loading, so a quick tap could agree to words the parent had not been shown.

`allergy_list` is a **live view** that unions plan allergens and `dietary_restriction` rows — so the posted sheet cannot drift from the plans. A **draft** plan's allergens are already on the list (`s43_3_draft_plan_allergens_already_on_the_list`), because a child's allergy does not wait for paperwork.

Room mode caches the allergy list for the offline evacuation screen.

### Every case

| Situation | What happens |
|---|---|
| Plan with no condition or no "developed with" | `a plan names the condition and who it was developed with — never blank` |
| Anaphylaxis plan with no allergens | `an anaphylaxis plan must name its allergens` |
| Anaphylaxis plan missing signs or procedure | `an anaphylaxis plan must describe the signs of a reaction and the emergency procedure` |
| Medical plan with no emergency procedure | `a medical-needs plan must include its emergency procedure` |
| Special-needs plan with no supports | `a special-needs plan must describe the supports and strategies` |
| Activating before agreement | `a plan cannot be active before a parent agreement is recorded` |
| Editing plan content | `plan content is never edited; record a new version that supersedes this one` |
| A non-consenting adult agrees | `only a consenting household adult can agree to this plan` |
| Agreeing to a version not awaiting agreement | `this plan version is not awaiting agreement` |
| Ending a plan that is not live | `only a live plan can be ended` |
| Dietary restriction with no substance | `name the substance or restriction` |
| Ending an ended restriction | `already ended` |
| A draft anaphylaxis plan exists | Its allergens are **already on the posted list** |
| Awaiting agreement | Console home: **Due** — "N individualised plans awaiting parent agreement" |
| Signed paper dated in the future | `an agreement is recorded once it has been signed — that date is in the future` |
| Reviewing a draft | `this plan is still awaiting agreement; a plan is reviewed once it is in practice` |
| Reviewing a superseded or ended version | `this plan version is no longer in practice; review the current one` |
| Reviewing with an adult who cannot consent | `a plan is reviewed with an adult who can consent for this child` |
| A review dated in the future | `a review is recorded once it has happened; <date> is in the future` |
| A review dated before the agreement | `a review cannot come before the agreement it reviews` |
| "Changes needed" with no note (staff or family) | `say what has changed; the next version is written from it` |
| Staff recording an "in the app" review | `staff record a review held in person, by phone or on signed paper; in the app, the family answers for themselves` |
| Asking the family twice | Nobody already asked and not yet answered is asked again; the console says "Already asked" |
| Asking a family with no consenting adult | `nobody in this family can consent in the app; record a review held in person instead` |
| A view-only adult answering | `only an adult who can consent for this child can answer for the family` |
| A family answering a review nobody asked for | `the centre has not asked you to review this plan` |
| A request about a version since replaced | The family sees "nothing to review here" and an Acknowledge button |
| Editing or deleting a review | `a plan review is never edited; record another review`; deletes are append-only refusals |
| Review due within 30 days | Console home and Plans: **Due** — "review due soon" |
| Review date passed | **Due** — "past the date your review schedule set". The centre's own promise, not a regulatory breach |
| Latest review found changes | Console home: **Now** — "found out of date at review and still in practice"; Plans shows the note |
| Retention (s. 72(5)) | Review notes become `[anonymised]`; the rows that say a review happened survive |

### Where this is weak

- **Changing the interval does not re-date existing plans.** A centre moving from 12 to 6 months sees the new schedule only as each plan is next agreed or reviewed. Deliberate, since a date a family was told stays true, but a centre tightening its schedule may expect otherwise. The Plans page says so under the setting.
- **The handbook does not state the interval.** The manual suggests it should; `plan_review_months` is not yet a sourced handbook sentence the way the anaphylaxis policy is, so a handbook can still promise "every year" while the setting says six months.
- **"Changes needed" is a flag, not a message.** Nobody is notified; it waits on the console home and the Plans page.
- **A review request is never withdrawn.** If the centre supersedes the plan first, the family's alert stays until they acknowledge it.
- **The posted list is a print view**, so a centre that reprints monthly has a stale sheet on the kitchen wall and Tucked cannot know.
- **No allergen cross-check against menus** — see [02 §8](02-features-daily-care.md).

---

## 5. Families and households

### The model

A **child** belongs to one or more **households** (`child_household`) — separated parents are a first-class case, not a workaround. A household has **members** (`household_member`) with individually revocable per-person permissions:

`can_view`, `can_message`, `can_pickup`, `can_consent`, `can_bill`

**This exists because of a specific competitor failure.** A shared household login means a co-parent who should no longer have access cannot be removed without locking out the other. Here each adult has their own account and their own row, and revoking one is immediate at query level.

`can_consent` is the gate on every parental act in this document — consents, plans, medication authorisations, feeding instructions, handbook acknowledgements, sleep rest requests.

### Visibility

- Family adults can see the **workforce** of their centre by name — a parent must know which educator wrote back.
- Other **families are invisible** to them.
- Adults **within one household** see each other.
- `app.is_household_comember` and `app.is_centre_workforce` are `SECURITY DEFINER` helpers, which is what stops RLS recursing through `person` and `household_member`.

### Where this is weak

- **No household merge or split.** A family restructuring is manual row surgery.
- **RLS is not the filter on a family screen, and that rule was broken twice.** A parent who also works at the centre can read every child through their staff role. The child picker scoped correctly from the start; the family More tab did not, and until 2026-09-13 showed such a parent every excluded child in the centre as "home unwell" and every child's enrolment record. Every child-shaped query on a family screen now filters to `useFamily().children`, and household-shaped ones (`household_balance`, `cra_receipt`) to the person's own households — never with `.maybeSingle()`, which errored for a separated parent in two households and silently hid their fees card. Nothing mechanical enforces this; it is a code-review rule.
- **`can_bill` is modelled and barely used** — the fee module addresses receipts to a household, not to a billing contact.
- **A person is global, a role is centre-scoped** (one login per human). Correct, but it means an email typo at onboarding creates a duplicate human with no merge path.

---

## 6. Staff files (ss. 53–64)

### What the regulation demands

Per person, depending on their role: a **vulnerable sector check** (with annual **offence declarations** between checks), **standard first aid with infant and child CPR**, **College of Early Childhood Educators registration** for RECEs, a **health assessment** and **immunisation**.

### What Tucked does

`staff_requirement` is the **rule pack** — six rows for CA-ON, each saying which roles it applies to:

| Requirement | Applies to |
|---|---|
| Vulnerable sector check | Everyone including volunteers |
| Offence declaration | Everyone, **one every year without a VSC** |
| Standard first aid with infant/child CPR | Staff counted in ratio — **never a volunteer** |
| College of ECE registration | RECEs |
| Health assessment | Per role |
| Immunisation (or the objection form) | Per role |

**A volunteer is asked for a police check and a health assessment, never for first aid, because a volunteer is never counted in ratio.** That is the rule pack expressing the ratio rule.

`credential` is the ledger; `staff_document` is the file. **A VSC's expiry is derived**, not typed: `new.expires_on := (new.issued_on + interval '5 years')::date`.

`staff_file_gaps()` and `offence_declaration_gaps()` are the two questions an advisor asks.

**Migration 0032 tightened the evidence bucket.** As shipped in 0012, any care-staff member could read any file in the centre — an educator could read a colleague's police check. Storage policies are now path-scoped: a person reads their own files; leadership reads the centre's.

### Every case

| Situation | What happens |
|---|---|
| VSC with no police service named | `a vulnerable sector check names the police service that conducted it` |
| VSC with no obtained date | `record the date the check was obtained` |
| VSC with no conducted date | `record the date the police service conducted the check` |
| Conducted **after** obtained | `the check cannot have been conducted after it was obtained` |
| **Check more than six months old when obtained** | `that check was already more than six months old when it was obtained (conducted {d}, obtained {d})` |
| VSC recorded | Expiry derived as issued + 5 years |
| Offence declaration with no year | `an offence declaration says which year it covers` |
| Credential with no expiry | `record the date this expires — the whole point of the ledger is the date` |
| Document uploaded outside `{centre}/{person}/…` | `a staff document lives at {centre}/{person}/… and nowhere else` |
| Document with no file name | `a document needs its file name` |
| Document attached to somebody else's credential | `that credential belongs to somebody else` |
| Superseding an already-superseded document | `this document has already been replaced` |
| A non-leader manages staff files | `staff files are kept by centre leadership` |
| An educator tries to read a colleague's file | RLS returns nothing |
| Expiring soon | Console home: **Due** — "{Name}: first aid cpr expires {date}" |

### Where this is weak

- **`credential_type` includes `training`, which is in no requirement row and has no surface.** Dead enum value.
- **`staff_document.kind` accepts `policy_acknowledgement`, `contract` and `other`; nothing writes them.**
- **The first-aid renewal interval (3 years) is seeded**, used only to compute "expiring soon". The certificate's own printed expiry always wins because it is what gets recorded — but the seeded interval should still be confirmed.
- **No employer duty to report RECE matters to the College.** Not modelled at all ([06](06-gaps-risks-and-roadmap.md)).

---

## 7. Policies and the record that staff read them (ss. 46, 48)

### The gap this closes

A licensee could show an advisor the program statement, and could show them the staff list, and had **nothing connecting the two**. s. 46 requires that every person reviews the program statement **before** they begin and **at least annually**, and again **whenever it is modified**.

### What Tucked does

`policy_spec` is the rule pack — **nine policies for CA-ON**, each with its regulation, who it applies to, and a review interval:

| Policy | Regulation |
|---|---|
| Program statement | s. 46 |
| Prohibited practices | s. 48 |
| Supervision of volunteers and students | s. 11(3) |
| Police record check policy | ss. 60–62 |
| Staff training and development | s. 63 |
| Safe arrival and dismissal | s. 50 |
| *(plus anaphylaxis, serious occurrence, and emergency management)* | |

`policy_version` is **immutable once published**. `policy_attestation` is the record that a named person read a named version on a date.

**The program statement is sourced from the handbook** (`sourced_from: 'handbook.program_statement'`) — one text, two obligations, and `app.handbook_syncs_program_statement` keeps them from disagreeing.

**Republishing an unchanged policy is refused**, because asking a whole staff to re-read an identical document is noise dressed as compliance.

### Every case

| Situation | What happens |
|---|---|
| Publishing an empty policy | `a policy with no words is not a policy` |
| Publishing an unknown key | `there is no policy "{key}" in this jurisdiction` |
| Editing a published version | `a published policy is never edited; publish a new version` |
| **Republishing identical text** | `that is word for word the policy already published — nobody needs to read it again` |
| A person outside the centre attests | `only somebody working at this centre attests to its policies` |
| Attesting to a superseded version | `that version has been replaced; read the current one` |
| Recording an attestation for a non-employee | `that person does not work at this centre` |
| Attestation dated in the future | `somebody cannot have read it tomorrow` |
| Duplicate attestation | `that is already on their file` |
| Somebody has not read a policy that applies to them | Console home: **Due** — "N people have not read a policy that applies to them (s. 46)" |
| A policy the centre must hold has never been written | Console home: **Now** — "N policies the centre must hold have not been written" |

### Where this is weak

- **Attestation is a button, not comprehension.** That matches what the regulation asks for, but nobody should mistake it for training.
- **The annual review clock is per policy spec** (`review_months`), and nothing warns before it lapses — the gap appears only once it has.

---

## 8. The parent handbook (s. 45)

### What the regulation demands

s. 45(1) lists what a parent handbook **must** contain, and s. 45 requires that parents receive it.

### What Tucked does

`handbook_section_spec` is the rule pack — **14 sections for CA-ON**, keyed by jurisdiction, so a Manitoba pack is a set of rows and every rule below keeps working.

Two sections are **sourced from elsewhere and cannot be contradicted**:

- **CWELCC enrolment** — the first line is written from `centre.cwelcc_enrolled`.
- **The anaphylaxis policy** — edited on Plans & allergies; the handbook reads it from there.

A published handbook is **immutable**. Issuing a new one requires that something actually changed, and requires the licensee to say **what** changed, because every family is being asked to read it again.

`handbook_acknowledgement` is the evidence a family received it; `handbook_outstanding` is the view of who has not.

### Every case

| Situation | What happens |
|---|---|
| Editing a published handbook | `a published handbook is never edited — publish a new version instead` |
| Saving an unknown section | `the handbook has no section "{key}" in this jurisdiction` |
| Editing the anaphylaxis section here | `the anaphylaxis policy is edited on Plans & allergies — the handbook reads it from there` |
| Saving a blank section | `a handbook section is never blank — s. 45 requires this content` |
| A non-leader publishes | `only centre leadership issues the parent handbook` |
| Publishing with sections missing | `s. 45 requires every section before the handbook is issued — still missing: {list}` |
| **Publishing with nothing changed** | `nothing has changed since version {n} — there is no new handbook to issue` |
| Publishing with no change note | `say what changed — every family is being asked to read this again` |
| A non-consenting adult acknowledges | `only a consenting household adult can acknowledge the handbook` |
| Acknowledgement dated in the future | `an acknowledgement is recorded when it happens, not ahead of it` |
| Duplicate acknowledgement | `that parent has already acknowledged this handbook` |
| Outstanding acknowledgements | Console home: **Due** — "N parents have not acknowledged the current handbook (s. 45)" |

### Where this is weak

- **The handbook is text, not a document.** There is a printable view; there is no PDF, and a centre with an existing designed handbook cannot upload it.
- **The waiting-list section must match `app.waitlist_rank`** and nothing checks that it does — see §9.
- **14 sections is a long form** with no autosave.

---

## 9. The waiting list (s. 75.1)

### What the regulation demands

Four rules, and the schema holds all four:

1. **No fee and no deposit, ever**, to be placed on the list.
2. A family can learn **their own position** without learning anyone else's.
3. The order is **the order families joined**, unless a written priority says otherwise.
4. The **handbook** explains the order.

### What Tucked does

**Rule 1 is enforced by absence.** There is nowhere in the schema to put a fee. No amount, no deposit, no payment column exists on any waitlist table. Not "we choose not to charge" — there is no field.

**Rule 2** is `waitlist_self_check(code)`, granted to `anon`: a family takes their code and gets **their position and nothing about anyone else**. It works with no account at all. Families with accounts use `my_waitlist_positions()`.

**The ranked view is care-staff-only.** An early draft let a family see the ranked list, which would tell them they were first — and tell them who was second.

**Rule 3** is the join anchor:

```sql
-- The position anchor: the moment the family joined, and it never moves.
-- clock_timestamp, not now(): two families added in one transaction still
-- joined in an order, and that order is their place in the queue.
joined_at timestamptz not null default clock_timestamp(),
```

`app.waitlist_rank` orders by sibling → subsidy referral → date joined.

Closed entries are anonymised **twelve months after closing** by `app.run_waitlist_sweep` at 02:45 — with its own cron, separate from the children's-record sweep, because conflating the two return values broke a retention test.

### Every case

| Situation | What happens |
|---|---|
| Joining with no contact route | `record an email or a phone number so the family can be reached` |
| Joining with no child or contact | `a waiting-list entry names the child and who to contact` |
| A start date in the past | `a start date in the past is not a place on the list` |
| Editing `joined_at` | `the moment a family joined is their place in the queue and never moves` |
| Priority with no reason | `a family placed above the date order is recorded with a reason` |
| A non-leader sets priority or offers a place | `only centre leadership changes a family's place` / `only centre leadership offers a place` |
| Offering a place to a family not waiting | `only a waiting family can be offered a place` |
| Offer with no response date | `give the family a date in the future to respond by` |
| A response with no offer outstanding | `there is no offer outstanding for this family` |
| A response that is neither accept nor decline | `a family either accepts or declines the place` |
| Acting on a closed entry | `this entry is closed` |
| Anonymising early | `a waiting-list entry is anonymised twelve months after it closes, never before` |
| A family checks their own code | Their position. Nothing about anyone else |
| An offer passes its response date | Console home: **Due** — "N waiting-list offers have passed the date the family was asked to respond by" |

### Where this is weak

- **Joining is a staff act.** s. 75.1 requires self-serve *position*, which is built and works with no account. Self-serve *joining* would need a public write endpoint and rate limiting.
- **The priority order must match that centre's handbook** and nothing checks it. This is the most consequential unchecked coupling in the product: the handbook is what the family was promised.
- **`waitlist_self_check` is granted to `anon`** with no rate limit. A code is long enough to be unguessable; nothing stops somebody trying.

---

## 10. Fees, the CWELCC cap and CRA receipts

### The decision this module encodes

> **Tucked records money; it does not move money.**

No card processing, no parent-side payment fee, no PCI scope in a database holding children's photographs. The centre records what arrived — pre-authorised debit, e-transfer, cheque, subsidy.

### What the rules demand

- **CWELCC**: for an eligible child, the base fee is **capped**. A fee above the cap cannot be charged.
- **Non-base fees are always optional** — never a condition of enrolment. That is a check constraint: `check (kind = 'base' or optional)`.
- **Withdrawal from CWELCC requires 30 days' notice** to every family and employee: `check (effective_on >= notice_given_on + 30)`.
- **O. Reg. 138/15 s. 27.1**: financial records are kept **six years**.

### What Tucked does

`cwelcc_parameter` holds the cap and the eligibility cutoff as **jurisdiction data**. `app.cwelcc_eligible` decides per child. `app.cwelcc_cap` is date-aware, so a cap change is a new row.

`fee_schedule` / `fee_item` are the plan; `fee_charge` / `fee_credit` / `fee_payment` are the ledger; `household_balance` is the view. **A charge is never edited — a credit note sits beside it.**

`cra_receipt` (+ lines) is issued per household per tax year. It **keeps names for six years**, outliving the three-year children's-record anonymiser, and is redacted by `app.run_financial_sweep`.

**Nothing here can lock a record.** No policy in this module gates a regulated record on billing state (§9.14 never-do #1), and pgTAP proves it.

### Every case

| Situation | What happens |
|---|---|
| Base fee above the cap for an eligible child | `the base fee for an eligible child cannot be more than ${cap} a day under CWELCC (you entered ${x})` |
| Charging above the cap | `that is ${x} a day for an eligible child; the CWELCC cap is ${cap}` |
| A non-base fee marked non-optional | Constraint violation — the schema will not accept it |
| Editing a charge | `a charge is never edited; record a credit note beside it` |
| A charge with no description | `a charge says what it is for` |
| A fee item with no purpose | `say what the fee is for — the handbook has to explain it (s. 45)` |
| A credit with no reason | `a credit says why — that is the whole of the correction` |
| A payment dated in the future | `a payment is recorded when it arrives, not before` |
| A non-licensee sets fees | `fees are set by the licensee` |
| Editing an issued receipt | `an issued receipt is never altered; issue a replacement` |
| Receipt for a future tax year | `that tax year has not happened yet` |
| Receipt with no payments | `no payments were received from this family in {year}` |
| Receipt with nobody to address | `this household has nobody to address the receipt to` |
| CWELCC withdrawal with under 30 days | Constraint violation |
| Withdrawal with no reason | `record why — every family and every employee is about to be told` |
| Serving a notice twice | `that person has already been served` |
| Redacting a receipt early | `a financial record is kept six years (O. Reg. 138/15 s. 27.1) — never redacted before` |
| A family owes money | **Nothing is locked.** Ever |

### Where this is weak

- **The CWELCC cap ($22.00/day) and the 30 June cutoff are seeded** and the programme's funded rate is scheduled to change. Row change, but confirm it ([06](06-gaps-risks-and-roadmap.md)).
- **Fee subsidy administration is not modelled.** A subsidy payment can be *recorded*; the subsidy relationship — eligibility, the City's portion vs the family's, reconciliation — is not.
- **No service-system-manager reporting.** Toronto Children's Services wants the numbers in its own formats; those have to come from discovery with an actual service agreement, not from a plausible CSV.
- **Two retention duties are in tension**, resolved in favour of both: a family asking "delete everything about my child" cannot have the receipts until six years. Somebody should be able to explain that.

---

## 11. Documents on the premises

### What this is

The first thing a program advisor asks to see and the last thing a centre can find. `centre_document_spec` is the rule pack — **eight kinds for CA-ON, six of them required**:

| Kind | Required |
|---|---|
| Licence | ✅ |
| Ministry inspection report | ✅ |
| Fire inspection report | ✅ |
| Public health inspection report | ✅ |
| Annual playground inspection | ✅ |
| Certificate of insurance | ✅ |
| Approved floor plan | — |
| Other | — |

`centre_document_gaps()` answers "what is missing or out of date". Documents are superseded, never replaced in place.

### The latent crash this module fixed

The evidence-bucket storage policies parsed a UUID out of the object path. `(split_part(name,'/',2))::uuid` **raises** on a non-UUID segment — and **a policy that raises fails the query**. The moment a centre-level path (`{centre}/centre/…`) existed, every staff-file read would have started erroring. `app.path_uuid(name, segment)` parses safely and returns null instead.

### Every case

| Situation | What happens |
|---|---|
| Document outside `{centre}/centre/…` | `a centre document lives at {centre}/centre/… and nowhere else` |
| No title or file name | `a document needs a title and its file name` |
| Unknown kind | `there is no document kind "{kind}" in this jurisdiction` |
| Inspection report issued in the future | `an inspection report cannot have been issued in the future` |
| Superseding a superseded document | `this document has already been replaced` |
| A non-leader attaches | `the centre's documents are kept by centre leadership` |
| Missing or expired | Console home: **Due** — "N of the documents that must be on the premises are missing or out of date: {list}" |
| A parent requests a centre document | RLS returns nothing (verified with a fresh request, not a cached one) |

### Where this is weak

- **Expiry is per document, not per kind.** A fire inspection with no recorded expiry never goes stale.
- **No reminder before expiry**, only after.

---

## 12. The compliance calendar (Parts 4 and 10)

### What Tucked does

**Twelve recurring tasks** seeded per centre, each of whose completion **is** the written record: PIN-signed, note required, append-only, audited.

| Task | Cadence |
|---|---|
| Fire drill | Monthly |
| Fire alarm & equipment test | Monthly |
| Fire procedure approved by the fire chief & posted in every room | Annual |
| Emergency management policy review (lockdown, evacuation, shelter) | Annual |
| Playground daily visual check | Daily |
| Playground monthly inspection | Monthly |
| Playground annual inspection (certified inspector, fixed structures) | Annual |
| First-aid kit inspection (contents, locations, manual) | Monthly |
| Water temperature check (max 49 °C where children reach) | Monthly |
| Anaphylaxis policy annual staff review | Annual |
| Program statement annual review | Annual |
| Electronic sleep monitors daily check | Daily |

Playground inspections cite **CSA Z614**.

**A real fire drill completes the scheduled task.** `app.headcount_completes_drill` links an `evacuation_drill` headcount to the `fire_drill` task, so a centre never records the same drill twice.

The **repair log** (`compliance_issue`) records a hazard with what is restricted until it is fixed — and lifting the restriction requires saying what was repaired.

### Every case

| Situation | What happens |
|---|---|
| Completing with no note | `the completion IS the written record — say what was done and what was found` |
| Completion dated in the future | `a completion cannot be dated in the future` |
| Recording a hazard with no description | `describe the hazard` |
| Resolving a resolved issue | `already resolved` |
| Lifting a restriction with no detail | `say what was repaired or changed before lifting the restriction` |
| A non-leader changes the schedule | `only centre leadership changes the compliance schedule` |
| A real drill is recorded | The scheduled fire-drill task completes itself |
| A task is overdue | Console home: **Due** — "N compliance tasks overdue (drills, tests, inspections)" |
| An unresolved hazard | Console home: **Now** — "N premises hazards on the repair log — restricted until fixed" |

### Where this is weak

- **Cadence is a string, not a calendar.** "Monthly" means "a month since the last completion", so a centre that completes late drifts.
- **No assignment.** Tasks belong to the centre, not to a person.
- **The sleep-monitor check does not know which monitor.** A reminder, not a record of a device.

---

## 13. Retention and anonymisation (s. 72(5))

### What the regulation demands

Children's records — including attendance and plans — are kept **three years after discharge**. Financial records are kept **six years** (O. Reg. 138/15 s. 27.1).

### What Tucked does

Three rules, all tested:

1. **Nothing is touched before its clock matures.** The anonymiser refuses even when called directly: `never: the retention period has not ended (kept until {date})`.
2. **"Purge" means anonymise.** Every regulated row **survives**. Names, addresses and free text are removed; the record of what happened stays, because that is what the regulation asked to be kept.
3. **There is an audit trail of the anonymisation itself.**

`retention_clock` starts at discharge. `app.run_retention_sweep()` runs at 02:30. `app.is_anonymising()` is the flag that lets the sweep past the append-only triggers — the escape hatch that migration 0038 accidentally dropped and the suite caught.

### Every case

| Situation | What happens |
|---|---|
| Child still enrolled | `never: this child is not discharged — no retention clock is running` |
| No clock exists | `never: no retention clock exists for this child` |
| Clock has not matured | `never: the retention period has not ended (kept until {date})` |
| Clock matured | Free text stripped from care logs; identity anonymised; **every row survives** |
| A serious occurrence naming the child | **Not scrubbed** — a Ministry-filed record with its own lifecycle |
| A CRA receipt naming the child | **Not scrubbed at three years** — kept six, then redacted by the financial sweep |
| Waiting-list entry closed 12 months ago | Anonymised by its own separate sweep |

### Where this is weak

- **Three sweeps, three crons, no shared reporting.** Nothing says "last night's retention run anonymised N children".
- **A `pg_cron` failure is silent.** If the sweep errors, records are kept longer than they should be and nobody learns.
- **No PIPEDA access/deletion workflow.** RLS gives every family read access to their own child's record, which covers the spirit. There is no request-and-response record and no 30-day SLA tracker.

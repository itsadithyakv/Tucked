# 04 — Data model, security and the platform layer

*How the database is actually put together: the write model, RLS, the PIN, audit, storage, break-glass, the platform/billing layer, push delivery, testing — and the bug classes this project has hit more than once.*

**§9 is the most useful section in this file.** It is the list of mistakes that have already been made here, each of which cost real debugging time and each of which will recur.

---

## Contents

1. [Schema conventions](#1-schema-conventions)
2. [The write model — why clients never INSERT](#2-the-write-model--why-clients-never-insert)
3. [The PIN — "who logged it"](#3-the-pin--who-logged-it)
4. [Append-only, corrections, and the never-do list](#4-append-only-corrections-and-the-never-do-list)
5. [Row Level Security](#5-row-level-security)
6. [Audit](#6-audit)
7. [Storage and consent](#7-storage-and-consent)
8. [Break-glass (s. 82(2))](#8-break-glass-s-822)
9. [Recurring bug classes — read this one](#9-recurring-bug-classes--read-this-one)
10. [The platform layer](#10-the-platform-layer)
11. [Push delivery, end to end](#11-push-delivery-end-to-end)
12. [Testing](#12-testing)

---

## 1. Schema conventions

- **Every data table carries `centre_id`**, including join tables. This is not redundancy — it is what keeps RLS policies non-recursive and cheap.
- **UUID primary keys**, `gen_random_uuid()`.
- **`created_at timestamptz not null default now()`** on essentially everything.
- **Enums for closed sets** (`role_id`, `care_log_type`, `record_item_type`, `consent_type`, `credential_type`, `attendance_event_type`, `age_group_preset`, `province`, `notification_channel`, `medication_kind`, `record_item_status`).
- **`jsonb payload` only where the shape genuinely varies** — the care log. Validated by a SQL function per type, not left open.
- **Two schemas.** `public` holds tables and the RPCs clients call. `app` holds `SECURITY DEFINER` helpers, trigger functions and sweeps that clients must never call. Anything in `app` is deliberately not exposed.
- **Rule packs are jurisdiction data**: `outdoor_requirement`, `staff_requirement`, `policy_spec`, `handbook_section_spec`, `centre_document_spec`, `cwelcc_parameter`, `illness_policy`, `statutory_holiday`. Each keyed by `jurisdiction_code`.
- **Naming is final** and mirrored in `packages/domain/src/schemas.ts`.

### Timezone discipline

A centre has a `timezone`. Every derived date column — `attendance_date`, `log_date`, `outdoor_date`, `record_date` — is computed **from the centre's timezone**, never the server's and never the reader's:

```sql
new.log_date := (new.logged_at at time zone tz)::date;
```

Display follows the same rule: block times render via `hhmm(iso, centre.timezone)`.

**`clock_timestamp()` vs `now()`:** `now()` is identical for every statement in a transaction. Where ordering within a transaction is semantically meaningful — the waiting-list join anchor — `clock_timestamp()` is used deliberately.

---

## 2. The write model — why clients never INSERT

Every regulated table follows the same pattern:

```
RLS: SELECT policy only. No INSERT, UPDATE or DELETE policy for clients.
     ↓
Client calls a SECURITY DEFINER RPC in `public`.
     ↓
RPC calls app.resolve_recorder(centre, person, pin) → the person id, or it raises.
     ↓
RPC inserts. A BEFORE trigger applies the rules and can raise.
     ↓
An AFTER trigger writes audit_event.
     ↓
A BEFORE DELETE trigger (app.block_mutation) refuses deletion for every role.
```

Consequences worth internalising:

- **A client cannot write an invalid regulated record**, because the client is not what decides.
- **A missing RLS write policy is a silent no-op, not an error.** A `DELETE` that matches no rows raises nothing. Protection is therefore asserted as *a count that did not change*, not as an exception — and the trigger is tested separately as the backstop for anything that gets past RLS.
- **Testing a CHECK constraint through a direct client insert proves nothing**, because RLS refuses the row before the constraint is evaluated. Constraint tests must go through the RPC.

Both of those were learned by writing tests that were wrong about our own system (§9).

---

## 3. The PIN — "who logged it"

A room tablet is shared. Individual accountability comes from a 4–6 digit staff PIN required on **every regulated write**.

- `staff_pin` stores a bcrypt hash (`extensions.crypt`), never the PIN.
- `app.verify_pin(person, centre, pin)` checks it.
- `app.resolve_recorder(centre, person, pin)` is the single entry point every write RPC calls. It checks the person holds a **care role at this centre** and that the PIN matches, then returns the person id — or raises.

| Refusal | Message |
|---|---|
| Not a member of this centre | `not authorised for this centre` |
| Member but no care role | `recorder has no care role at this centre` |
| Wrong PIN | `invalid staff PIN` |
| Setting a PIN outside 4–6 digits | `PIN must be 4-6 digits` |
| Setting somebody else's PIN | `not authorised to set this PIN` |

### Where this is weak

- **No PIN rate limiting.** A 4-digit PIN is 10,000 possibilities and nothing throttles attempts or locks out. On a device physically inside a centre this is a modest risk, but it is a real one and the fix is cheap.
- **No PIN rotation policy or expiry.**
- **A PIN is per person per centre**, so a dual-role person at two centres has two PINs and no way to see that.

---

## 4. Append-only, corrections, and the never-do list

### The correction pattern

Regulated rows are never updated. A mistake is fixed by inserting a **correction row** carrying `correction_of` (the original) and `correction_reason`. Both are enforced together:

```sql
constraint care_log_correction_needs_reason
  check ((correction_of is null) = (correction_reason is null))
```

Every read that reasons about a register ignores rows that have a correction pointing at them:

```sql
and not exists (select 1 from public.care_log c where c.correction_of = cl.id)
```

**A correction can do things the original write could not.** An excluded child can be signed in *as a correction*; a nap position can be corrected to one the rule would refuse. That is deliberate: the register must always be able to state what actually happened, including a breach.

### §9.14 — the never-do list, each proven by a test

| Never | How it is proven |
|---|---|
| Billing state locks or hides a regulated record | No policy in the platform module references subscription state; pgTAP asserts a record stays readable with a lapsed plan |
| Anything is deleted before its retention period | `app.anonymise_child` refuses with `never: the retention period has not ended (kept until …)` |
| Anything is auto-filed with a regulator | Nothing files anywhere. The CCLS number is *recorded*, having been received by a human |
| A monitor or AI substitutes for a direct sleep check or the human close | Sleep checks are per-child rows recorded by a PIN-signed human; `s37_close_names_the_human` |
| The daily record draft is generated rather than derived | `never_the_daily_record_draft_is_deterministic_not_generated` |
| A required record is deletable by anyone, including `service_role` | `app.block_mutation` fires for every role |

---

## 5. Row Level Security

### The helper functions

RLS policies must never recurse through RLS. Every helper is `SECURITY DEFINER`:

| Helper | Answers |
|---|---|
| `app.current_person_id()` | Who am I? |
| `app.member_centre_ids()` | Centres I belong to in any capacity |
| `app.care_centre_ids()` | Centres where I hold a **care** role |
| `app.staff_centre_ids()` | Centres where I am staff |
| `app.has_role(centre, roles[])` | Do I hold one of these roles here? |
| `app.my_household_ids()` | Households I am a member of |
| `app.my_viewable_household_ids()` | Households I may **view** (`can_view`, not revoked) |
| `app.is_consenting_member(child, person)` | May this person consent for this child? |
| `app.is_household_comember(a, b)` | Adults in one household see each other |
| `app.is_centre_workforce(person, centre)` | A parent may see staff by name |
| `app.has_break_glass(centre)` | Is emergency read access open? |
| `app.is_platform_admin()` | PaperKite admin |
| `app.has_live_device(person)` | Does this person have a registered push token? |

### The typical policy shapes

**Care staff plus the child's own family:**

```sql
create policy x_select on public.x
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = x.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
```

**Everyone at the centre, families included** (menus, outdoor periods, announcements) uses `app.member_centre_ids()`.

**Leadership only** (waitlist ranking, daily record preview, staff files) uses `app.has_role(centre, array['supervisor','designate','licensee_admin'])`.

### Where this is weak

- **Policies are hand-written per table and not generated**, so a new table can easily get a subtly different shape. There is no lint for "every table has RLS enabled and at least one policy".
- **`security_invoker` views are the single most dangerous default here.** See §9.
- **A family's read of the workforce is centre-wide**, so a parent sees every staff name including those in other rooms. Correct for messaging, more than strictly needed.

---

## 6. Audit

`audit_event` is append-only — enforced by `app.block_mutation` on `before update or delete`, for **every role including `service_role`**.

`app.audit_row()` is a generic `SECURITY DEFINER` trigger attached to every regulated table. It records **references only**: table, row id, action, actor, timestamp. **Never photos, never free-text health details.** An audit log that copies the sensitive payload doubles the exposure it was meant to police.

### Where this is weak

- **There is no audit reader.** Nothing in either app surfaces `audit_event`. It exists for an investigation nobody has yet had to run, and its usability is untested.
- **Attaching the trigger is manual per table.** Nothing verifies that every regulated table has it.
- **No retention on the audit table itself.**

---

## 7. Storage and consent

Two private buckets. No public bucket exists.

| Bucket | Path shape | Read access |
|---|---|---|
| `evidence` | `{centre}/{person}/…` for staff files; `{centre}/centre/…` for premises documents | The person themself, or centre leadership |
| `photos` | `{centre}/{child}/…` | Consent-gated, family and care staff |

Paths are parsed with `app.path_uuid(name, segment)`, which returns null rather than raising on a non-UUID segment (§9).

**Client-side image discipline** (also the cost rule): long edge 2560 px, quality ≈ 85, EXIF stripped **except capture time** — the dated-photos promise. Feeds serve thumbnails; the stored original moves only on explicit download or zoom.

**Consent is enforced at query level.** A child without group-photo consent is excluded from the relevant reads. Photo visibility follows `consent` rows, not client filtering. A removed household member loses photo access immediately because signed URLs are short-lived and re-authorised on every read.

### Where this is weak

- **The `photos` bucket is entirely unused.** Policies written in migration 0012, consent-gated, and **no surface uploads a photo.** The `photo` care-log type exists and nothing produces one.
- **No virus or content scanning** on uploads.
- **No storage quota per centre.**

---

## 8. Break-glass (s. 82(2))

### Why it exists

Electronic records are permitted **only if** staff and Ministry officials can always get in. "Ask your administrator to unlock it" is not an answer to a program advisor standing in the lobby.

### Two failure modes, two mechanisms

1. **The evacuation screen** — outside authentication, entirely from the device cache, no network. The life-safety case ([02 §4](02-features-daily-care.md)).
2. **`break_glass_access`** — a **read-only, 24-hour, self-expiring** unlock, loud to leadership, fully audited. `app.has_break_glass(centre)` widens RLS for its holder while it is open.

### Every case

| Situation | What happens |
|---|---|
| Opening with a vague reason | `a break-glass needs a real reason — who needs the records and why the supervisor cannot provide them` |
| Opening a second one | `you already have emergency access open` |
| Closing | By the holder or centre leadership |
| Someone else closing | `only the holder or centre leadership can close emergency access` |
| Closing twice | `already closed` |
| 24 hours elapse | Expires on its own |
| While open | Console home: **Now** — "Emergency read-only access open: {name} — '{reason}' — expires {time} (s. 82(2), audited)" |

### Where this is weak

- **Read-only is the right default and also a limit.** A supervisor genuinely unavailable for a week leaves a centre unable to *write* leadership-gated records; the only path is `admin_grant_supervisor` by a platform admin.
- **No physical-device fallback if the whole internet is down at the centre.** The evacuation cache covers life safety only; the register itself is unreachable.

---

## 9. Recurring bug classes — read this one

Each of these has bitten this project at least once. Each will recur.

### 9.1 A view that reasons about ABSENCE must not be `security_invoker`

**Hit three times.** A `security_invoker` view asking "does X exist?" evaluates under the caller's RLS. If the caller cannot see the table, the view sees nothing and confidently reports **false**.

- `undeliverable_now_alerts` asked "does this person have a device?" under the caller's RLS. A supervisor saw the **entire centre** as unreachable.
- `push_never_arrived` repeated it.
- The same shape lurks anywhere a view says `not exists`.

**The fix each time:** a `SECURITY DEFINER` helper (`app.has_live_device`, `app.push_all_tickets_failed`, `app.push_failure_reason`) and a tombstone test.

> **Rule:** if a view answers a question about the absence of rows, the thing that looks for those rows must be able to see the whole table.

### 9.2 `create or replace function` silently discards a later migration's amendment

Migration 0038 rebuilt `app.care_log_rules()` from the 0006 text. Migration **0022** had amended that function to let the s. 72(5) anonymiser through:

```sql
if tg_op = 'UPDATE' then
  if app.is_anonymising() then return new; end if;   -- ← dropped
  raise exception 'care logs are never updated; record a correction';
end if;
```

The retention sweep then failed on every child it touched. The suite caught it.

> **Rule:** when replacing a function, start from the **database's current definition**, not from the migration that first created it. `app.care_log_rules()` and `app.attendance_event_rules()` are both multi-migration choke points.

### 9.3 `REVOKE … FROM anon, authenticated` leaves PostgreSQL's grant to PUBLIC

PostgreSQL grants `EXECUTE` on a new function to `PUBLIC`, and both roles inherit it. Revoking only the named roles leaves the door open.

```sql
revoke execute on function public.notifications_to_push(integer)
  from public, anon, authenticated;
```

**Worse:** the first catalogue test *passed anyway*, because it queried `role_routine_grants` by grantee name and never saw the PUBLIC grant. The test was rewritten to use `has_function_privilege`.

> **Rule:** revoke `from public` as well, and test with `has_function_privilege`, never by listing grantees.

### 9.4 `RETURNS TABLE` parameter names shadow columns

A function whose `RETURNS TABLE` names include `child_id` has that name in scope as a parameter. An unqualified `child_id` in the body silently binds to the parameter, grouping every row under a null id.

```sql
-- every column reference here is qualified on purpose
select l.child_id, l.room_id, l.actual_time as in_at, …
from live l
```

> **Rule:** qualify every column reference inside a `RETURNS TABLE` function.

### 9.5 Test fixtures anchored to `now()` cross local midnight

`now() - interval '8 hours'` runs fine at midday and crosses Toronto midnight at 01:00. Several suites were time-of-day fragile.

> **Rule:** anchor to the centre's local day:
> ```sql
> (((now() at time zone 'America/Toronto')::date + time '12:00') at time zone 'America/Toronto')
> ```

### 9.6 A policy that RAISES fails the whole query

`(split_part(name,'/',2))::uuid` raises on a non-UUID segment. Because it lived in a storage policy, the first centre-level path would have made **every staff-file read** start erroring. `app.path_uuid()` returns null instead.

> **Rule:** a function called from an RLS policy must never raise. Return null.

### 9.7 RLS wins before CHECK constraints, and DELETE fails silently

Two consequences for tests, both learned the hard way:

- A direct client `INSERT` testing a CHECK constraint is refused by RLS first, so it proves nothing. **Test constraints through the RPC.**
- A client `DELETE` against a table with no delete policy matches no rows and **raises nothing at all**. Assert a count, then test the append-only trigger separately as `postgres`.

### 9.8 Two faces of one schema drift unless something compares them

`careLogSchemas.ts` declared `position` as an enum; `app.validate_care_log_payload` validated nothing. For the entire life of the project. The header comment said "change both together"; nothing tested it. **This is still not mechanically checked.**

---

## 10. The platform layer

The platform layer manages **tenancy and money, never children**.

- `platform_admin` holds **no care role**, so RLS never shows them a child, an attendance row, or a family. This is the strongest privacy property in the system and it comes from the role model rather than from a filter.
- `jurisdiction` declares which regulator's rule pack a centre runs under. **CA-ON is the only implemented pack**; CA-MB and CA-QC are seeded as `planned`/inactive, and `admin_create_centre` refuses to create a centre in a jurisdiction until its pack is `implemented` — proven by `planned_jurisdictions_reject_centres_until_implemented`.
- `plan`, `centre_subscription`, `billing_event` hold commercial state. **No policy in this module gates a regulated record on billing state** (§9.14 never-do #1).
- `app.link_person_on_signup` connects an `auth.users` row to the `person` record created at onboarding.

### Every case

| Situation | What happens |
|---|---|
| A non-admin calls an admin RPC | `platform admins only` |
| Creating a centre in a planned jurisdiction | `jurisdiction {code} is not accepting centres yet` |
| Creating a centre with no supervisor email | `a supervisor email is required — it is how they sign in` |
| Unknown plan | `unknown plan {name}` |
| Unknown subscription status | `unknown status {s}` |
| Setting a plan for a centre with no subscription | `centre {id} has no subscription` |
| Recording a zero or negative payment | `a payment needs a positive amount` |
| Adding an admin with no email | `an email address is required` |
| A lapsed subscription | **Every regulated record stays readable and writable** |

### Where this is weak

- **One centre per console session.** A supervisor of two centres signs out and back in. `licensee` exists and owns centres; nothing aggregates across them.
- **No self-serve onboarding.** A platform admin creates every centre by hand.
- **Billing is a ledger, not an integration.** Stripe is a Phase 2 decision that has not been made.

---

## 11. Push delivery, end to end

The most intricate pipeline in the system, because it is the one that leaves the building.

```
notification row created (often by a trigger, e.g. an accident report)
   ↓
app.notifications_to_push(limit)   ← the PRODUCT PROMISE lives here, pgTAP-proven
   ↓
pg_cron 'push-dispatch' every 2 min → app.dispatch_push() → pg_net → Edge Function `notify`
   ↓
Expo push API → a TICKET per message (accepted ≠ delivered)
   ↓
app.record_push_tickets  →  push_ticket rows
   ↓
a few minutes later: Expo receipts → app.record_push_receipt
   ↓
delivered_at set from the first ok receipt; dead tokens revoked
   ↓
push_never_arrived / undeliverable_now_alerts / stuck_push_alerts → console home
```

### The design decisions worth knowing

- **The Edge Function is a dumb pipe.** *Which* notifications get pushed — every Now alert; of the Later feed only the daily story, at most one per person per day — is a product promise that lives in the database where pgTAP can hold it to account. Nothing in TypeScript decides.
- **"Sent" and "arrived" are different.** Expo accepting a message is a **ticket**, not a delivery. Receipts come back minutes later and say what actually happened — the device unregistered, the app was uninstalled, the message was too big.
- **A notification is marked pushed only if Expo accepted that exact message.** Anything else records the reason and stays pending.
- **Failures are deduped per notification, not per message.** A notification with several devices counts as sent if **any** device was accepted; only ones with no accepted device are failures, and each is counted **once**. Counting per message would burn a two-device parent's five retries in two runs.
- **The batch limit is applied after the token join.** An early version applied it first, so tokenless notifications could starve real ones.
- **Dead tokens are retired** (`device_push_token.revoked_at`).

### Configuration required per environment

1. `supabase functions deploy notify` with a `PUSH_SHARED_SECRET`.
2. Two `app_setting` rows (the migration footer spells them out).

Until both exist the dispatcher returns **`not configured`** — nothing is silently dropped. `app_setting` has RLS enabled and **no policies at all**, so no client can read it.

### Every case

| Situation | What happens |
|---|---|
| A Now alert is created | Dispatched within two minutes |
| The recipient has no device | `undeliverable_now_alerts` → console says to call them |
| Expo rejects the message | Reason recorded, stays pending, retried |
| Five attempts fail | `stuck_push_alerts` |
| Expo accepts, receipt says the device unregistered | Token revoked; `push_never_arrived` if every device failed |
| A receipt never comes back | `app.close_stale_push_tickets` at 03:25 |
| The function is not deployed | `not configured` — visible, not silent |
| A client calls `notifications_to_push` | Refused — revoked from `public`, `anon`, `authenticated`; granted to `service_role` |

### Where this is weak

- **Remote push has never reached a real device.** Everything above is proven in the database and against a stubbed Expo endpoint. It needs an EAS dev build.
- **A receipt cannot tell you a human looked at the phone.** That is what the in-app acknowledgement is for.
- **The two `app_setting` rows are a manual step** with no health check saying they are missing beyond the dispatcher's own return value.

---

## 12. Testing

| Suite | Count | Runs in CI? |
|---|---|---|
| **pgTAP** (`supabase/tests/`, 29 files) | **663** | ❌ **No** |
| Domain (`packages/domain/test/`) | 75 | ✅ |
| Design tokens (`packages/ui-tokens/test/`) | 51 | ✅ |
| Mobile offline queue (`apps/mobile/test/`) | 15 | ✅ |

`pnpm check` runs lint + typecheck + the JS/TS suites across 11 Turborepo tasks. The database suite is run by hand:

```bash
pnpm db:seed:gen && pnpm exec supabase db reset && pnpm exec supabase test db
```

### Conventions

- **Every test is named for its regulation section**: `s33_1_front_without_a_direction_is_refused`, `s8_volunteer_never_counted_in_ratio`, `s72_attendance_requires_actual_times`.
- **Tombstone tests** — every bug fixed gets a test named for the mistake, so the class cannot come back quietly.
- **Never-do tests** are prefixed `never_`.
- Each pgTAP file is one transaction, `begin … rollback`, with its own fixture and UUID prefix.

### The design-token tests are unusual and worth copying

`packages/ui-tokens/test/tokens.css.test.ts` parses the project's own `tokens.css` and asserts:

- every colour defined in light is redefined in **both** dark blocks (the `@media` one and the `[data-theme]` one);
- the two dark blocks hold **identical values**;
- `color-scheme` is declared in all three;
- every contrast pair clears the floor **it** claims — 4.5:1, or 3:1 for the two tokens whose own declarations restrict them to large text and UI;
- **dark is never a downgrade**: no pair reads worse in dark than in light;
- the clay foot is darker than its face in every palette.

A ratio written in a document is a claim; a ratio in a test is a rule.

### Where this is weak

- **The 663 most valuable tests in the repository do not run in CI.** This is the single biggest quality gap in the project. A database regression is caught only by whoever remembers to run the suite.
- **No coverage gate is enforced** despite the architecture note asking for ≥ 90 % on the rule engine.
- **The seed is a test surface nobody counts.** It caught a real bug — a `db reset` refused to load when the new sleep rule met a demo nap with no position — but that is luck, not design.
- **No end-to-end test of either app.** The 15 mobile tests cover the offline queue only; every screen is verified by hand in a browser.

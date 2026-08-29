# Phase 0 — Foundation

*Per [tucked-build-prompt.md](../../references/tucked-build-prompt.md) §8. Status: **built 29 Aug 2026** (same day as go-ahead). The §8 answers are recorded in [decisions.md](../decisions.md): global person, day-bounded attendance, `ca.tucked.app` identifiers, local-only Supabase with no git remote.*

**✅ Done-when met (verified 29 Aug 2026, after WSL2 + Docker Desktop install):**

- 62 domain tests green (97% branch coverage on the rule engine, gate ≥ 90%); lint + typecheck clean across all four workspaces; Next.js production build succeeds; the mobile app bundles for Android via Metro.
- All four migrations and the generated seed applied cleanly to the local stack on first run; **pgTAP 16/16 passing** (wrong-centre isolation, revoked household member, volunteer exclusion, append-only audit).
- **Sign-in verified for all three roles**: supervisor in the web console (centre, licence, CWELCC status, three rooms); educator in the mobile app's Room mode (Dara Ocampo · RECE, room roster); parent in Family mode (Alex Osei sees exactly the 3 Osei children out of 40 — RLS in the real UI). Also verified at the API level: supervisor/educator see 40 children, parent sees 3.
- Two navigation bugs found and fixed during verification: sign-in raced the auth context (imperative `router.replace` before `SIGNED_IN` processed — now state-driven redirects), and home screens did not react to sign-out (now guarded).

**Still deferred until accounts exist:** `eas init` (Expo account) and Sentry (DSN). Parent magic-link *completion* on a device (tucked:// deep link) is Phase 1 work; the password path exercised Family mode meanwhile.

**Done when:** a fresh clone seeds the demo centre ("Maple Leaf Early Learning") and both apps sign in as supervisor, educator and parent.

---

## 1. Scope

Phase 0 builds the skeleton everything else hangs on: monorepo + tooling, design tokens, the domain package with the Ontario rule engine and fixtures, the Supabase schema for identity/tenancy (not yet the regulated-record tables), RLS with pgTAP proof, both app shells with working sign-in, CI, and the EAS/Sentry scaffolding.

**Explicit non-goals:** no attendance, care logs, daily written record, medication, accidents, notifications, offline queue, photos, messaging, or exports — all Phase 1. Phase 0 signs three people into an empty, correctly-themed house.

## 2. Repo and tooling

- pnpm workspaces + Turborepo; TypeScript strict everywhere; single root ESLint + Prettier config; `engines`/`.nvmrc` pinned Node LTS.
- Workspaces: `apps/mobile`, `apps/web`, `packages/domain`, `packages/ui-tokens`, `supabase` (scripts only — SQL lives in `supabase/`).
- Local development is offline and free: `supabase start` (Docker) runs the whole backend (cost-model rule 7). No cloud project is required to develop.

## 3. `packages/ui-tokens`

Everything in [design-language.md](../../references/design-language.md) §3–§6 as code, exported twice from one source:

- `tokens.ts` — typed objects for React Native `StyleSheet` (colour, type styles, spacing, radius, shadow, motion).
- `tokens.css` — the same values as CSS custom properties for the web console.
- Font wiring: ttf map for `expo-font` (keys `Gilroy-Light` … `Gilroy-Heavy` — selection is by family name, never `fontWeight`, per the metadata gotcha), and a `fonts.css` with five `@font-face` rules mapping the woff2 files onto one `'Gilroy'` family with explicit weights 300/400/500/700/800.
- A tiny visual check page/screen listing every token (doubles as the theme smoke test).

## 4. `packages/domain`

Pure TypeScript, no React, no Supabase imports. Modules:

| Module | Contents |
|---|---|
| `ageGroups` | Schedule 1 presets: the seven licensed age groups with ratio, max group size, qualified-staff proportion, mixed-age caps |
| `ratios` | Live ratio calculation (who counts: **never** volunteers, students, resource consultants, off-shift supervisors); reduced-ratio windows (6h+ programs: first 90 min / last 60 min / rest ≤ 2 h; floors toddler 1:8, preschool 1:12, kindergarten 1:20, primary/junior 1:23; **never infants, never outdoors**; <6h programs: 30-min windows); 6+ children ⇒ ≥ 2 staff |
| `retention` | Retention clocks: children's records & attendance 3 y post-discharge, financial 6 y; purge = anonymise-after, never before |
| `notifications` | The Now/Later routing table (build prompt §6) as data + a pure `route(event) → channel` function |
| `presets` | Province preset (ON live; MB/QC typed stubs) and room presets (infant/toddler/preschool/kindergarten/school-age/family) driving care-log types |
| `schemas` | Zod schemas for every entity created in Phase 0 (person, roles, household, child, centre, age group, room) |
| `i18n` | en-CA strings (product vocabulary from the Ontario words table); fr-CA scaffold with the same keys |
| `fixtures` | **Maple Leaf Early Learning**: 1 licensee, 1 centre (Toronto, `America/Toronto`), 3 rooms (infant, toddler, preschool), 40 children across ~30 households (incl. one split household with two member adults, one child with a pickup restriction placeholder, siblings in one household), 9 staff (supervisor, 6 RECE/staff, 1 student, 1 volunteer — the last two exist to prove they never count in ratios) |

## 5. `supabase/` — schema, RLS, seed

Phase 0 migrations (regulated-record tables are Phase 1):

| Migration | Tables |
|---|---|
| `0001_tenancy` | `licensee`, `centre` (licence number, capacity per age group, province preset, timezone, CWELCC status, hours), `age_group`, `room` |
| `0002_people` | `person`, `person_role` (role enum from build prompt §4, per centre) |
| `0003_families` | `household`, `child`, `child_household`, `household_member` (per-person permissions: view / message / pickup / consent / billing) |
| `0004_audit` | `audit_event` (append-only; trigger-fed; references only) |

- **RLS on every table from the first migration.** Helper functions `current_person_id()`, `has_role(centre_id, role[])`; policies per role including family adults scoped to their own households.
- Auth: Supabase Auth with role claims in `app_metadata`; family = email magic link, staff = email + password (MFA enrolment lands with the supervisor console work in Phase 1; the role model supports it now).
- pgTAP installed with the test harness running against the local stack.
- `seed.ts` builds Maple Leaf Early Learning from `packages/domain/fixtures` — the single source of truth for demo data.

## 6. App shells

**`apps/mobile`** (Expo, latest SDK, Expo Router): Gilroy loaded via `useFonts`; token-driven theme; Sentry init behind an env flag (absent DSN = disabled, scrubbed config from day one); auth flows (family magic link, staff password); mode resolution by role (Family shell / Room shell — Room's PIN gate is a stub); placeholder homes proving identity + centre data flow.

**`apps/web`** (Next.js App Router): tokens as CSS vars, Gilroy via `fonts.css`; staff sign-in; placeholder console home showing the seeded centre, rooms and counts.

### Screens created in Phase 0

| App | Screen | Proves |
|---|---|---|
| mobile | Sign in — family (magic link) | Auth + deep link handling |
| mobile | Sign in — staff (email + password) | Auth + role claim |
| mobile | Family home (placeholder: children of my household) | RLS: parent sees only own children |
| mobile | Room home (placeholder: room roster; PIN gate stub) | RLS: educator sees own centre |
| mobile | Debug/session screen | Session, role, centre, token theme, font rendering |
| web | Sign in | Staff auth on web |
| web | Console home (placeholder: centre, rooms, counts) | RLS: supervisor scope |

## 7. CI, EAS, Sentry

- **GitHub Actions:** `lint` → `typecheck` → `unit` (domain, ≥ 90% branch coverage on rule modules) → `pgtap` (spins up local Supabase in CI) → `expo prebuild` check. EAS builds are **not** in CI (cost-model rule 4).
- **EAS:** `app.json` + `eas.json` with dev / preview / production profiles. Proposed identifiers — **confirm before init, painful to change:** iOS bundle ID and Android package `com.paperkite.tucked`, app name "Tucked".
- **Sentry:** mobile + web projects on the free tier; DSN via env only. *(Blocked on accounts — see §8 Q4.)*

## 8. Questions before go-ahead

Q1 and Q2 change the data model; the rest gate external setup.

1. **Global person vs per-centre person.** Recommendation: `person` is global (one login per human, tied to the auth identity), while `person_role`, `household` and `child` are centre-scoped. An educator working at two centres or a parent with children at two Tucked centres keeps one account; each centre sees and revokes only its own roles/household memberships. The alternative (fully centre-scoped person) duplicates humans and makes the Phase 3 agency model harder. Confirm?
2. **Day boundary / overnight assumption.** I will assume no overnight care in v1: an attendance "day" is the centre-local calendar date (`timezone` stored per centre from migration 0001 — Ontario now, Manitoba-ready). Any centre in the discovery list that runs overnight care would change the attendance model — flag now if so.
3. **Store identifiers:** `com.paperkite.tucked` and app display name "Tucked" — confirm or correct before EAS init.
4. **Accounts inventory:** does a GitHub remote for this repo exist or should it stay local for now? Do you already have Expo, Supabase (org), and Sentry accounts to use — and per the cost model I'd stay **local-only Supabase** until the pilot; confirm no cloud project yet. Apple/Google developer accounts can wait until first device builds.
5. **Daily written record default** (config, not schema — schema keeps both): default scope **per centre** with a per-room toggle. Confirm.

## 9. Order of work and risks

Order: repo/tooling → ui-tokens → domain (rules + fixtures + tests) → supabase (migrations + RLS + pgTAP + seed) → mobile shell → web shell → CI → EAS/Sentry config.

Risks: Expo SDK / Supabase CLI versions move fast (pin exact versions in the first commit); Windows + Docker for local Supabase needs WSL2 working (verify early — it is the local-dev backbone); magic-link deep linking on the dev client is fiddly (budget a day, test on a real Android device first).

# 05 — The apps and the design system

*Every screen on both surfaces, what each one does, the offline model, and the complete design language.*

---

## Contents

1. [The web console](#1-the-web-console)
2. [The mobile app — Family mode](#2-the-mobile-app--family-mode)
3. [The mobile app — Room mode](#3-the-mobile-app--room-mode)
4. [The offline model](#4-the-offline-model)
5. [Design language — brand and voice](#5-design-language--brand-and-voice)
6. [Colour, including dark mode](#6-colour-including-dark-mode)
7. [Typography, space, shape, elevation](#7-typography-space-shape-elevation)
8. [Motion, components, iconography](#8-motion-components-iconography)
9. [Accessibility](#9-accessibility)
10. [The token file contract](#10-the-token-file-contract)

---

## 1. The web console

Next.js 16 App Router. Two route groups plus a public page:

- `(console)/…` — the authenticated supervisor and licensee console
- `/admin` — the PaperKite platform admin
- `/waiting-list` — public, unauthenticated, no account needed

### The shell

A left rail with **one fixed icon per regulated concept**. It auto-collapses below 1600 px (hovering peeks it open), pins by choice on wide screens, and becomes a drawer below 900 px. The collapse choice persists in `localStorage`. Top right of every page: the three-state appearance toggle (§6).

### The screens

| Route | What it does |
|---|---|
| **`/`** Today | The exception home. Room tiles with live counts and staff-in-ratio, then **Needs attention** — a single ordered list of every **Now** and **Due** signal in the centre, each with a link to the screen that fixes it. This is the screen a supervisor lives on |
| **`/attendance`** | The s. 72(3) register: arrivals, departures, absences, actual times, corrections with who/when/why. **No session noise.** CSV + print |
| **`/daily-record`** | The s. 37 record: today's composed draft, a **Moved on** badge when the day has changed since drafting, Redraft, and a PIN-gated close |
| **`/accidents`** | s. 36(4) reports and the parent acknowledgement that is the evidence |
| **`/serious-occurrences`** | s. 38: the 24-hour CCLS clock, filing, the CCLS-down fallback, updates, the anonymised posting, closing |
| **`/plans`** | ss. 39/39.1/52 plans, agreements, and the printable s. 43(3) allergy list |
| **`/illness`** | s. 36 exclusions, contact attempts, clearance, and public health orders with the advisor deadline |
| **`/menus`** | ss. 42–44: this week and next, posting, substitutions, feeding instructions, printable menu |
| **`/outdoor`** | s. 47: minutes per room and per child, shortfalls with reasons, exemptions |
| **`/medication`** | s. 40 authorisations and the administration register |
| **`/sleep-checks`** | s. 33.1: **What the day is owed** (position findings and long rests), the check register with CSV/print, and the written directions card with a PIN-gated form |
| **`/children`** + `/children/[id]` | s. 72(1) record items, immunisation, consents, plans, the s. 72(6) MOH subset |
| **`/messages`** | Announcements and family threads |
| **`/staff`** | ss. 53–64 files: what is missing across the centre, offence-declaration gaps, per-person files, printable |
| **`/fees`** | CWELCC cap, the fee schedule, charges/credits/payments, balances, CRA receipts, withdrawal notices |
| **`/handbook`** | s. 45: the 14 sections, publishing, who has acknowledged |
| **`/waitlist`** | s. 75.1: the ranked list (leadership only), offers and responses |
| **`/policies`** | ss. 46/48: the nine policies, publishing, who has read what |
| **`/compliance`** | Parts 4/10: the twelve recurring tasks, completions, the repair log |
| **`/admin`** | Platform: create a centre, set a plan, record a payment. **Never shows a child** |
| **`/waiting-list`** | Public. A family enters their code and sees **their own position and nothing else** |

### Where this is weak

- **Every page is a client component** that fetches on mount. Server components were the stated reason for choosing Next; almost nothing uses them. The console is effectively an SPA in App Router clothing.
- **No pagination anywhere.** The attendance register for a 40-child centre over a year is one query.
- **Printing is the browser's.** No PDF generation, and no single "give the advisor everything" bundle.
- **`/admin` is thin** — no centre list, no usage view, no support tooling.
- **No loading or empty-state discipline.** Some screens flash, some show nothing.

---

## 2. The mobile app — Family mode

Expo SDK 57, Expo Router. One binary, two modes, chosen by the role the signed-in person holds.

Four tabs:

| Tab | What it does |
|---|---|
| **Home** | For the selected child: status, **home unwell and when they can come back** (moved here from More), "not coming today" / "running late" before they arrive, today's story; any **Now** alert awaiting acknowledgement; announcements; the child switcher |
| **Log** | The day's care log — meals, naps, nappies, outdoor — read-only, calm, 12-hour times |
| **Messages** | Threads with the centre |
| **More** | Today's menu, fees and CRA receipts (across every household the adult belongs to), waiting-list place, the handbook, enrolment records, accident reports, sign-out |

Supporting screens: `enrolment/[childId]`, `handbook`, `messages/[id]`, `reports`, `sign-in`.

`ChildSwitcher` and `SwipeChildCard` handle multi-child families; `childTheme.tsx` gives each child a stable accent so a parent recognises their own child's card before reading the name.

### Where this is weak

- **None of the family screens has been tapped on a device.** They typecheck and their queries and RPCs are proven against a live database, but Expo web will not accept automated taps.
- **No photo upload and no photo feed**, so the "dated lifetime archive" promise has no surface.
- **Light-only.** The web console has dark mode; the Expo app does not, because its tokens are a TypeScript object and React Native has no CSS custom properties. It needs a theme context threaded through the component library, not a token swap.
- **No web fallback** for a family without a smartphone.

---

## 3. The mobile app — Room mode

PIN-locked, device-bound to a centre, offline-first. Five tabs:

| Tab | What it does |
|---|---|
| **Overview** | The room's day at a glance: who is present, staff in ratio, and — before the safe-arrival cutoff — who is still to arrive, after it who is not accounted for (the same rule as the Rooms chase list); open serious occurrences, today's accident reports |
| **Rooms** | Every room with live counts and ratio; the **safe-arrival chase list** after the cutoff; **what families told us today** (absence notices) |
| **Staffing** | Who is on shift and who counts toward ratio |
| **Evacuation** | **The screen the architecture exists for.** One tap from anywhere. Renders entirely from the device cache — every child, present/absent, room, allergies, medication, an emergency contact. **No sign-in wall, no network, ever.** Tap each child as you count them; anyone uncounted is visible by name; one button records the muster as a PIN-signed headcount |
| **More** | Settings, sign-out, device session |

`room/[id].tsx` is the room detail screen and by far the largest file in the app (~1,300 lines): the sign-in board, the care-log grid, the nap board, bulk logging, and the medication list.

### Where this is weak

- **`room/[id].tsx` is ~1,300 lines** and does too much. It is the highest-risk file in the repository for a regression nobody notices.
- **The nap board's offline fallback is back-only.** It reads `sleep_placement_options` live, so a child with a physician's side-lying direction cannot be laid on their side without a connection ([02 §6](02-features-daily-care.md)).
- **The evacuation cache is per-device** and there is no priming step, no staleness indicator, and no warning when it is empty.
- **`debug.tsx` still references Gilroy**, the retired typeface.

### The centre's day, everywhere

Every `date` column in the schema — `attendance_date`, `log_date`, `story_date`, `notice_date` — is filed under the **centre-local** day, derived in SQL with `at time zone centre.timezone`. A client asking for "today" has to ask for the same day, so both apps use `packages/domain/src/localDate.ts` (`localDateISO`, `localMinutes`, `localWeekStartISO`, `addDaysISO`, `isoWeekdayOf`), never `new Date().toISOString().slice(0, 10)`.

Until 2026-09-13 that pattern was in 24 places. From 8 p.m. in Toronto (7 p.m. in winter) the UTC date is tomorrow, so the family Home asked for tomorrow's story and showed "The day's story arrives at pick-up time" at exactly the hour parents read it; the day log emptied; and a room educator's story note after 8 p.m. saved onto tomorrow's story. `loadRoomDay()` fetched the centre's timezone and computed today from UTC on the line above. Where the timezone comes from: the console's `useConsole().centre.timezone`, family mode's `useFamily().selected.timeZone`, and room mode's `loadRoomDay().centre.timezone`.

---

## 4. The offline model

Room mode is offline-**first**, not offline-tolerant, because the Licensing Manual requires attendance to work off-site.

### How it works

- **Store:** an AsyncStorage command queue (`apps/mobile/src/lib/queue.ts`), plus the evacuation cache.
- **Write path:** every regulated write becomes a **command** with a device timestamp and the recording PIN, persisted before anything is attempted, then replayed **in order** when the network returns.
- **Sync evidence:** `offline_recorded_at` and `offline_synced_at` are stored on the row and are part of the audit trail. A record made in a basement and synced two hours later says so.
- **Refusals from the far side are visible.** If the server rejects a command — an excluded child, an expired medication — the queue surfaces it rather than silently dropping it.
- **Corrupt storage is survivable.** The queue recovers rather than wedging.

### Two real bugs found and fixed here

1. **`flushQueue` skipped `persist()` and `notify()` on the network break.** The loop's own persist/notify sat after the branch, so breaking past them left the attempt count unsaved and the screen showing a stale "syncing…" with nothing to say the flush had stalled. Found by reading.
2. **`flushQueue` returned immediately when a flush was in flight**, so `await flushQueue()` meant nothing — a caller could not tell a finished flush from a skipped one. Callers now **join** the in-flight promise. Found by testing.

15 automated tests cover ordering, persistence across a restart, offline timestamps, visible refusals and corrupt storage.

### Where this is weak

- **A lost response on a flaky connection can duplicate a regulated record.** The queue only learns "network error" — it cannot distinguish "the write never arrived" from "the write succeeded and the reply was lost", so it retries, and the RPCs carry no idempotency key. **Marginal signal is the condition that produces this**, which is exactly what a basement gives you. The fix is a client-generated command id unique per centre on the write RPCs — roughly thirty functions, which is why it is written down rather than done speculatively.
- **The runbook has never been run on hardware.** See [06](06-gaps-risks-and-roadmap.md).
- **Family mode has no queue** — it is a read-only cache, by design.

---

## 5. Design language — brand and voice

### The mark

A swaddled, sleeping baby in soft 3D "clay": rounded, plush, gently lit, closed eyes, a small contented smile, a crescent-moon curl, a pale blue heart on the blanket. Everything in the product should feel like that mark.

| The mark is… | So the product is… |
|---|---|
| Asleep, at peace | **Quiet by default.** One story a day; loud only when it matters *now* |
| Swaddled, held | **Contained.** Every record in its place; nothing lost, nothing leaking |
| Soft, rounded, matte | Generous radii, soft shadows, no hard edges, no gloss, no decorative gradients |
| One blue, plus white | **One accent colour.** Neutral canvas; blue means Tucked, green means fine, red means act now |
| A little heart, not a badge | Warmth without cuteness overload. **No mood emoji, ever** |

### Logo rules

- **Preferred grounds:** white, canvas, or mist. The mark's edges are brand blue, so it disappears on blue — if it must sit on blue, keep it in a white or mist rounded container.
- **Clear space:** ≥ 10 % of the mark's width on all sides.
- **Minimum size:** 24 px rendered; below that use the simplified silhouette.
- **Never** recolour, rotate, stretch, outline, add effects, place on photography, or pair with another mascot or emoji.
- **Wordmark:** "tucked" in **Baloo 2 Bold, all lowercase**, in Ink (preferred) or Blanket Blue on light grounds, white on dark. Lowercase matches the bedtime softness. Do not track lowercase.

### Voice and tone

- **Plain, specific, calm.** "Maya was found on their front at a sleep check" — not "sleep position anomaly detected".
- **Say the regulation when it helps**, in parentheses: "(s. 33.1)". A supervisor needs to know which rule they are meeting.
- **Refusals explain what has to be true first.** Every error message in [02](02-features-daily-care.md) and [03](03-features-records-and-obligations.md) tells the reader the next action, not just the failure.
- **Never blame the user.** "Record the physician's direction first" — not "invalid input".
- **Names, not ids**, in anything a human reads.
- **No exclamation marks, no emoji, no cheerleading.**

### The words the app must use — binding

Ontario's vocabulary is not a style preference. A program advisor reads these words; using the wrong one signals that the product does not know the regulation. `packages/domain/src/i18n/en-CA.ts` holds the strings.

| Use this | Not this | Why |
|---|---|---|
| **Licensee** | owner, company | The legal holder of the licence |
| **Supervisor** | director, principal | Ontario's title for the person in charge of a centre |
| **RECE** | teacher, ECE | Registered Early Childhood Educator, a College member |
| **Program advisor** | inspector | The Ministry official who inspects and licenses |
| **CCLS** | — | Child Care Licensing System, where serious occurrences and the annual survey are filed |
| **Age group** / licensed age group | class, room | The licence is issued per age group |
| **Parent** | guardian | The regulation says parent; it includes guardians |
| **Children's record** | file, profile | The regulated term (s. 72) |
| **Daily written record** | daily log, diary | The regulated term (s. 37) |
| **Serious occurrence** | incident | A defined, reportable category (s. 38) |

Canadian spelling throughout: *centre*, *authorised*, *anonymised*, *behaviour*, *paediatrics*.

### Licensed age groups (Schedule 1) — the room presets

These numbers are **regulation, not configuration**. They live in `packages/domain/src/ageGroups.ts` and every value is pinned by a `sched1_*` test. Do not edit without citing the amended Schedule.

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

## 6. Colour, including dark mode

Sampled from the logo. Every value contrast-checked; **no colour is added without a computed ratio.**

### Brand palette (light)

| Token | Hex | Use |
|---|---|---|
| `blue.500` **Blanket** | `#3E89E8` | The brand colour. Primary buttons, active states, large-text links |
| `blue.600` **Deep** | `#2166C8` | Pressed states, text links, icons that must meet 4.5:1 |
| `blue.700` | `#1C5AB5` | High-emphasis blue text, focus rings |
| `blue.100` **Heart** | `#A0C8F8` | **Decorative only** (1.73:1) — never text |
| `blue.50` **Mist** | `#CFE2FA` | Tinted surfaces: selected cards, info banners, stat tiles |
| `ink` | `#17325C` | Primary text. A warm navy, not black — 12.75:1 on white |

### Neutrals and semantics (light)

`canvas #EFF4FB` · `surface #FFFFFF` · `surface-sink #F9FBFE` · `line #D9E2EF` · `slate #46587A` (7.4:1) · `slate.muted #7C8AA0` (large/secondary only)

**Green = fine, red = act now.** Amber exists only for "due soon" — use it sparingly or it becomes noise.

| Token | Hex | On white |
|---|---|---|
| `ok` / `ok.wash` | `#177243` / `#C9EAD7` | 5.96:1 |
| `now` / `now.wash` | `#B02A20` / `#F9D9D3` | 6.57:1 |
| `due` / `due.wash` | `#96470A` / `#FAE3C2` | 6.56:1 |

Every semantic colour passes 4.5:1 **on its own wash** as well as on white, because pills sit on both.

### Rules

- **Red is sacred.** Red appears only when a human must act now. Never for validation nitpicks, never decoratively. If everything is red, the missed-sick-child failure mode returns.
- Body text is `ink` or `slate` — **never `blue.500`** (3.53:1). Blue text is links and actions only, at `blue.600`+ or ≥ 18 pt.
- **One accent per screen.** If a screen needs two competing accents, the screen is doing too much.

### Dark

Three states, because "dark mode" has three:

| State | How it is expressed | Wins over |
|---|---|---|
| Follow the device | **no** `data-theme` attribute — the default | — |
| Light | `data-theme="light"` on `<html>` | a device set to dark |
| Dark | `data-theme="dark"` on `<html>` | a device set to light |

The control sits **top right** of every console page, the sign-in screen and the public pages — somebody signing in at six in the morning in a dark room should be able to fix that *before* they have an account. The choice is stored in `localStorage` and re-applied by an inline script in the root layout **before first paint**.

**Dark values are chosen for contrast on the dark canvas, not inverted.** `#17325c` ink becomes a pale blue-white; the brand blues lift so a link still reads as a link; each semantic colour is measured against **its own wash**. Measured on the built page:

| Pair | Ratio | |
|---|---|---|
| `ink` on `surface` | 13.4:1 | ✅ |
| `ink` on `canvas` | 15.2:1 | ✅ |
| `slate` on `surface` | 8.8:1 | ✅ |
| `slate-muted` on `surface` | 5.5:1 | ✅ |
| `blue.500` link on `surface` | 7.5:1 | ✅ |
| `ok` / `now` / `due` on their washes | 7.9 / 7.1 / 7.7:1 | ✅ |

**The table is not transcribed by hand** — it is asserted in `packages/ui-tokens/test/tokens.css.test.ts`, along with "every light colour is redefined in both dark blocks", "the two dark blocks are identical", and **"dark is never a downgrade"** ([04 §12](04-data-security-and-platform.md)).

### The clay foot — the one thing the swap did not get for free

`--clay-foot` and `--clay-foot-quiet` are the side wall of an extruded clay control, and must be **darker than the face above them**. They used to be steps of the brand ramp (`blue-700` under a primary button, `blue-100` under a quiet one) — correct in light and impossible in dark, because **the ramp inverts**: `blue-700` is the high-emphasis text colour, so on a dark canvas it becomes the *lightest* blue in the set. Every foot came out lighter than its own face: a row of buttons lit from underneath.

> **A ramp that changes direction cannot be borrowed for a shadow.** The foot is named for its job instead, and tested in both palettes.

### Native controls follow `color-scheme`, and only if you declare it

Every palette block sets it. `<select>` is styled alongside `input` and `textarea` — it was left out originally and **nobody could tell in light**, because the browser's own control is near enough to white. Dark rendered it as a `#3b3b3b` box from no palette of ours, sitting between two correctly themed inputs.

> **If a control looks right in light, that is not evidence it is styled.**

### Where this is weak

- **The mobile app is light-only.**
- **`--clay-highlight` at 8 % in dark is close to invisible** on some panels; it is correct rather than beautiful.
- **The tile trio was measured and fixed once** (dark spread 0.150 → 0.036) but nothing re-measures when a new tinted surface is added.

---

## 7. Typography, space, shape, elevation

### Typeface

**Baloo 2** (display, headings, the wordmark) + **Nunito** (body, UI). Both OFL — free, embedding included. Web serves variable woff2; mobile uses fontTools-instantiated static TTFs.

The retired Gilroy files remain archived in `assets/fonts/`; nothing loads them.

### Space — a 4 pt grid

`xs 4` · `sm 8` · `md 12` · `base 16` · `lg 20` · `xl 24` · `2xl 32` · `3xl 40` · `4xl 48` · `5xl 64` · gutter 24 · card padding 16 · card gap 12

### Radius — generous, claymorphic

`sm 12` · `md 16` · `lg 18` · `card 22` · `xl 24` · `tile 28` · `pill 999`

### Elevation — clay, not paper

Surfaces are **soft solids**, never flat paper shadows. Each level is a thick inner top highlight (light hits the top of the form), an inner bottom shade (the form curves away), and a layered ink-tinted drop:

- `--shadow-resting`, `--shadow-raised`
- `--clay-highlight` / `--clay-highlight-soft` — the light on the top edge
- `--clay-foot` / `--clay-foot-quiet` — the side wall
- `--clay-glow` — the warm lift under a primary press (a deeper drop in dark, not a brighter halo)

**In dark, shadows barely work** — you cannot cast a dark shadow on a dark canvas — so surfaces separate by lightness instead. Dark deliberately separates ~15 % more than light, and that is correct rather than a bug.

### Neumorphism — the cousin, used sparingly

Clay is a solid form sitting **on a different-coloured ground**: one top highlight and one ink-tinted drop. Neumorphism is a form pressed **out of or into a ground of the same colour**, which needs *two* shadows — a lit face toward the light and a shaded face away from it.

| Token | What it is |
|---|---|
| `--neu-light` / `--neu-shade` | The lit and shaded faces. In dark the light dims to 5.5 % white and the shade goes near-black |
| `--shadow-neu-raised` | Pressed out of the ground |
| `--shadow-neu-inset` | Carved into it — a field, a read-only panel |
| `--shadow-neu-subtle` | Touchable without announcing itself |

**The light sits top-left, always, everywhere.** A screen where some controls are lit from the left and others from the right does not read as soft, it reads as broken — and it is invisible in review, because each control looks fine on its own. Three tests per palette hold the direction, the lit/shaded pairing, and the fact that an inset is drawn `inset`.

**The rule that keeps it honest: neumorphism carries no meaning.** An element the same colour as its ground cannot carry contrast, so it is never the only thing saying something. Where it is allowed:

| Allowed | Why it is safe |
|---|---|
| `input`, `select`, `textarea` | The `--line` border stays. A field boundary made only of soft shadow is exactly the accessibility complaint neumorphism has earned; the line is the honest edge (1.4.11), the shadow is the depth |
| `.theme-toggle` | Background is `--canvas`, deliberately the same colour as the page, which is the whole premise. Its label still measures 6.5:1. Pressing it swaps the raise for the inset |
| `.sidebar nav a[aria-current='page']` | Reads as pressed *into* the rail. The blue tint stays — a state told only in shadow is a state many people cannot see, and `aria-current` plus the visible label are what carry it |
| `.well` | Read-only prose a reader dwells on: a published policy, a composed story draft |

Where it is **not** allowed: a primary button, a Now pill, or anything holding regulated content, where the clay drop is doing real separation work.

**It mirrors to React Native**, unlike the rest of elevation. RN ≥ 0.76 takes the `boxShadow` shorthand with multiple shadows and `inset` on both platforms, so `neu` in `tokens.ts` is the same string — the mobile `Field` is the same carved well. The RN face carries the light values only, because the app is light-only.

---

## 8. Motion, components, iconography

### Motion

`--motion-fast 120ms` · `--motion-base` · squish curves.

Clay is **squishy, not plastic**: the press lands instantly, the release springs back with a soft overshoot.

```css
transition: transform 340ms cubic-bezier(0.3, 1.8, 0.45, 1);
```

Sparkles and click pulses are a deliberate warmth device — but **serious zones stay quiet**: anything containing a `.pill.now`, and every text field, spawns nothing. Every helper refuses to spawn under `prefers-reduced-motion`.

### Components

Pills (`ok` / `now` / `due`), cards, tiles, the top bar, the rail, quiet buttons, primary buttons, tables, the PIN field. Tap targets are 48 px minimum — with one deliberate exception: the appearance toggle overrides down to 38 px, because **it is a preference, not an action, and it should not compete with the Now pills.**

### Iconography

**One fixed icon per regulated concept**, used everywhere that concept appears — the rail, the page header, the console home. Lucide on web, Ionicons on mobile. An icon never changes meaning between screens.

### Where this is weak

- **Two icon libraries** for one product; a concept's icon is chosen twice and can drift.
- **Sparkles are charming and untested** — no test asserts they stay out of serious zones.

---

## 9. Accessibility

The checklist the design language holds itself to:

- **Contrast**: 4.5:1 body, 3:1 large text and UI. Machine-tested in both palettes.
- **Tap targets** ≥ 48 px, with the single stated exception above.
- **Focus rings** on every interactive element: `2px solid var(--blue-700)`, `outline-offset: 2px`.
- **`prefers-reduced-motion`** respected by every decorative helper.
- **Colour is never the only signal** — every pill carries a word.
- **Theme-aware**: three states, no flash, `color-scheme` declared so native controls follow.
- **Semantic HTML** and real `<label>` elements.

### Where this is weak

- **No screen-reader pass has been done** on either app.
- **No keyboard-only pass** on the console.
- **The accessibility gate named in the build plan has never been run** as a formal check — contrast is tested, everything else is convention.

---

## 10. The token file contract

Two faces, one palette:

- **`packages/ui-tokens/src/tokens.ts`** — the React Native face. TypeScript objects consumed by StyleSheet. **Light only.**
- **`packages/ui-tokens/css/tokens.css`** — the web face. CSS custom properties, defined **three times**: `:root` (light), `@media (prefers-color-scheme: dark) :root:not([data-theme='light'])`, and `:root[data-theme='dark']`.

**The palette mirrors between the two faces; elevation does not.** Clay is shadows and highlights on the web and StyleSheet shadow objects in React Native, so `--clay-*`, `--scrim` and `--shadow-*` live only in the CSS file.

> **Add a colour to all three blocks or to none.** A reader who picked dark will otherwise meet a light value on some screen. This is asserted by a test, not by discipline.

### Where this is weak

- **The two faces are compared by a human, not a test.** The CSS blocks are tested against each other; nothing compares `tokens.ts` to `tokens.css`.
- **`tokens.ts` has no dark palette**, which is what blocks mobile dark mode.

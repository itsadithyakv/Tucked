# Tucked — design language

*The visual and verbal identity of Tucked. Derived from the logo ([assets/logoTuckedNoBG.png](../assets/logoTuckedNoBG.png)), the Gilroy typeface family ([assets/fonts/](../assets/fonts/)), and the product principles in [tucked-build-prompt.md](tucked-build-prompt.md) §3. Colour values below were sampled directly from the logo file; contrast ratios were computed, not estimated.*

---

## 1. Brand essence

**Tucked** — as in *tucked in*: looked after, everything in one calm place.

The logo is a swaddled, sleeping baby rendered in a soft 3D "clay" style: rounded, plush, gently lit, with closed eyes, a small contented smile, a crescent-moon curl, and a pale blue heart on the blanket. Everything in the product should feel like that mark:

| The mark is… | So the product is… |
|---|---|
| Asleep, at peace | **Quiet by default.** One story a day; loud only when it matters *now*. |
| Swaddled, held | **Contained.** Every record in its place; nothing lost; nothing leaking. |
| Soft, rounded, matte | Generous radii, soft shadows, no hard edges, no gloss, no gradients-for-decoration. |
| One blue, plus white | **One accent colour.** Neutral canvas; blue means Tucked; green means fine; red means act now. |
| A little heart, not a badge | Warmth without cuteness overload. **No mood emoji, ever** (product rule). |

Two sentences the brand must always be able to say, from the plan:

> **Calm for parents. Boring inspections for operators.**

Every design decision should survive the question: *does this make the day calmer, or louder?*

---

## 2. Logo

### Files

| File | Use |
|---|---|
| `assets/logoTuckedNoBG.png` (1169 × 1169, transparent) | Master mark. Source for all derived sizes. |

Derive and commit as needed: app icon (1024 × 1024 on solid ground — iOS requires no transparency), Android adaptive icon foreground, favicon set, notification small icon (Android requires a flat white silhouette — trace a simplified single-colour outline of the swaddle shape; the full-colour mark will not render in the status bar).

### Usage rules

- **Preferred grounds:** white `#FFFFFF`, canvas `#F7F9FC`, or mist `#EAF2FD`. The mark's edges are brand blue, so it disappears on blue grounds — if it must sit on blue, keep it inside a white or mist rounded container.
- **Clear space:** keep a margin of at least 10% of the mark's width on all sides.
- **Minimum size:** 24 px / 24 pt rendered. Below that, use the simplified silhouette.
- **Never:** recolour, rotate, stretch, outline, add effects, place on photography, or pair with any other mascot or emoji.

### Wordmark

Set **"tucked"** in **Gilroy Bold, all lowercase**, in Ink `#17325C` (preferred) or Blanket Blue `#3E89E8` on light grounds; white on dark/blue grounds. Lowercase matches the bedtime softness of the mark. Letter-spacing: default (do not track lowercase). Lock-up: mark left of wordmark, gap = 40% of mark width, wordmark cap-height ≈ 42% of mark height. "by PaperKite" credit, when used, is Gilroy Medium at 35% of the wordmark size in Slate.

---

## 3. Colour

Sampled from the logo: blanket body averages `#3E89E8` (peak `#4090F0`), facial features and shading average `#1C5AB5`–`#2868C8`, the heart is `#A0C8F8`, the face `#F0F0F0`–`#F8F8F8`.

### Brand palette

| Token | Hex | Sampled from | Use |
|---|---|---|---|
| `blue.500` **Blanket** | `#3E89E8` | blanket body | The brand colour. Primary buttons, active states, links on large text, brand moments. |
| `blue.600` **Deep** | `#2166C8` | features/shading | Pressed states, text links, icons on white that must meet 4.5:1. |
| `blue.700` | `#1C5AB5` | deep shading | High-emphasis blue text, focus rings. |
| `blue.100` **Heart** | `#A0C8F8` | the heart | Decorative only (illustrations, progress fills, selected-card washes). Never text. |
| `blue.50` **Mist** | `#EAF2FD` | derived | Tinted surfaces: selected cards, info banners, avatar grounds. |
| `ink` | `#17325C` | derived (navy of the blues) | Primary text. A warm navy, not black — softer, still 12.75:1 on white. |

### Neutrals

| Token | Hex | Use |
|---|---|---|
| `canvas` | `#F7F9FC` | App background. Cool near-white, never pure grey. |
| `surface` | `#FFFFFF` | Cards, sheets, inputs. |
| `line` | `#E3E9F2` | Hairline borders, dividers. |
| `slate` | `#4B5C74` | Secondary text (6.81:1 on white). |
| `slate.muted` | `#7C8AA0` | Placeholders, disabled text, timestamps. Large/secondary contexts only. |

### Semantic colours

Calm surfaces, one accent: **green = fine, red = act now** (build prompt §3.2). Amber exists only for "due soon" compliance states — use it sparingly or it becomes noise.

| Token | Hex | On white | Use |
|---|---|---|---|
| `ok` | `#1E7A46` | 5.35:1 | Ratio OK, record closed, synced, acknowledged. |
| `ok.wash` | `#E7F4EC` | — | Backgrounds for fine-states. |
| `now` | `#C2362B` | 5.45:1 | The **Now** channel, ratio breach, overdue serious-occurrence clock, hard blocks (restricted pickup). White text on `now` passes (5.45:1). |
| `now.wash` | `#FBECEA` | — | Now-item backgrounds. |
| `due` | `#B45309` | 5.02:1 | Expiring credentials, sleep check due, unclosed daily record. |
| `due.wash` | `#FBF1E4` | — | Due-state backgrounds. |

### Rules

- **Red is sacred.** Red appears only when a human must act now. Never for validation nitpicks, never decoratively. If everything is red, the missed-sick-child failure mode returns.
- Body text is `ink` or `slate` — never `blue.500` (3.53:1, fails 4.5:1). Blue text is links/actions only, at `blue.600`+ or ≥ 18 pt.
- White text on `blue.500` (3.53:1) is acceptable only for large button labels (≥ 18 pt / 14 pt bold); prefer `blue.600` fills for standard buttons so labels pass comfortably.
- `blue.100` (Heart) is 1.73:1 — decorative only, enforced in review.
- One accent per screen. If a screen needs two competing accents, the screen is doing too much.
- **Dark mode is deferred** (not a Phase 1 promise). Structure tokens as semantic names (`canvas`, `surface`, `ink`) so a dark theme is a token swap later, not a rewrite.

---

## 4. Typography — Gilroy

### Files and formats

| Weight | Mobile (Expo) | Web (Next.js) |
|---|---|---|
| Light | `Gilroy-Light.ttf` | `Gilroy-Light.woff2` |
| Regular | `Gilroy-Regular.ttf` | `Gilroy-Regular.woff2` |
| Medium | `Gilroy-Medium.ttf` | `Gilroy-Medium.woff2` |
| Bold | `Gilroy-Bold.ttf` | `Gilroy-Bold.woff2` |
| Heavy | `Gilroy-Heavy.ttf` | `Gilroy-Heavy.woff2` |

The `.ttf` files were converted from the `.woff2` sources with fontTools (same glyph tables, decompressed) because **React Native cannot load woff2** — Expo's `useFonts` needs ttf/otf. Web keeps woff2 (smallest). ~120–140 KB per ttf weight, 556 glyphs each, covering extended Latin — **fr-CA accents (é è à ç ô î û ë ï) are covered**, so the Quebec preset does not need a font change.

**⚠ Metadata gotcha (verified in the files):** each file declares itself as its own family (`Gilroy-Bold`, `Gilroy-Light`, …) with an internal weight class of 400. Weight-based selection will silently fail:

- **React Native:** select by `fontFamily` name only. Load each file under its own key (`Gilroy-Bold`, etc.) and never set `fontWeight` alongside — on Android, `fontWeight` on a custom family can drop to a fallback. Expose styles from `ui-tokens` (e.g. `type.title`) so screens never hand-pick fonts.
- **Web:** declare all five files under **one** `font-family: 'Gilroy'` with explicit `font-weight: 300/400/500/700/800` in each `@font-face`, `font-display: swap`. Then normal `font-weight` CSS works. Self-host — no Google Fonts, no external requests (privacy stance, §7 of the build prompt).
- Fallback stacks: mobile — system default (SF Pro / Roboto); web — `'Gilroy', -apple-system, 'Segoe UI', Roboto, sans-serif`.

There is **no italic** (none supplied; faux italic is banned). Emphasis = weight or colour, never slant. Verify tabular figures (`tnum`) before shipping time columns (attendance, sleep checks); if Gilroy's default figures are proportional, times will jiggle — fall back to the platform's tabular numerals for dense time tables.

**Licensing:** Gilroy is a commercial typeface by Radomir Tinkov (only Light and ExtraBold are free-for-personal-use). Before store submission, hold a licence tier that covers **app embedding + webfont** use. One-time cost; budget line lives in [cost-model.md](cost-model.md).

### Type scale

Mobile in pt, web in px (same numbers). Line height ≈ 1.4 for body, tighter for display.

| Style | Weight | Size / line | Use |
|---|---|---|---|
| `display` | Heavy | 32 / 38 | Big numerals and moments: ratio "3 : 10", evacuation headcount, onboarding. |
| `title` | Bold | 24 / 30 | Screen titles ("Toddler room"). |
| `heading` | Bold | 20 / 26 | Card titles, section heads. |
| `subheading` | Medium | 17 / 24 | Child names in lists, key-value labels. |
| `body` | Regular | 16 / 24 | Everything readable. The daily story is set in this. |
| `label` | Medium | 15 / 20 | Buttons, tabs, chips. Sentence case — never all-caps buttons. |
| `caption` | Regular | 13 / 18 | Timestamps, metadata, photo dates. `slate.muted`. |
| `overline` | Medium | 12 / 16, +4% tracking, caps | The only all-caps style: tiny category labels ("NOW", "SLEEP CHECK"). |

Rules: Heavy is display-only — never at body sizes. Light is reserved for large decorative numerals (32 pt+) and marketing; never in the app's working UI. Minimum UI text size 13. Family app body text respects the OS text-size setting (Dynamic Type / font scale) — parents at pickup, one-handed, in daylight.

---

## 5. Space, shape, elevation

**Spacing** — 4-pt grid: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Screen gutter 16 (mobile) / 24 (web). Card padding 16. Gap between cards 12.

**Radius** — generous, echoing the mark's roundness: `sm 8` (chips, inputs), `md 12` (buttons), `lg 16` (cards — the default), `xl 24` (sheets, modals), `pill 999` (status pills, avatars). Nothing square-cornered except full-bleed dividers.

**Elevation** — soft and low, like the logo's matte lighting. Two levels only: resting cards `0 1px 3px rgba(23,50,92,0.08)`, raised sheets/menus `0 8px 24px rgba(23,50,92,0.14)`. Never harsh black shadows; shadow colour is always ink-tinted.

**Touch targets** — ≥ 44 × 44 pt, per the quality gates. Sign-in rows, sleep-check confirms and evacuation controls should be far larger — these get used with a toddler on one hip.

---

## 6. Motion

Purposeful only; `prefers-reduced-motion` honoured on both platforms (build prompt §3.6).

| Token | Duration / easing | Use |
|---|---|---|
| `fast` | 120 ms, ease-out | Press feedback, toggles, checkmarks. |
| `base` | 200 ms, ease-in-out | Card expansion, tab changes, sheet content. |
| `gentle` | 300 ms, gentle spring (no overshoot > 4%) | Sheets sliding in, the daily story opening. |

No looping animations, no confetti, no bounce-for-delight. The one sanctioned flourish: the daily story may open with a single `gentle` settle — the "tucking in". Skeletons hold exact layout (no shift — §3.5); shimmer at low contrast (`line` on `canvas`), disabled under reduced motion.

---

## 7. Components

**Smart cards** (§3.3) — every card answers: *what changed, what needs attention, what's next, what can I do here.* Anatomy: overline category → heading → body → actions. One primary action max; the rest behind the card tap.

**Legible actions** (§3.4) — buttons name the deed and the object: `Sign in Maya`, `Record sleep check`, `Close today's record`, `Send accident report`. Never `OK` / `Submit` / `Done` on anything that becomes a regulated record. Anything regulated gets a confirm step showing exactly what will be saved.

**Now / Later, visually:**
- **Now** items: `now.wash` ground, `now` left rail (3 pt), overline "NOW", never dismissible by swipe — acknowledged by an explicit labelled action, timestamp recorded (delivery evidence is a compliance feature).
- **Later** items never use red or amber anywhere in their layout. The daily story is set like a letter — `body` text on `surface`, photos inline with their capture dates in `caption` — not a social feed. No like buttons, no reactions.

**Status pills:** `ok`/`due`/`now` washes with matching text; icon + word, never colour alone (colour-blind safe).

**Every state designed** (§3.5): loading without layout shift; empty-but-valid ("No medication scheduled today" is a good state and looks like one — mist illustration, not a sad face); offline (persistent quiet banner: "Working offline — 3 items will sync", `slate` not red — offline is *normal*, not an error); denied; pending acknowledgement; success showing the saved record itself.

**Forms:** labels above fields (never placeholder-as-label), optional fields marked "(optional)" — the consent rules in s. 73 make optionality a legal property, so it must be visually explicit.

---

## 8. Iconography & illustration

**Icons: Lucide** (decided, §3.7). Stroke 2 px at 24; sizes 16 / 20 / 24. Colour: `slate` default, `ink` active, semantic colours for status only. Every regulated concept keeps one fixed icon across the product (sleep check `moon`, medication `pill`, accident `bandage`, attendance `door-open`, evacuation `siren`, credential `badge-check`) — a program advisor watching a supervisor navigate should see the same symbol every time.

**Illustration:** the soft-3D clay style of the mark is reserved for brand moments — onboarding, empty states, the graduation export cover, the website. Rounded geometry, matte finish, brand blues + white only. Never illustrate alarming content (no clay injuries); serious flows use plain text and icons. In-app spot illustrations should be few, small, and reused.

**Photography:** parents' photos of their children are the product's only photography. The UI never competes with them — chrome around photos is white/canvas, dates always visible, full-resolution download one tap away.

---

## 9. Voice and tone

The written interface is the product's personality. It is a calm, competent educator at pickup time — warm, brief, specific, never chirpy.

**Rules**
- **Ontario's words, exactly** — the table in [tucked-ontario-requirements.md](tucked-ontario-requirements.md) §0 is binding: *supervisor, RECE, program advisor, licensee, age group, children's record, daily written record, serious occurrence.*
- **Canadian spelling:** centre, enrolment, colour, licence (noun) / license (verb), authorised.
- **Dates** `29 Aug 2026`; **24-hour times for staff, 12-hour for families**; currency CAD.
- Specific over generic: "Maya is napping — since 12:40" not "Nap time logged!".
- No exclamation marks in the working UI; at most one in onboarding. No emoji anywhere in product copy.
- Urgent copy is instructive, complete and unambiguous: what happened, what to do, who to reach. "Maya has a fever of 38.9 °C. Please call Maple Leaf Early Learning at (416) 555-0100 to arrange pickup."
- Errors: say what happened and the way out; never blame; never "Oops". Offline is stated as a status, not apologised for.
- Empty states state the fact and the next action: "No children signed in yet. Sign-ins appear here as families arrive."
- The auto-drafted daily story reads like a note from the educator, first person plural: "We spent the morning outside — Maya loved the leaf pile. Lunch went well (most of it eaten), and she napped 12:40–2:10." The educator's own note always sits on top, untouched.

**Never in copy:** "Awesome!", "Yay!", "Uh oh", "Kiddo", "Littles", mood descriptors as data ("had a sad day"), any AI-voice tell ("As an assistant…"). Machine-translated content is labelled as such (Phase 2 rule).

---

## 10. Accessibility checklist

From the quality gates (build prompt §12), restated as design law:

- Text contrast ≥ 4.5:1 (large text ≥ 3:1) — the palette above passes by construction; new colours must be checked before entering `ui-tokens`.
- Touch targets ≥ 44 pt; critical care actions larger.
- Never colour alone: every status has icon + word.
- Screen-reader labels on every control, in product language ("Sign in Maya, button").
- Respect OS text scaling in Family mode; Room mode may pin sizes for layout-critical grids but must pass at 200% on key flows.
- `prefers-reduced-motion` disables all non-essential motion, both platforms.
- Focus states on web: 2 px `blue.700` ring, 2 px offset, on everything interactive.

---

## 11. Token file contract

`packages/ui-tokens` is the single source of truth and ships two faces of the same values: TypeScript objects for React Native `StyleSheet`, CSS custom properties for the web console (no Tailwind, no CSS-in-JS — decided). Anything visual not expressible as a token belongs in a shared component, not in a screen. If a screen hard-codes a hex, a radius or a font name, the review rejects it — that is how the design language survives being built by one person at speed.

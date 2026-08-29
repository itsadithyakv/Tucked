# Decisions

*Why, not what. Newest at the top. A decision recorded here is settled — reopen it only with new evidence, and record the reopening here too.*

## 2026-08-29 — Phase 0 build

- **Versions pinned by the official scaffolders, not memory:** Expo SDK 57 (RN 0.86, React 19.2, TS 6), Next.js 16.3. `create-expo-app`/`create-next-app` ran with `--no-install`/`--skip-install`; the lockfile is the authority.
- **Session storage on mobile is AsyncStorage for now** — SecureStore caps values at 2 KB (smaller than a session payload). TODO(security) before any pilot: encrypt the AsyncStorage payload with a key held in expo-secure-store. Storage is platform-gated: on web/Node prerender supabase-js picks its own (the web static export crashed otherwise).
- **Sentry wiring deferred until accounts exist.** Local-only decision means no DSN; the dependency lands together with `eas init`. The scrubbing rules (no request bodies, no child names) are already recorded and non-negotiable.
- **`@typescript-eslint/no-require-imports` is off for `apps/mobile` only** — Metro requires static `require()` for fonts and images.
- **Web console uses a lazy `getSupabase()`** — Next prerenders client components in Node, so nothing may throw at module scope.
- **App icons are generated from the master logo** (Pillow script): iOS icon on white, Android adaptive foreground at 58% for the safe zone, monochrome from the alpha channel, mist splash/adaptive background `#EAF2FD`.

## 2026-08-29 — Phase 0 go-ahead answers (from the founder)

- **`person` is global; roles, households and children are centre-scoped.** One login per human tied to the auth identity; `person_role` and `household_member` carry the centre scoping. An educator at two centres or a parent with children at two Tucked centres keeps one account; each centre sees and revokes only its own rows. Chosen for the Phase 3 agency model.
- **Attendance is day-bounded.** No overnight care in v1: an attendance day = the centre-local calendar date. `timezone` column on `centre` from migration 0001 (Ontario now, Manitoba-ready). Reopen only if a discovery centre runs overnight care.
- **Store identifiers: `ca.tucked.app`** (iOS bundle ID and Android package), display name "Tucked". Brand-first namespace tied to tucked.ca, not the company namespace.
- **Local-only, no remote.** Supabase runs via CLI/Docker at $0; the git repo stays on this machine. Cloud project and GitHub remote wait for their cost-model triggers.

## 2026-08-29 — Phase 0 planning

- **Local-only Supabase until a pilot centre exists.** Development runs entirely on the Supabase CLI stack (Docker). No cloud project, no monthly cost, offline-capable dev. Trigger to change: first real centre's data → Pro tier for backups/no-pause ([cost-model.md](../references/cost-model.md) §5).
- **Web console hosts on Cloudflare Pages, not Vercel Hobby.** Vercel's free tier prohibits commercial use; Cloudflare's permits it. Vercel Pro ($20/mo) only if a named Next.js feature justifies it.
- **Phone OTP off by default.** It's the only auth path with per-use cost (SMS). Email magic links until a pilot family genuinely can't use them.
- **No analytics/flags/cron/search SaaS — Postgres does these jobs.** Event counts, a settings table, `pg_cron`, FTS. Both a privacy stance (no third-party SDKs near children's data) and a cost rule.
- **Product analytics never touch photos or message content.** Counts and timings only.

## 2026-08-29 — Brand and assets

- **Gilroy woff2 → ttf conversion committed alongside the originals.** React Native cannot load woff2; Expo needs ttf/otf. Converted with fontTools (same glyph tables). Web keeps woff2.
- **Font selection is by family name, never weight.** The files internally declare five separate families (`Gilroy-Bold` etc.) each with weight class 400. RN: load under per-weight keys, never set `fontWeight` with a custom family. Web: five `@font-face` rules onto one `'Gilroy'` family with explicit weights. Documented in [design-language.md](../references/design-language.md) §4.
- **Gilroy licence must cover app embedding + webfont before store submission.** Commercial typeface; budget line in the cost model.
- **Palette is sampled from the logo, not invented.** Blanket `#3E89E8`, deep `#2166C8`/`#1C5AB5`, heart `#A0C8F8` (decorative only — 1.73:1), ink `#17325C`. Every colour entering `ui-tokens` needs a computed contrast ratio first.
- **Body text is never brand blue.** `#3E89E8` on white is 3.53:1 — large text/UI only. Text links use `blue.600`+.
- **Dark mode deferred; tokens named semantically** (`canvas`, `surface`, `ink`) so it's a token swap later.

## From the plan and build prompt (recorded so they aren't relitigated — rationale in [references/](../references/README.md))

- **Expo (React Native), not Capacitor or a PWA** — dependable iOS push for the Now channel; EAS Build needs no Mac; EAS Update skips store review. ([plan §14](../references/paperkite-daycare-canada-plan.md), [build prompt §2](../references/tucked-build-prompt.md))
- **Supabase Postgres in `ca-central-1`, single multi-tenant project** — relational compliance data, RLS-as-tenancy, Canadian residency as a brand promise. Tenancy is rows, never infrastructure.
- **Compliance rules enforced in the database**, not only the app: constraints, triggers, RLS, `pg_cron`. Clients pre-validate as a courtesy.
- **Tokens + plain StyleSheet/CSS; no Tailwind, no CSS-in-JS.** One token file, two platforms.
- **Stripe Canada (Phase 2): PAD + cards; Interac e-Transfer is record-and-reconcile** (no receiving API exists). No parent-side fees, ever.
- **AI (Phase 2, optional) drafts and translates only** — never accident reports, serious occurrences, medication, or the daily written record. Labelled when machine-translated. No AI on any hot path.
- **Ontario vocabulary and Canadian spelling are binding** — the words table in [tucked-ontario-requirements.md](../references/tucked-ontario-requirements.md) §0.
- **Build/parity/skip calls** follow [tucked-competitor-matrix.md](../references/tucked-competitor-matrix.md): no payroll, no curriculum marketplace, no CRM, no cameras, no US-subsidy logic, no mood emoji.

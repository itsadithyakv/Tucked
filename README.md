# Tucked

A calm daycare app for licensed child care centres in Ontario, by PaperKite.

> **Calm for parents. Boring inspections for operators.**

Parents get one quiet daily story of their child's day plus loud alerts only for things that matter now. Operators get every record an Ontario licensing inspector will ask for, filled in as a side effect of normal work.

## Orientation

| Where | What |
|---|---|
| [references/](references/README.md) | The plan, the master build spec, Ontario compliance requirements, competitor matrix, architecture, design language, cost model. **Read [references/tucked-build-prompt.md](references/tucked-build-prompt.md) first — it is the canonical spec.** |
| [docs/plans/](docs/plans/) | Per-phase build plans (`phase-N.md`), written before each phase begins. |
| [docs/decisions.md](docs/decisions.md) | Why, not what — every decision that would otherwise get relitigated. |
| [docs/compliance-map.md](docs/compliance-map.md) | Regulation section → table / function / screen / test. |
| [assets/](assets/) | Brand mark and the Gilroy typeface (woff2 for web, ttf for mobile). |

## Status

**Phase 0 (foundation) is complete and verified** — see [docs/plans/phase-0.md](docs/plans/phase-0.md). Monorepo: `pnpm install`, then `pnpm check` (lint + typecheck + tests). Local backend (Docker Desktop required): `pnpm db:start`, then `pnpm db:test` for the pgTAP suite. Apps: `pnpm --filter @tucked/web dev` (console at :3000) and `pnpm --filter @tucked/mobile start`. Demo logins (local stack only): `supervisor@` / `educator@` / `parent@mapleleaf.example`, password `tucked-demo`. Next: Phase 1 — plan first in `docs/plans/phase-1.md`.

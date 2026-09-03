# Tucked

A calm daycare app for licensed child care centres in Ontario, by PaperKite.

> **Calm for parents. Boring inspections for operators.**

Parents get one quiet daily story of their child's day plus loud alerts only for things that matter now. Operators get every record an Ontario licensing inspector will ask for, filled in as a side effect of normal work.

## Orientation

| Where | What |
|---|---|
| [references/](references/01-overview-and-architecture.md) | Six documents covering the whole system: product and architecture, every feature and every case it handles, the data and security model, both apps and the design system, and the honest gap list. **Start at [01-overview-and-architecture.md](references/01-overview-and-architecture.md)**, which indexes the rest; **read [06-gaps-risks-and-roadmap.md](references/06-gaps-risks-and-roadmap.md) before writing code.** |
| [docs/plans/](docs/plans/) | Per-phase build plans (`phase-N.md`), written before each phase begins. |
| [docs/decisions.md](docs/decisions.md) | Why, not what — every decision that would otherwise get relitigated. |
| [docs/compliance-map.md](docs/compliance-map.md) | Regulation section → table / function / screen / test. |
| [assets/](assets/) | Brand mark and the Baloo 2 + Nunito typefaces (variable woff2 for web, instantiated ttf for mobile). The retired Gilroy files remain archived; nothing loads them. |

## Status

**Phase 0 (foundation) is complete and verified** — see [docs/plans/phase-0.md](docs/plans/phase-0.md). Monorepo: `pnpm install`, then `pnpm check` (lint + typecheck + tests). Local backend (Docker Desktop required): `pnpm db:start`, then `pnpm db:test` for the pgTAP suite. Apps: `pnpm --filter @tucked/web dev` (console at :3000) and `pnpm --filter @tucked/mobile start`. Demo logins (local stack only): `supervisor@` / `educator@` / `parent@mapleleaf.example`, password `tucked-demo`. Next: Phase 1 — plan first in `docs/plans/phase-1.md`.

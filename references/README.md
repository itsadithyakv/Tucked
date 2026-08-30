# Tucked — references

Everything a builder needs to know about Tucked before writing code, in one folder. Start with the plan, build against the build prompt, and treat the Ontario requirements as acceptance criteria.

## The documents

| Document | What it is | Authority |
|---|---|---|
| [paperkite-daycare-canada-plan.md](paperkite-daycare-canada-plan.md) | The business plan: market, competitors, wedge, pricing, go-to-market, risks, the name. | Why Tucked exists |
| [tucked-build-prompt.md](tucked-build-prompt.md) | The master build specification: stack, domain model, modules, phases, quality gates, full compliance spec (§9). | **Canonical spec** — wins any conflict |
| [tucked-ontario-requirements.md](tucked-ontario-requirements.md) | O. Reg. 137/15 + Licensing Manual as product requirements: every record, rule, and "never do". | Compliance acceptance criteria |
| [tucked-competitor-matrix.md](tucked-competitor-matrix.md) | Feature/pricing matrix vs Brightwheel, Procare, Lillio, Playground, Storypark, Mitten; build / parity / skip calls. | What not to build |
| [architecture.md](architecture.md) | System architecture in depth: tenancy, offline, notifications, where logic lives, environments, security invariants — with the low-cost reasoning marked **[cost]** throughout. | How it's put together |
| [design-language.md](design-language.md) | Visual + verbal identity: logo usage, colour palette (sampled from the logo, contrast-checked), Baloo 2 + Nunito typography, claymorphic surfaces, motion, components, voice and tone. | How it looks and speaks |
| [cost-model.md](cost-model.md) | The running-costs budget: $0 through development, ~$25–30/mo in pilot, ~$50/mo at 10 centres — with named upgrade triggers and the engineering rules that keep it flat. | Standing order: super low running costs |
| [attendance-model.md](attendance-model.md) | The three-layer model: legal attendance (s. 72(3)) vs location vs supervision headcounts — why sessions never take attendance, and the evacuation runbook. | How counting children actually works |

## Brand assets

In [`../assets/`](../assets/):

- `logoTuckedNoBG.png` — master mark (1169 × 1169, transparent). Usage rules in [design-language.md §2](design-language.md).
- `fonts/` — **Baloo 2 + Nunito** variable-font sources (OFL): web serves them as variable woff2, mobile as fontTools-instantiated static ttfs. Loading rules in [design-language.md §4](design-language.md). The retired Gilroy files remain archived here; nothing loads them.

## The two sentences

> **Calm for parents. Boring inspections for operators.**

If a change doesn't serve one of those, it probably belongs on the do-not-build list.

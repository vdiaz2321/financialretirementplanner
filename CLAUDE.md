# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file financial and retirement planner for military and civilian users (`index.html`, ~2,000 lines of inline HTML/CSS/JS). No build step, no package manager, no server — it's opened directly in a browser. The only external dependency is Chart.js, loaded via CDN (`cdn.jsdelivr.net/npm/chart.js@4.4.4`).

There is no test suite and no linter configured in this repo.

## Commands

There is no build/test/lint tooling. Development loop:
- Edit `index.html` directly.
- Open it directly in a browser to verify (double-click, or `file://` URL) — no dev server needed.
- No Node tooling is required to run the app; `wrangler.jsonc` exists only for the Cloudflare Worker deploy step (see below), not for local development.

## Deployment

Two targets, each serving the same `index.html` from a different branch:

| Service | Branch | Purpose |
|---|---|---|
| Cloudflare Worker (`financialretirementplanner.vdiaz24.workers.dev`) | `main` | Auto-deploys on every push to `main` — production |
| GitHub Pages (`vdiaz2321.github.io/financialretirementplanner`) | `preview` | Free review URL for sanity-checking changes before they're considered final |

Workflow: commit locally → push to both `main` and `preview` (`git push origin main && git push origin main:preview`) → review on the Cloudflare or GitHub Pages URL. Do not push without being asked — confirm with the user first, since pushing affects the live Cloudflare Worker immediately.

Netlify is no longer part of the deployment pipeline (Cloudflare Worker covers production). If a `netlify.toml` or similar config still exists in the repo, it's inert — do not maintain or reference it.

`wrangler.jsonc` configures the Cloudflare Worker to serve static assets from `.` (the repo root) with `nodejs_compat` enabled — there's no actual Worker script, it's pure static asset serving.

## Architecture

Everything lives in one `<script>` block at the bottom of `index.html`. The app has three layers:

**1. Input layer** — `<details>` elements (collapsible sections) in tab panes (`pane1`, `paneH`, `pane2`, `pane3`, `pane5`) hold plain `<input>`/`<select>` elements. Every input/select ID that should persist is listed in the `ALL_IDS` array (~line 1270) and the `ACCTS` array (the 7 asset account types: `Tsp`, `RothMe`, `RothWife`, `Tax`, `Sav`, `Crypto`, `Gold`, used for the actuals grid). **Any new persistent input field must be added to `ALL_IDS`** or it won't save/load/backup correctly.

**2. Calculation engine — `runModel()`** (~line 1382) — the core of the app. On every call it:
- Reads all current input values via local helpers `v(id)` (numeric) and `txt(id)` (string/select), both closures defined at the top of `runModel()`.
- Defines a large set of nested helper functions scoped *inside* `runModel()` (e.g. `incomeParts(y)`, `expensesMonthly(y)`, `homeForYear(y)`, `bahForYear(y)`, `debtPaymentMonthly(y)`, `mortgageRemaining(y)`, `nw(y)` for net worth). These are **not** globally accessible — anything outside `runModel()` that needs them must go through the exported objects below.
- Builds year-by-year projections into `proj[y]` / `actual[y]` objects (one per account in `ACCTS`).
- At the end, exports everything outside code needs via two globals: **`window._cf`** (calculation helper functions + scalar inputs, e.g. `c.nw(y)`, `c.incomeParts(y)`) and **`window._ctx`** (year-indexed data + a few more helpers, e.g. `proj`, `actual`, `accCashFlow`). A separate IIFE builds **`window._chartData`** (flat arrays keyed by year, for Chart.js).
- **If you add a new nested helper function that needs to be called from outside `runModel()` (e.g. from a render function), you must add it to the `window._cf` or `window._ctx` export object** — there's no other way to reach it.

**3. Render layer** — top-level functions outside `runModel()` (e.g. `buildCashGroup()`, `buildInvGroup()`, `buildEduGroup()`, `renderCashFlow()`, `renderPcsCompare()`, `renderCharts()`) read from `window._cf`/`window._ctx`/`window._chartData` and write HTML into the DOM. `buildSectionGroups()` calls all three `build*Group()` plus `renderPcsCompare()`, which is the main re-render entry point after `runModel()` finishes.

**Buy vs Rent Comparison panel** — `renderPcsCompare()` writes into `#pcs-compare-panel` at the bottom of the Housing tab. For each PCS it computes Buy vs Rent side-by-side over the same start/end window (buy year→sell year, or rent start→end). Columns: Home/mo, Utils/mo, BAH/mo, Net/mo, Down Pmt, Total Housing, Total Utils, Total BAH, Total Out-of-Pocket, End Equity (3% appreciation − 6% selling costs), Net Cost, Verdict, and an "Activate" button. The button calls `activatePcsOption(pcsKey, typeKey, startY, endY)` which flips the housing-type dropdown and auto-fills blank utility dates so Section 2 immediately reflects the choice. BAH and Utils totals are suppressed (shown as $0) when their Start/End year fields are blank — the model only counts them when those dates are set.

**Cash Flow table columns** — `renderCashFlow()` order: Year, My Age, Spouse Age, Status, My Net/mo, Spouse/mo, Combined/mo, Home/mo, Utils/mo, BAH/mo, Debt/mo, Exp/mo, Invest/mo, Health/mo, Life Ins/mo, PrivSch/mo (conditional), SBP/mo, Surplus/mo, Annual, Projected Net Worth. Health/mo, Life Ins/mo, and PrivSch/mo are broken out via `healthcareMonthly(y)` / `lifeInsMonthly(y)` / `privSchMonthly(y)` helpers (all exported on `_cf`); the Exp/mo cell shows the residual (`expensesMonthly − health − lifeIns − privSch`) so surplus math stays identical.

**Private schooling toggle** — `showPrivate` global (default true) mirrors the `showWife` pattern. `togglePrivate(state)` re-runs the model; when off, `expensesMonthly()` skips the K-12 tuition/fees add-in, so both cash flow and net worth reflect the change. The PrivSch/mo column and the WITH/WITHOUT + Dashboard toggle buttons only render when `hasPrivSchoolData()` (any child has start/end year + tuition/fees > 0) — otherwise they're hidden to avoid clutter for users without K-12 private school plans.

**Sidebar sync** — Education and Investments each appear in two places (Core Inputs sidebar `sl-3`/`sl-2` and Results sidebar `sl-edu`/`sl-inv`). Clicking either link routes through `sideNavEducation(from)` or `sideNavInvestments(from)` which activates both links and shows both the input tab and results group, so the two views stay in sync.

**Net worth** (`nw(y)` inside `runModel()`) is the central computed value, reused in three places: the 3 dashboard snapshot cards (`card()`), the Net Worth chart (`window._chartData.netWorth`), and the "Projected Net Worth" column in the year-by-year Cash Flow table — all three must stay in sync, which is why they all call the same `nw(y)` rather than duplicating the formula.

### Persistence

- `autoSave()` / `autoLoad()` serialize all `ALL_IDS` fields, the actuals grid (`__actuals`), and open/closed `<details>` state (`__details`) to `localStorage` under key `frp_v80`. `autoLoad()` falls back to reading older keys (`frp_v78`, `frp_v77`, `frp_v76`) for backward compatibility with earlier versions of the planner.
- `downloadBackup()` / `uploadBackup()` export/import the same data as a JSON file.
- Dark mode preference is stored separately under `frp_darkmode`.
- Every persisted input has `onchange="autoSave()"` wired up via `attachAutoSave()`, which iterates `ALL_IDS` — so new fields are auto-saved automatically once added to `ALL_IDS`, no manual wiring needed per-field.

### Currency display

`applyCurrencyStyles()` (~line 1980) auto-wraps `<input type="number">` elements in a `$`-prefix span, **except** for IDs matching substrings in its `skip` array (e.g. `age`, `year`, `pct`, `rate`, `cola`, `apy`, `fedtax`, `vafee`, `yos`). When adding a new percentage/count input, add a matching substring to `skip` — otherwise it will incorrectly show a `$` prefix. Conversely, when adding a new dollar-amount field, double-check it doesn't accidentally match an existing `skip` substring (e.g. avoid generic substrings like `fee` or `roll` that could collide with unrelated dollar fields — prefer specific ones like `vafee`, `tsproll`).

### Military retirement pay

The Retirement System selector (`retSystem`: `high3`/`brs`/`redux`) drives a live auto-calculator: if `yos` (years of service), `yosMonths`, and `high3Pay` (average monthly base pay) are filled in, `runModel()` overwrites `retGross` (Retirement GROSS Annual) using `high3Pay × 12 × multiplier × (yos + yosMonths/12)`, where multiplier is 2.5% for High-3 and 2.0% for BRS/REDUX — matching the official DFAS High-3 calculator's fractional-year-of-service formula. If `yos`/`high3Pay` are left blank, `retGross` is left untouched, preserving manual entries from before this calculator existed.

### Details open/close behavior

- All Core Input `<details>` elements **do NOT have the `open` attribute** in HTML — they load collapsed by default on every page load, regardless of last saved state.
- `autoLoad()` intentionally skips restoring `__details` state (except for `det_actuals`) so sections always start collapsed.
- `toggleAllDetails(paneId, open)` only targets `details.inline-summary` (the top-level section cards). Nested sub-toggles (`det_income_promos`, `det_mil_other`, `det_health_tricare/med/dental` and their `*2` rate-change variants, `det_main_exp2`, `det_lifeins_rate2`) are always forced closed by Expand/Collapse All and only open when the user clicks them directly.

### Toggle button colors

- `.toggle-btn.active` (WITH/WITHOUT Spouse buttons in Cash Flow and elsewhere) uses `background: var(--blue); color: #fff` to match `.view-btn.active`. All active toggle buttons throughout the app are now consistently blue.

### Charts (Results sections)

All time-series charts use a shared `buildYearPlugin(yearsArr)` helper that draws:
- A shaded region for years before the current year
- A solid vertical line at the current year
- Dashed milestone lines (Retirement, TSP W/D, SS Start, GS Start/End)

Charts enhanced: Net Worth (stacked area: Liquid / Retirement Accts / Home Equity), Investments composition (stacked bar), Annual Surplus bar, and per-asset detail charts (Taxable, Crypto, Gold). Points are hidden (`pointRadius:0`) except on hover.

### Sidebar layout

Left sidebar Core Inputs order: Main Data → Housing & Real Estate → Probate Log → Investments/Savings → Education → Debt. Probate Log sits above Investments/Savings because balances flow from Probate Log into the locked Investments/Savings fields.

Investments/Savings sidebar links are labeled "Investments/Savings" (not just "Investments") in both Core Inputs and Results sections.

### Locked Investments/Savings balance fields

The 7 balance fields (`tspBal`, `rothBalMe`, `rothBalWife`, `taxBal`, `savBal`, `cryptoBal`, `goldBal`) in `pane2` are `readonly` with `data-locked-tip="Add balances under Probate Log Section"` and `background: var(--surface-2)`. A custom JS tooltip (`initSbTooltip` IIFE, reusing `#sb-tooltip`) shows on hover/focus — no native `title` attribute (that caused a duplicate tooltip bug).

`syncProbateBalances()` sets these fields from Probate Log totals and also reapplies the `data-locked-tip` attribute and gray background.

### Probate Log banner

The "📒 How the Probate Log works" `<details>` at the top of `paneP` is default-closed. It contains three color-coded cards (blue=Bank→Savings/Cash, green=Personal Investments→Taxable/Crypto/Gold/Savings, purple=Pension Plans→TSP & Roth) explaining which Probate Log sections flow into which Investments tab fields.

### Main Data grid structure (pane1)

Two `<div class="grid4">` rows:

**Row 1:**
- Col 1: `det_main_people` — People & Timeline (ages, retirement month/year, projection start/end year)
- Col 2 (flex column): `det_main_income` (Income & Pay, with nested `det_income_promos` for promotions) + `det_main_spouse` (Spouse Income) stacked
- Col 3: `det_main_mil` (Military Retirement, with nested `det_mil_other` for VA Disability & Other Net Monthly)
- Col 4: `det_main_post` (GS / Federal Civilian Job)

**Row 2:**
- Col 1: `det_main_exp1` (Monthly Expenses, with nested `det_main_exp2` Rate Change)
- Col 2: `det_main_health` (Healthcare — three nested sub-toggles: `det_health_tricare`, `det_health_med`, `det_health_dental`, each with their own `*2` Rate Change nested inside)
- Col 3: `det_main_lifeins` (Life Insurance, with nested `det_lifeins_rate2` Rate Change)
- Col 4: `det_main_ss` (Social Security — Retire Income)

## Cross-session continuity

The user works across two machines (PC and MacBook) — both have this repo cloned from GitHub. Sync is handled entirely via git: `git pull` before starting work, `git push` when done. No Google Drive sync needed.

Cross-session context (what was done, what's next) is captured in `CLAUDE.md` (this file) and the Claude Code memory files at `~/.claude/projects/<encoded-path>/memory/project_context.md`. Check those at the start of a new session rather than re-deriving from code.

## Recent changes (as of 2026-07-14, commit 8c8cc59)

- All input sections now load collapsed by default (removed `open` from all `<details class="schoolblock inline-summary">` in HTML; `autoLoad()` no longer restores details state)
- Expand/Collapse All buttons skip nested sub-toggles
- Active toggle buttons (WITH/WITHOUT Spouse, etc.) now blue to match view buttons
- Charts enhanced with stacked areas, milestone markers, current-year divider, decluttered points (shared `buildYearPlugin()`)
- Probate Log banner redesigned as color-coded cards, default-closed
- Investments/Savings balance fields locked (readonly + tooltip)
- Main Data grid restructured: Spouse Income under Income & Pay column, Healthcare split into 3 independent sub-toggles (Tricare/Medical/Dental) each with nested Rate Change
- Sidebar: Probate Log link moved above Investments/Savings; links renamed to "Investments/Savings"

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

Three targets, each serving the same `index.html` from a different branch:

| Service | Branch | Purpose |
|---|---|---|
| Cloudflare Worker (`financialretirementplanner.vdiaz24.workers.dev`) | `main` | Auto-deploys on every push to `main` — used for previewing live changes |
| Netlify | `main` | Auto-deploy is **paused** — only deploys when manually triggered from the Netlify dashboard ("Trigger deploy" → "Deploy site"), used for production |
| GitHub Pages (`vdiaz2321.github.io/financialretirementplanner`) | `preview` | Free review URL for sanity-checking changes before they're considered final |

Workflow: commit locally → push to both `main` and `preview` (`git push origin main && git push origin main:preview`) → review on the Cloudflare or GitHub Pages URL → manually trigger Netlify deploy once satisfied. Do not push without being asked — confirm with the user first, since pushing affects the live Cloudflare Worker immediately.

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

**3. Render layer** — top-level functions outside `runModel()` (e.g. `buildCashGroup()`, `buildInvGroup()`, `buildEduGroup()`, `renderCashFlow()`, `renderCharts()`) read from `window._cf`/`window._ctx`/`window._chartData` and write HTML into the DOM. `buildSectionGroups()` calls all three `build*Group()` functions, which is the main re-render entry point after `runModel()` finishes.

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

## Cross-session continuity

The user works across two machines (PC and MacBook) using this git repo as the sync mechanism — `git pull` before starting work, `git push` when done, rather than copying the file via cloud storage (which isn't git-aware and can silently overwrite changes). A separate Google Drive doc ("Financial Planner - Dev Notes & Roadmap.md") tracks cross-session status/roadmap and should be checked/updated when picking up work after a gap or finishing a notable chunk of work.

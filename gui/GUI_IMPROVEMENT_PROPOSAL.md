# GUI Improvement Proposal

## Purpose

This proposal consolidates recommended improvements for the BE200 local GUI in four areas:

- visual clarity and operator confidence
- reliability and error handling
- information architecture and workflow fit
- maintainability and testability

The current GUI already has a solid operator-console foundation:

- strong safety framing in the scope strip
- clear route grouping in [templates/base.html](templates/base.html)
- risk zoning in [static/style.css](static/style.css)
- validation-before-apply workflow in [templates/editor.html](templates/editor.html)
- artifact-driven auditability in history and job detail

This proposal is intentionally evolutionary. It does not assume a rewrite.

## Design Goals

1. Make dangerous actions feel visually heavier than read-only views.
2. Reduce the chance of operator misreads before and after execution.
3. Make fleet-level status easier to scan and compare.
4. Preserve the current safety model and PowerShell-first execution boundaries.
5. Improve resilience without changing accepted operator scope.

## Non-Goals

- no conversion into a cloud app
- no remote browser automation
- no arbitrary target entry
- no weakening of allowlist or validation policy
- no replacement of the PowerShell toolkit backend

## Current Strengths

These should be preserved:

- grouped navigation and persistent scope strip in [templates/base.html](templates/base.html)
- consistent operator styling tokens in [static/style.css](static/style.css)
- accepted-property enforcement in [templates/editor.html](templates/editor.html)
- policy callout and confirmation box pattern in [templates/inventory.html](templates/inventory.html)
- dense audit-oriented history in [templates/history.html](templates/history.html)

## Proposal Overview

The recommended work is grouped into three phases:

1. Operator Clarity
2. Reliability and Workflow Safety
3. Structural Cleanup and Scale Readiness

## Phase 1: Operator Clarity

### 1. Risk-Layered Layout

Promote a stronger visual distinction between four kinds of pages and cards:

- `Read Only`
- `Configuration`
- `State Changing`
- `System Level`

Recommended treatment:

- keep the existing left-border zone system
- add stronger page-level headers for dangerous routes
- add persistent danger banners on:
  - `Property Editor` real apply section
  - `Inventory` operational actions
  - `Restart + RDP`
  - `Open NCPA`

Suggested page labels:

- Dashboard: `Read Only`
- Inventory: `Read Only + State Control`
- Current Settings: `Read Only`
- Property Editor: `Configuration / State Change`
- Wi-Fi Connect: `State Change`
- Wi-Fi Status: `Read Only`
- Restart + RDP: `System Level`
- Open NCPA: `System Level`

### 2. Pre-Execution Summary Panels

Before any dangerous submit, show a compact execution summary card with:

- selected targets
- operation or mode
- property count
- exact script to be invoked
- whether adapter restart will occur
- whether OS restart will occur
- whether `mstsc` will launch
- expected artifact categories

Apply this to:

- operational actions in [templates/inventory.html](templates/inventory.html)
- real apply in [templates/editor.html](templates/editor.html)
- restart workflow in [templates/system_restart_rdp.html](templates/system_restart_rdp.html)
- Open NCPA in [templates/open_ncpa.html](templates/open_ncpa.html)

### 3. Stronger Job Outcome Presentation

The recent `success / partial / failed` improvement should be expanded into a richer pattern.

Recommended presentation:

- badge color plus outcome count
- always show `status_reason`
- always show result overview when available

Examples:

- `success` -> `8/8 targets succeeded`
- `partial` -> `6/8 targets succeeded`
- `failed` -> `0/8 targets succeeded`

Recommended changes:

- dashboard recent jobs should show counts, not just a color
- history should support a one-line summary of row outcome
- job detail should promote `status_reason` above raw stdout

### 4. Better Fleet Readability

Across fleet tables:

- use monospace consistently for:
  - target IP
  - registry keyword
  - job id
  - artifact path
  - driver version
- use sticky headers on all large tables, not only the current settings matrix
- widen first columns on operator-critical tables
- keep compact text, but increase badge size slightly for scan speed

### 5. Dashboard Upgrade Into a Preflight Console

The current dashboard is useful but still passive.

Upgrade it into a `preflight` screen with tiles for:

- controller identity
- remoting freshness
- latest discovery age
- latest validation status
- latest apply status
- unresolved partial/failed jobs
- GUI local health

Recommended local health checks:

- toolkit root exists
- output path writable
- history index readable
- discovery artifact present / missing / stale
- Python runtime available for GUI host

## Phase 2: Reliability and Workflow Safety

### 6. Submission Guardrails

Add in-browser protections to prevent accidental duplicate runs:

- disable submit buttons while a request is being sent
- show `Running...` state
- add route-local warning if a dangerous form is re-submitted
- optionally block same-type concurrent jobs from the GUI

Most valuable on:

- discovery refresh
- real apply
- restart + RDP
- Open NCPA
- Wi-Fi Connect

### 7. Filterable History

Convert history from a flat audit table into a more usable operator tool.

Recommended additions:

- filter by status
- filter by job type
- search by:
  - target IP
  - property label
  - registry keyword
  - action
  - script name
- quick toggle: `show only partial / failed`

Optional layout enhancement:

- keep current table for desktop
- add a split-pane detail preview later

### 8. Better Result Table Review

Add review aids inside job detail:

- `Show only failures`
- `Show only warnings / partial rows`
- `Show only successful rows`
- copy-friendly artifact path list

For apply jobs, highlight:

- `ApplySucceeded = false`
- `VerificationSucceeded = false`
- `RestartSucceeded = false`

For restart/open-ncpa jobs, highlight:

- timeout
- unreachable
- no mstsc launch
- no visible success row

### 9. Discovery Freshness Warning

In `Property Editor`, show a freshness banner when discovery is missing or stale.

Suggested thresholds:

- under 24h: normal
- 24h to 72h: warning
- over 72h: stale

This should sit near `discovery_path` and target selection so the operator sees it before validation.

### 10. Current Settings as a Fleet Diff Tool

The current settings page should evolve from a matrix into a fleet comparison workspace.

Recommended toggles:

- show only accepted properties
- show only mismatched targets
- show only non-uniform values
- sort by most variant property first

Recommended action bridge:

- one-click `Open in Property Editor` for a selected property

This would make the page operationally useful, not just informative.

## Phase 3: Structural Cleanup and Scale Readiness

### 11. Navigation Reorganization

The current nav works, but a more operator-mental-model-aligned grouping would help.

Recommended top-level groups:

- `Overview`
- `Discovery`
- `Configuration`
- `Operations`

Suggested mapping:

- Overview:
  - Dashboard
  - History
- Discovery:
  - Inventory
  - Current Settings
- Configuration:
  - Property Editor
- Operations:
  - Wi-Fi Connect
  - Wi-Fi Status
  - Open NCPA
  - Restart + RDP

This is mostly a wording and grouping pass in [templates/base.html](templates/base.html).

### 12. Componentization of Shared UI Patterns

Several repeated patterns should become reusable partials or macros:

- page header block
- artifact list
- status badge
- danger confirmation box
- target checkbox grid
- summary card
- result count badge

This will reduce drift between templates and speed up future changes.

### 13. Service Layer Decomposition

[services.py](services.py) is now doing multiple jobs:

- job persistence
- artifact lookup
- status interpretation
- orchestration
- property policy
- view-model preparation

Recommended medium-term split:

- `job_store.py`
- `job_runner.py`
- `artifact_index.py`
- `policy.py`
- `inventory.py`
- `ui_summary.py`

This should happen after user-facing improvements, not before.

### 14. Frontend Smoke Tests

Add lightweight tests for page rendering and state display.

Minimum recommended coverage:

- dashboard render with mixed job states
- history render with `partial`
- job detail render with `status_reason`
- editor validation blocked state
- danger form confirmation presence

This can build on the same Flask test client approach already used in backend-oriented tests.

## Page-by-Page Recommendations

### Dashboard

Keep:

- controller card
- artifact card
- recent jobs card

Add:

- preflight health row
- unresolved issues card
- artifact freshness markers
- direct links to most recent failed/partial jobs

### Inventory

Keep:

- discovery + remoting forms
- operational policy callout
- fleet table
- accepted property catalog

Add:

- execution summary before submit
- selected target count
- risk chip next to current operation
- operator note when discovery is stale

### Property Editor

Keep:

- multi-property builder
- generated config preview
- validation summary
- explicit real-apply confirmation

Add:

- execution summary card before real apply
- stale discovery warning
- property risk chips in selector
- common-mode compatibility preview as properties are added
- optional `show only targets with this property` helper

### History

Keep:

- audit orientation

Add:

- filters
- search
- `show only actionable failures`
- richer summary column with row counts

### Job Detail

Keep:

- raw stdout/stderr
- artifact listing
- result rows

Add:

- prominent `status_reason`
- overview counters near the top
- row filters
- copy buttons for command and paths

### Wi-Fi Connect / Status

Add:

- clearer explanation of success criteria
- stronger separation between `Connect` and `Verify`
- last used target count + SSID summary
- explicit warning that network reachability is not fully validated by SSID match alone

### Restart + RDP

Add:

- heavier system-level visual style than current risk zone
- pre-execution system summary
- clearer explanation of:
  - ping recovery
  - RDP port check
  - `mstsc` launch behavior

### Open NCPA

Add:

- stronger wording around interactive-session dependency
- clearer distinction between:
  - remote task registration succeeded
  - user visibly saw the window

## Visual Direction

The current styling direction is good and should be preserved:

- strong navy shell
- high-contrast tables
- Fira Sans / Fira Code
- card-based console layout

Recommended refinements:

- slightly larger state badges
- stronger contrast for muted metadata
- tighter spacing in data-dense cards
- small iconography only where it adds meaning:
  - read-only
  - warning
  - danger
  - system

Avoid:

- decorative animation-heavy redesign
- glassmorphism or low-contrast trends
- overly soft danger styling

## Accessibility Recommendations

1. Preserve skip link and focus styles.
2. Add visible labels for all confirmation areas.
3. Add `aria-live` only where results truly change dynamically.
4. Ensure badge color is not the only status signal.
5. Prefer descriptive button labels over generic `Run`.

## Rollout Strategy

### Batch A: Highest Value, Lowest Risk

- richer job status presentation
- status reason prominence
- dashboard preflight tiles
- execution summary panels
- duplicate-submit guardrails

### Batch B: Workflow Usability

- filterable history
- job detail row filters
- discovery freshness warnings
- current settings fleet diff toggles

### Batch C: Structural Cleanup

- template partial extraction
- navigation relabeling / regrouping
- service layer decomposition
- frontend smoke tests

## Suggested Acceptance Criteria

For any GUI improvement batch, accept only when:

- no route loses the current safety boundary
- `success / partial / failed` remain accurate and readable
- no page hides the allowlisted scope
- keyboard navigation still works
- operator-critical data remains visible without opening dev tools or reading raw JSON

## Decisions Needed From You

Before implementation, these product decisions should be confirmed:

1. Should the GUI remain a local operator tool only, or be prepared for broader use on `192.168.22.8`?
2. Do you want the nav regrouped now, or after functionality improvements?
3. Should history stay table-first, or move toward a split-pane event view?
4. Do you want Batch A only first, or all three batches as a larger redesign program?

## Recommended Next Step

Start with `Batch A`.

It gives the best operator value immediately:

- clearer danger boundaries
- better result interpretation
- better readiness checking
- lower chance of accidental re-submits

Then decide whether to continue into `Batch B` based on how much daily operator traffic the GUI is expected to handle.

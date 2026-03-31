# BE200 Control Console — UI redesign summary

## Direction

- **Bootstrap 5.3** retained; styling extended via [static/style.css](static/style.css) using design tokens (navy primary `#1E40AF`, slate background `#F8FAFC`, **Fira Sans** / **Fira Code**).
- **Operator shell**: persistent **scope strip** (fleet IP range + BE200-only adapter policy), grouped nav with **active route** highlighting, skip link, max-width main column.
- **Zones**: `zone-readonly` (read/monitor), `zone-action` (standard actions), `zone-risk` (Wi‑Fi connect, operational actions, real apply).
- **Tables**: `table-be200` for dense data; settings matrix uses `matrix-table-wrap` + sticky header row + **`matrix-driver-ver`** (high-contrast driver text, no low-opacity hiding).
- **Policy visibility**: `callout-scope` for live operational policy text; **`confirmation-box`** (dashed amber) for operational and real-apply checkboxes so confirmations stay visually obvious.

## Operator-critical visibility (preserved or strengthened)

| Concern | Where |
|--------|--------|
| Accepted scope | Scope strip; page leads; “accepted” / “catalog scope” in headers; property matrix badges |
| Driver version | Fleet `driver-cell` + date line; matrix column headers with `matrix-driver-ver` |
| Current target scope | Inventory “Current target scope” label + checkboxes; editor “Target scope”; Wi‑Fi `target-grid`; policy note still lists **Accepted targets** and max |
| Risky confirmations | `confirmation-box` + stronger copy on operational + real apply |

## Files touched

- [static/style.css](static/style.css) — full token set and components (from [REDESIGN_STYLE_SNIPPET.md](REDESIGN_STYLE_SNIPPET.md) source block).
- [templates/base.html](templates/base.html) — nav groups, `request.endpoint` active links, scope strip, `app-main`.
- [templates/dashboard.html](templates/dashboard.html), [history.html](templates/history.html), [job_detail.html](templates/job_detail.html), [current_settings.html](templates/current_settings.html), [inventory.html](templates/inventory.html), [editor.html](templates/editor.html), [wifi_connect.html](templates/wifi_connect.html), [wifi_status.html](templates/wifi_status.html) — headers, cards, zones, tables.

**Staging / optional cleanup:** [GUI_APPLY_BUNDLE.md](GUI_APPLY_BUNDLE.md) was used to apply templates when plan mode blocked direct HTML writes; you may delete it after you are satisfied. To re-apply from bundle + snippet, run `py -3 _apply_gui_redesign.py` (recreate that script from the last session if needed).

## Verification

- `Flask` `test_client()` GETs: `/`, `/inventory`, `/editor`, `/current-settings`, `/wifi-connect`, `/wifi-status`, `/history` → **200**. Job detail uses URL prefix `/jobs/` (see `job_detail` in [app.py](app.py)).

## Small behavior fix

- Inventory operational submit: empty target alert text is **“Select at least one target…”** (multi-target is valid).

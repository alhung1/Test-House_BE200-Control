# BE200 Control Console — GUI redesign release note

1. **Redesign completed** — Operator-facing UI refresh (Bootstrap 5 retained): tokens, navigation, scope strip, cards/zones, tables, and confirmation affordances while preserving operator-critical visibility.

2. **Smoke verification completed** — Automated pass covered inventory, current settings, editor (validation and apply paths), operational actions, Wi‑Fi Connect/Verify, history, and job detail (HTTP responses, form handling, redirects, and job flows).

3. **No regressions found** — Operator flow smoke pass reported no regressions (no 5xxs; forms, flashes, and job routing behaved as expected).

4. **Design documentation** — [gui/DESIGN_SUMMARY.md](gui/DESIGN_SUMMARY.md) (under this repo: `C:\Test House BE200 control\gui\DESIGN_SUMMARY.md`).

5. **Baseline acceptance** — The redesign is accepted for production use from a GUI integration perspective: pages render, core POST flows execute, jobs are created and viewable, and the pass did not surface UI-induced breakage of operator workflows. Remote action outcomes still depend on environment credentials and fleet state.

6. **Live-verified system workflows** — **Restart + RDP** (`/system-restart-rdp`) and **Open NCPA** (`/open-ncpa`) were staged on the lab controller against `192.168.22.221`–`228` (including an all-eight run where one host was powered off and correctly reported failure). Accepted scope for both: the same eight fleet IPs only; never `192.168.22.8`; no L3 or Ethernet changes. Success criteria, caveats, session limits, and step-by-step usage are documented in [GUI_OPERATOR_HANDOFF.md](GUI_OPERATOR_HANDOFF.md) under **System workflows (live-verified)**. Toolkit support: `orchestrate-restart-rdp.ps1` (ping polling compatible with this environment’s PowerShell 5.1; internal row timing fields fixed for strict mode) and `orchestrate-open-ncpa.ps1` (COM Task Scheduler with InteractiveTokenOrPassword for interactive-desktop NCPA launch).

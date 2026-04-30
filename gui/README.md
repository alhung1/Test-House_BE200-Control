# BE200 GUI Runbook

## Purpose
This local web GUI runs on the controller and wraps the existing validated PowerShell toolkit under `C:\Test House BE200 control`.

The GUI does not replace the toolkit logic. It orchestrates these scripts:
- `test-remoting.ps1`
- `discover-be200-advanced-properties.ps1`
- `export-be200-config-template.ps1`
- `validate-be200-config.ps1`
- `apply-be200-config.ps1`
- `orchestrate-open-ncpa.ps1` (Open NCPA page only)

`invoke-be200-action.ps1` is intentionally not wired into the v1 GUI.

## Python Requirements
Use Python 3 only:
- `py -3`
- `py -3 -m pip`

Do not use the plain `python` command on this machine.

## Install Dependencies
From `C:\Test House BE200 control\gui`:

```powershell
py -3 -m pip install -r requirements.txt
```

## Start The GUI
From `C:\Test House BE200 control\gui`:

```powershell
.\start-gui.ps1
```

Or directly:

```powershell
py -3 .\app.py
```

Default URL:

```text
http://127.0.0.1:5000
```

## GUI Structure
- `app.py`: Flask entrypoint and routes
- `services.py`: PowerShell orchestration, artifact discovery, inventory parsing, history storage
- `config.json`: local GUI settings and validated target scope
- `templates/`: HTML pages
- `static/`: local CSS
- `data/`: GUI job history and per-job JSON
- `work/configs/`: generated config CSVs used for validate/apply
- `logs/`: reserved for future local GUI logs

## Safety Model
- Only the validated target set `192.168.22.221` through `192.168.22.228` is exposed.
- The GUI never asks for arbitrary IP entry.
- The GUI reads discovery outputs to build property/value inventory.
- The GUI always validates before enabling real apply.
- Real apply requires explicit confirmation in the browser.
- The GUI uses the validated toolkit scripts rather than issuing raw adapter-changing commands.

## Page Mapping

### Dashboard
- shows toolkit root
- shows controller identity
- shows latest remoting/discovery/template/apply artifacts
- shows recent GUI jobs

### Inventory
- reads the latest discovery snapshot
- shows per-target adapter resolution and property counts
- highlights variant targets with missing keywords
- can run remoting test
- can run discovery refresh, then template export

### Property Editor
- selects one or more validated targets
- selects one property from latest discovery data
- accepts a target value
- supports `WriteOnly` and `RestartBE200`
- generates config CSV rows in `gui\work\configs`
- runs validation first
- shows validation output
- only then enables real apply

### History / Job Detail
- stores each GUI-triggered run as JSON in `gui\data\jobs`
- stores a summary index in `gui\data\history.json`
- shows command, stdout, stderr, artifact paths, and parsed result rows

### Restart + RDP (`/system-restart-rdp`) -- live-tested 2026-03-31
- **Route:** `http://127.0.0.1:5000/system-restart-rdp`
- **Live verification status:** All 3 stages passed. Stage 1: single target `.221` (36s recovery, RDP port Yes, mstsc launched). Stage 2: two targets `.221`+`.223` (20s/26s recovery, both Success). Stage 3: all 8 targets (7/7 reachable Success, `.222` powered off correctly reported Failed).
- **What it does:** Issues `Restart-Computer -Force` via WinRM per target, then polls for ping recovery with configurable timeout. Optional TCP 3389 check and sequential `mstsc /v:<ip>` launch from the controller.
- **Bug fix applied during testing:** `Test-Connection -TimeoutSeconds` does not exist on this PowerShell 5.1 build; replaced with `-ErrorAction SilentlyContinue`. `Add-Member` on ordered hashtable lost during `[pscustomobject]` cast; fixed by casting first, then adding the member.
- **CSV columns:** `TargetIP`, `RestartRequested`, `RestartIssued`, `RestartError`, `PingReachable`, `RecoverySeconds`, `RdpPortOpen`, `RdpLaunched`, `FinalStatus`, `Message`.
- **Caveats:** `RdpPortOpen` may show `No` for hosts whose RDP service has not started yet even though ping succeeded (timing-dependent). `mstsc` is launched from the controller desktop; it does not guarantee successful logon. `.222` was powered off during testing and is consistently unreachable.

### Open NCPA (`/open-ncpa`) -- live-tested 2026-03-31
- **Route:** `http://127.0.0.1:5000/open-ncpa` (when the GUI is bound to localhost).
- **Live verification status:** All 3 stages passed. 7/7 reachable targets confirmed `NcpaSuccess=Yes` with Network Connections opening in the interactive desktop session. `.222` (powered off) correctly reported `Failed`.
- **Mechanism:** COM `Schedule.Service` API with `LogonType = InteractiveTokenOrPassword (3)` and action `rundll32.exe shell32.dll,Control_RunDLL ncpa.cpl`. This is the only approach that reliably opens GUI apps in a logged-on user's interactive session when invoked remotely via WinRM.
- **Accepted targets:** Only `192.168.22.221`–`228` (checkboxes). `192.168.22.8` is never valid.
- **Order:** Selected hosts are processed **in sequence** (checkbox list order: .221 through .228).
- **What it does:** For each target, the orchestrator uses **WinRM** (`Invoke-Command`) and registers a **one-shot scheduled task** so `cmd.exe /c start "" ncpa.cpl` runs on that machine. It first tries **Interactive** principal registration (best for showing Network Connections on the logged-on desktop). If that fails, it falls back to a **user/password** one-time task registration (same action); the fallback may not always surface UI on an interactive desktop. The task is started immediately and then removed. **No** Ethernet/IP/gateway/DNS/route/metric/proxy changes are made.
- **Optional RDP:** If “open mstsc” is checked (default in `config.json`: `open_ncpa_open_mstsc_default`), after each target the **controller** runs `mstsc /v:<ip>` so the operator gets a visible Remote Desktop window in order.
- **Credentials:** Username/password are passed only to the subprocess; `-Password` is **redacted** in stored job `command` and in logged argv text (same pattern as other jobs). Do not paste passwords into transcripts or custom logs.
- **Config defaults:** `open_ncpa_timeout_seconds`, `open_ncpa_default_delay_seconds`, `open_ncpa_open_mstsc_default` in `gui\config.json`.
- **Session caveats:** The account you enter should be the same user (or compatible with) an **active interactive logon** on the target. If nobody is logged on at the console, the interactive task may not show Network Connections on a desktop. With **console + RDP** sessions, which session receives the UI can vary by OS. **WinRM** and firewall rules must allow remoting from the controller.
- **Verification (staged):** On the lab network, run **one** target first and confirm Network Connections appears on that host’s screen; then **two** targets with a non-zero delay and confirm order; then a broader run if desired. Confirm job CSV columns: `RemoteSessionAttempted`, `NcpaLaunchAttempted`, `NcpaSuccess`, `MstscLaunched`, `Success`, `Message`.
- **CLI dry-run:** `.\orchestrate-open-ncpa.ps1 -TargetIP 192.168.22.221 -Username admin -Password ... -CsvPath ... -TranscriptPath ... -DryRun`

## Artifact Usage
The GUI reuses the existing toolkit output folders under `C:\Test House BE200 control\output` for:
- remoting CSV
- discovery CSV/JSON/transcript
- validation report + validated config
- apply results CSV/JSON
- rollback CSV/JSON
- apply transcript
- open-ncpa result CSV + transcript (`gui-open-ncpa-results-*.csv`, `gui-orchestrate-open-ncpa-*.log` under `output`)

Generated GUI config CSVs are created under:
- `C:\Test House BE200 control\gui\work\configs`

## Notes
- The GUI expects credentials to be entered in the form for discovery, remoting, or apply actions.
- Passwords are not persisted in the GUI history.
- If discovery data is stale, refresh discovery before editing properties.

# Restart + RDP workflow

## Route

- GUI path: `/system-restart-rdp`
- Nav: **System** → **Restart + RDP**

## Accepted scope

- **In scope:** `192.168.22.221`–`192.168.22.228` only (same allowlist as the rest of the console).
- **Never targeted:** `192.168.22.8` (controller). Requests including it are rejected in the GUI and in `orchestrate-restart-rdp.ps1`.

## What it does

1. **OS restart:** WinRM `Invoke-Command` runs `Restart-Computer -Force` on each selected host (sequential issuance, 2 s apart).
2. **Wait:** Grace period (default 15 s), then **ICMP ping** until each host responds or per-host timeout (default 10 minutes).
3. **Optional:** TCP **3389** check via `Test-NetConnection` when enabled — confirms a listener, **not** successful RDP authentication.
4. **RDP:** If **Automatically open RDP** is checked, `mstsc.exe /v:<ip>` runs **in order of target selection**, with a delay between launches. Otherwise use **Launch RDP** on the job detail page for ping-recovered hosts.

## Success meaning

- **Ping recovered:** Host answered ICMP within the timeout (firewall may still block RDP).
- **RDP port Yes:** TCP connect to 3389 succeeded (optional).
- **RDP launched:** `mstsc` was started from the controller session (automatic or manual from job detail).

Partial success is normal if some hosts fail restart or miss the ping window.

## Artifacts

- CSV result grid and PowerShell transcript paths are stored on the job record (see **Job detail**).

## Caveats

- Ping can return before services (including RDP) are fully ready.
- `mstsc` runs **on the machine where the Flask GUI process runs** (typically `192.168.22.8`); it does not run inside remote sessions.
- Long runs may require `restart_rdp_timeout_seconds` in `gui/config.json` (default 7200).

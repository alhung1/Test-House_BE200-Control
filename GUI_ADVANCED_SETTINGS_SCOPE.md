# GUI Advanced Settings Scope

## Purpose
This note defines the broadest BE200 advanced-settings scope that was safely provable through the GUI and validated PowerShell toolkit on `192.168.22.8`.

It separates:
- live-tested and accepted properties
- deferred properties
- accepted modes
- accepted operational-action scope
- hard operator boundaries

## Current Reference Artifacts
Latest refreshed discovery and matrix artifacts from the final acceptance pass:
- Discovery CSV: `C:\Test House BE200 control\output\csv\gui-be200-discovery-20260325-140956-102881.csv`
- Discovery JSON: `C:\Test House BE200 control\output\json\gui-be200-discovery-20260325-140956-103049.json`
- Config template CSV: `C:\Test House BE200 control\output\csv\gui-be200-config-template-20260325-141004-438142.csv`
- Property matrix CSV: `C:\Test House BE200 control\output\csv\gui-be200-property-matrix-20260325-141005-147679.csv`
- Property matrix JSON: `C:\Test House BE200 control\output\json\gui-be200-property-matrix-20260325-141005-147800.json`
- Restart promotion summary JSON: `C:\Test House BE200 control\output\json\gui-restart-promotion-summary-20260325-210637.json`

Matrix totals from the final refresh:
- 91 discovered advanced properties total
- 24 operator-visible properties live-tested and accepted
- 67 deferred properties
- 0 validation-only operator-visible properties remaining

## Fixed Scope Boundaries
Accepted target scope:
- `192.168.22.221` through `192.168.22.228`

Accepted adapter scope:
- `Intel(R) Wi-Fi 7 BE200 320MHz`
- `Intel(R) Wi-Fi 7 BE200 320MHz #6`

Never accepted:
- any other target
- any other adapter
- Ethernet changes
- IP, gateway, DNS, route, metric, or proxy changes
- raw command execution

## Final Property Classes
### Live-Tested And Accepted
These 24 operator-visible properties were exercised through the GUI apply path with validation, real apply, read-back verification, and rollback.

Final accepted property mode set:
- `WriteOnly`: accepted for all 24 operator-visible properties across all 8 allowlisted targets
- `RestartBE200`: accepted for all 24 operator-visible properties across all 8 allowlisted targets

Final accepted properties:
- `Preferred Band` / `RoamingPreferredBandType`
- `Roaming Aggressiveness` / `RoamAggressiveness`
- `U-APSD support` / `uAPSDSupport`
- `Throughput Booster` / `ThroughputBoosterEnabled`
- `Fat Channel Intolerant` / `FatChannelIntolerant`
- `Channel-Load usage for AP Selection` / `EnableChLoad4ApSelection`
- `Mixed Mode Protection` / `CtsToItself`
- `Transmit Power` / `IbssTxPower`
- `Channel Width for 2.4GHz` / `ChannelWidth24`
- `Channel Width for 5GHz` / `ChannelWidth52`
- `Channel Width for 6GHz` / `ChannelWidth6`
- `MIMO Power Save Mode` / `MIMOPowerSaveMode`
- `802.11a/b/g Wireless Mode` / `WirelessMode`
- `802.11n/ac/ax/be Wireless Mode` / `IEEE11nMode`
- `Ultra High Band (6GHz)` / `Is6GhzBandSupported`
- `ARP offload for WoWLAN` / `*PMARPOffload`
- `GTK rekeying for WoWLAN` / `*PMWiFiRekeyOffload`
- `NS offload for WoWLAN` / `*PMNSOffload`
- `Packet Coalescing` / `*PacketCoalescing`
- `RSCv4` / `*RscIPv4`
- `RSCv6` / `*RscIPv6`
- `Sleep on WoWLAN Disconnect` / `*DeviceSleepOnDisconnect`
- `Wake on Magic Packet` / `*WakeOnMagicPacket`
- `Wake on Pattern Match` / `*WakeOnPattern`

### Deferred
The remaining 67 discovered properties remain deferred.

Deferred scope consists of:
- registry-only or informational entries without a stable operator-facing display label
- non-operator-visible properties that were not promoted into GUI apply scope

Deferred means:
- discovery and matrix visibility are preserved
- the property remains visible for audit and inventory purposes
- the GUI does not treat it as an accepted live apply path

## Risk Interpretation
- `low`: reversible behavior change with successful GUI write, read-back, rollback, and fleet restart evidence
- `medium`: property is manageable but still warrants deliberate staged operator discipline
- `high`: property can materially affect RF, protocol, sleep/wake, or driver behavior, but it was accepted only after successful GUI-driven all-8 restarted rollout and rollback evidence

## GUI Behavior
Inventory page:
- shows all discovered properties
- shows coverage counts
- shows classification and risk
- shows BE200 driver version (`DriverVersion`) and driver date (`DriverDate`) per target, extracted from the current discovery snapshot
- exposes `Status`, `Restart`, `Disable`, and `Enable` only within the final action boundaries
- embeds action-policy data so the form disables unsafe action choices for the currently selected targets

Property editor:
- supports multi-property configuration: operators can add multiple property rows in a single run, each with its own target value
- the property selector shows only the 24 live-tested accepted properties; deferred and validation-only properties are not listed
- shows discovered values when available for each property row
- all property rows share the same target set and mode
- the GUI blocks validation if any selected property is not live-tested or if the mode is not in the accepted mode set for all selected properties
- allows real apply only when:
  - all selected properties are live-tested
  - the selected mode is in the accepted mode list for all selected properties (intersection)
  - validation completed successfully with all rows valid and no skipped or invalid rows
- no property combinations have been found to be unsafe; all 24 accepted properties can be freely combined in a single run

History and results:
- multi-property jobs store property count, all property labels, registry keywords, targets, mode, and classification in job summaries
- per-property, per-target result rows are visible in job detail
- preserve rollback artifacts for apply jobs covering all properties in the run
- preserve operational-action result rows and transcripts for action jobs

## Live Evidence Summary
Property evidence:
- all 24 operator-visible properties had prior GUI-driven `.221` and `.221/.222` validation/apply/read-back/rollback evidence
- `Throughput Booster` completed an explicit all-8 `RestartBE200` pilot before the broader promotion batch
- the remaining 23 operator-visible properties then completed full all-8 `RestartBE200` apply, remoting continuity, read-back, grouped rollback where required, and final read-back restoration
- the two mixed-baseline properties, `WirelessMode` and `IEEE11nMode`, were promoted successfully with grouped rollback based on original target-specific values

Resulting property truth:
- no operator-visible properties remain `WriteOnly`-only
- no operator-visible properties remain `validation-only`
- no operator-visible properties are blocked from `RestartBE200`

Multi-property evidence:
- 1 target, 2 properties (`Preferred Band` + `Roaming Aggressiveness`), WriteOnly: validated, applied, verified, rolled back
- 1 target, 3 properties (`Throughput Booster` + `Fat Channel Intolerant` + `U-APSD support`), WriteOnly: validated, applied, verified, rolled back
- 2 targets, 2 properties (`Channel Width for 2.4GHz` + `MIMO Power Save Mode`), WriteOnly: validated, applied (4 rows), verified, rolled back
- 1 target, 2 properties (`Transmit Power` + `Channel Width for 5GHz`), RestartBE200: validated, applied, verified, rolled back
- no property combinations were found to be unsafe or blocked

## Operational Actions
Final accepted action scope:
- `Status`: up to all 8 targets per run across `192.168.22.221-228`
- `Restart`: up to all 8 targets per run across `192.168.22.221-228` (confirmation required)
- `Disable`: up to all 8 targets per run across `192.168.22.221-228` (confirmation required)
- `Enable`: up to all 8 targets per run across `192.168.22.221-228` (confirmation required)

Multi-target acceptance evidence:
- 2-target subset (`.221` + `.222`): all 4 actions passed with per-target success and remoting continuity
- 4-target subset (`.221` - `.224`): all 4 actions passed with per-target success and remoting continuity
- all-8 targets (`.221` - `.228`): all 4 actions passed with per-target success and remoting continuity
- multi-target Disable followed by multi-target Enable: saved adapter identity resolved correctly per target at each stage

Disable/Enable redesign:
- the toolkit persists the exact BE200 adapter identity resolved during `Disable` for each target
- `Enable` reuses that saved identity instead of trying to infer the adapter from a fresh ambiguous disabled-state snapshot
- this works correctly even when multiple targets are disabled and re-enabled in a single run

Action-gating fix (resolved):
- a previous browser-side bug caused the operation value to be dropped when the selected `<option>` was disabled by JavaScript policy logic, resulting in an incorrect "not accepted in the current GUI scope" error
- the fix added a hidden mirror input (`operation_mirror`) that stays in sync with the select via JavaScript, a client-side submission guard, and a server-side fallback in `app.py`
- all four accepted actions now work correctly through the GUI for single-target and multi-target use

Stable identifiers used by the final reversible `Disable` / `Enable` path:
- `Name`
- `InterfaceDescription`
- `MacAddress`
- `ifIndex`
- `PnPDeviceID`

Final action evidence (single-target, proven in prior passes):
- `Disable` and `Enable` completed successfully on each of `192.168.22.221` through `192.168.22.228` individually
- management Ethernet stayed `Up`
- remoting stayed usable
- discovery succeeded again after re-enable

Final action evidence (multi-target, proven in this pass):
- 2-target: Status, Restart, Disable, Enable all succeeded on `.221` + `.222` with per-target results and remoting continuity
- 4-target: Status, Restart, Disable, Enable all succeeded on `.221` - `.224` with per-target results and remoting continuity
- all-8: Status, Restart, Disable, Enable all succeeded on `.221` - `.228` with per-target results and remoting continuity
- Disable/Enable saved-identity resolution worked correctly when all 8 targets were disabled and re-enabled in a single run

## Wi-Fi Connect and Status

### Feature scope
Two new GUI pages provide Wi-Fi connection management for the managed BE200 adapters:
- **Wi-Fi Connect** (`/wifi-connect`): connect BE200 adapters to a specified SSID, or verify current connection against an expected SSID
- **Wi-Fi Status** (`/wifi-status`): read-only view of Wi-Fi state, SSID, radio type, signal, and authentication across all targets

### Technical implementation
Backend script: `invoke-be200-wifi.ps1` (new)
- Actions: `Connect`, `Verify`, `Status`
- Uses `Invoke-Command` per target with the same `Resolve-BE200TargetIPs`, `Resolve-BE200Credential`, and allowlist logic as existing toolkit scripts
- Adapter resolution: finds the BE200 adapter via `Get-NetAdapter` using the allowlisted `InterfaceDescription`, then resolves the corresponding `netsh wlan` interface by matching the `Description` field in `netsh wlan show interfaces`
- Connect: generates a temporary Wi-Fi profile XML (WPA2PSK/AES if password provided; open/none otherwise), adds it via `netsh wlan add profile`, connects via `netsh wlan connect`, waits 5 seconds, then checks connection state
- Verify/Status: parses `netsh wlan show interfaces` to extract state, SSID, radio type, signal, authentication, and channel
- Temp profile XML is deleted immediately after `netsh wlan add profile`
- Results exported as CSV per target with all fields

Service layer: `run_wifi_job()` and `summarize_wifi_results()` in `services.py`
- `redact_command()` updated to redact both `-Password` and `-WiFiPassword`

### Accepted Wi-Fi scope
- Targets: `192.168.22.221` through `192.168.22.228`
- Adapter scope: allowlisted BE200 interface descriptions only
- Authentication: Open and WPA2-Personal (SSID + optional password)
- Actions: Connect, Verify, Status
- Multi-target: supported (all 8 targets per run)

### Success criteria
- **Connect**: `State` = `connected` and `SSID` matches the requested SSID. No deeper connectivity check (ping, DNS, HTTP) is used. Success is determined solely from `netsh wlan show interfaces` output after a 5-second post-connect wait.
- **Verify**: `State` = `connected` and actual SSID matches the expected SSID. Failure if disconnected or SSID mismatch.
- **Status**: per-target row returned with adapter name, state, SSID, radio type, signal, authentication, and channel. `Success` = `True` when retrieved without error.
- **Failure reporting**: any failure populates the `Message` column with the specific reason (e.g., adapter disabled, SSID not visible, WinRM error, no BE200 adapter found).

### Live verification evidence
- Single-target Status on `.221`: `State=connected`, `SSID=WBE700v2-5G`, `RadioType=802.11be`, `Signal=97%`
- All-8 Status: 7 connected (mix of `WBE700v2-5G` and `WBE700v2-2G`), 1 disconnected (`.222`), all returned `RadioType=802.11be`
- Single-target Connect on `.222` to `WBE700v2-2G` (open network): `State=connected`, `SSID=WBE700v2-2G`, `Success=True`, `RadioType=802.11be`, `Signal=95%`, `Channel=10`
- Single-target Verify on `.222` against `WBE700v2-2G`: `Success=True`, verified connected to expected SSID
- Multi-target Connect on `.223` + `.224` to `WBE700v2-5G`: both `Success=True`, `State=connected`
- GUI-based tests: Wi-Fi Status page rendered 8 target rows with radio type; Wi-Fi Connect page showed inline results with success badges; Wi-Fi Verify page confirmed connection
- Password redaction verified: `-Password` and `-WiFiPassword` both show `********` in all job records; no password leaks in stdout

### Caveats
- The SSID must be visible on the target's scan for Connect to succeed; out-of-range networks will show a successful connection request but the adapter remains disconnected
- Description-based matching between `Get-NetAdapter` and `netsh wlan show interfaces` handles ghost adapter name mismatches
- The feature does not delete, forget, or manage Wi-Fi profile priority; it only adds/updates and connects
- Enterprise authentication (802.1X, EAP, RADIUS) is not supported in this version

## Launcher
One-click launcher:
- `C:\Test House BE200 control\launch-be200-gui.ps1`

Verified launch command:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Test House BE200 control\launch-be200-gui.ps1"
```

Launcher behavior:
- starts the GUI if it is not already running
- collapses duplicate GUI processes to a single surviving instance when possible
- re-launches the GUI if an existing process is present but not listening
- opens the local GUI URL unless `-NoBrowser` is supplied
- uses `py -3`

## Rollback Guidance
For every real apply job:
- review the job in `History`
- open `Job Detail`
- record the rollback CSV and rollback JSON artifact paths
- use the rollback artifacts as the authoritative source if a manual recovery step is ever required

Normal operator expectation:
- validate first
- apply only within accepted scope
- confirm read-back or job verification
- retain rollback artifacts
- for `Disable` / `Enable`, always follow a multi-target `Disable` with a matching `Enable` on the same targets and verify all per-target results before proceeding

## Existing Workflow Integrity
The Wi-Fi Connect / Verify / Status feature is implemented as a separate workflow with its own script (`invoke-be200-wifi.ps1`), service functions, routes, and templates. It does not modify, replace, or interfere with any existing accepted workflow:
- Advanced-property discovery, validation, apply, and rollback paths are unchanged.
- Operational actions (Status, Restart, Disable, Enable) via `invoke-be200-action.ps1` are unchanged.
- The property editor, current-settings page, inventory page, and history/job-detail views are unchanged.
- `config.json` property and action policy overrides are unchanged.
- All GUI pages that existed before the Wi-Fi addition continue to return HTTP 200 and function as documented.

## Residual Caveats
- `.226` still has a known `SwRadioState` discovery variance
- immediate post-restart discovery can temporarily lag actual adapter state
- immediate post-disable discovery will intentionally show the BE200 adapter absent until `Enable` runs; when multiple targets are disabled in one run, all affected targets need re-enabling
- the property matrix is authoritative for classification, but deferred entries are not permission for live operator apply
- driver version and date in the inventory come from the `DriverVersion` and `DriverDate` registry keywords in the discovery snapshot; if a target has no discovery data, the version shows as "Unknown"

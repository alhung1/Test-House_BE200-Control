# Real-Machine Validation Report

Date: 2026-04-21
Controller workspace: `C:\Test House BE200 control`
Validation scope: local GUI launcher, live GUI pages, GUI backend jobs, selected GUI route posts, and real target operations against `192.168.22.221` plus safe read-only checks across `192.168.22.221`-`192.168.22.228`.

## Summary

Overall status: `partial pass`

What passed:

- local GUI launcher and live page rendering
- remoting reachability and discovery execution
- Wi-Fi status across all eight targets
- Wi-Fi connect and verify on `192.168.22.221`
- Open NCPA on `192.168.22.221`
- Restart + RDP on `192.168.22.221`
- GUI route submission for inventory jobs and editor apply redirect flow
- validation and before/after report export using a known-good discovery snapshot

What was safely blocked:

- property apply on `192.168.22.221`
- BE200 `Status / Disable / Enable / Restart` action workflows on `192.168.22.221`

Why those were blocked:

- the toolkit detected multiple allowlisted BE200 adapter matches on `192.168.22.221` and skipped to avoid ambiguity

## Environment Checks

- `WinRM` service on controller: running
- `TrustedHosts`: exact allowlist `192.168.22.221`-`192.168.22.228`
- `Ping`: 8/8 reachable
- `Test-WSMan`: 8/8 reachable
- GUI launcher: started successfully and served `http://127.0.0.1:5000/`

## Live GUI Checks

Live GUI pages returned `HTTP 200`:

- `/`
- `/inventory`
- `/editor`
- `/current-settings`
- `/wifi-connect`
- `/wifi-status`
- `/open-ncpa`
- `/system-restart-rdp`
- `/history`

GUI launcher validation:

- `launch-be200-gui.ps1` started successfully in a child PowerShell process
- local root page responded successfully while the launcher-owned process was running

## Real Job Results

### 1. Remoting test across all eight targets

Result: `partial`

- `6/8` targets met the GUI success rule `Reachable + BE200AdapterFound`
- `192.168.22.221` and `192.168.22.227` reported `BE200AdapterFound = False`

Artifact:

- `output\csv\gui-test-remoting-summary-20260421-180403-711246.csv`

### 2. Discovery refresh across all eight targets

Result: `success`

- discovery CSV, JSON, transcript, template CSV, and property matrix were generated
- summary reported `91` total properties, `24` live-tested, `67` deferred

Artifacts:

- `output\csv\gui-be200-discovery-20260421-180415-129300.csv`
- `output\json\gui-be200-discovery-20260421-180415-129411.json`
- `output\transcripts\gui-discover-be200-advanced-properties-20260421-180415-129509.log`

### 3. Wi-Fi status across all eight targets

Result: `success`

- `8/8` rows succeeded
- `5/8` targets were connected at test time
- `3/8` targets were disconnected at test time

Notable state:

- `192.168.22.221` was initially disconnected
- most connected systems were already on `OpenWrt_6G`

Artifact:

- `output\csv\gui-be200-wifi-status-20260421-180423-283901.csv`

### 4. Wi-Fi verify before connect on `192.168.22.221`

Result: `failed`

- expected and correct: target was disconnected before connect

Artifact:

- `output\csv\gui-be200-wifi-verify-20260421-180430-604113.csv`

### 5. Property validate/apply test on `192.168.22.221`

Property: `Roaming Aggressiveness`
Mode tested:

- validation using `WriteOnly` input
- apply using `WriteOnly`

Validation result: `success`

- the generated config validated successfully using discovery snapshot `gui-be200-discovery-20260421-180415-129300.csv`

Apply result: `failed`, but safely

- the toolkit did not make a silent or ambiguous change
- apply row notes reported:
  - `Multiple adapters matched allowlisted InterfaceDescription 'Intel(R) Wi-Fi 7 BE200 320MHz' with Status 'Disconnected'. Skipping to avoid ambiguity.`

Interpretation:

- this is a real-machine safety block, not a GUI crash
- `.221` is not currently in a clean enough adapter state for BE200 property apply or action workflows

Artifacts:

- `output\csv\gui-be200-validation-report-20260421-180520-262008.csv`
- `output\csv\gui-be200-validated-config-20260421-180520-262113.csv`
- `output\csv\gui-be200-apply-results-20260421-180520-687739.csv`
- `output\csv\gui-be200-rollback-data-20260421-180520-687944.csv`
- `output\reports\manual-forward-report.csv`

### 6. BE200 action workflows on `192.168.22.221`

Tested:

- `Status`
- `Disable`
- `Enable`
- `Restart`

Result for all four: `failed`, but safely

Common reason:

- multiple allowlisted BE200 adapter matches on `.221`
- no single safe adapter resolution was available for the action scripts

Interpretation:

- the GUI/backend behavior is correct and safety-preserving
- `.221` currently cannot be used as a clean single-adapter action target without resolving the ambiguity on that machine first

### 7. Wi-Fi connect on `192.168.22.221`

SSID: `OpenWrt_6G`

Result: `success`

- connect succeeded
- immediate verify succeeded
- reported signal: `99%`
- radio type: `802.11be`
- authentication: `WPA3-Personal (H2E)`

Artifacts:

- `output\csv\gui-be200-wifi-connect-20260421-180621-339226.csv`
- `output\csv\gui-be200-wifi-verify-20260421-180627-942031.csv`

### 8. Open NCPA on `192.168.22.221`

Result: `success`

- remote session attempted: yes
- `ncpa.cpl` launch success: yes
- local `mstsc` launch recorded: yes

Artifact:

- `output\csv\gui-open-ncpa-results-20260421-180638-655465.csv`

### 9. Restart + RDP on `192.168.22.221`

Result: `success`

- OS restart issued: yes
- ping recovered: yes
- recovery time: `44` seconds
- TCP 3389 open: yes
- local `mstsc` launch recorded: yes

Artifact:

- `output\csv\gui-restart-rdp-results-20260421-180651-841471.csv`

## Live GUI Route Submission Checks

Validated with real credentials and real backend execution:

- `/inventory` `run_remoting` -> redirected to job detail
- `/inventory` `refresh_discovery` -> redirected to job detail
- `/editor` `validate` -> rendered validation summary correctly when pointed at a discovery snapshot that actually contained the property
- `/editor` `apply` -> redirected to job detail and preserved the safe apply failure
- `/wifi-status` POST rendered results page
- `/wifi-connect` verify POST rendered results page

Important nuance:

- one later discovery snapshot did not contain `Roaming Aggressiveness` for `.221`, so editor validation correctly blocked when using that newer snapshot
- this was a data consistency issue between snapshots, not a route crash

## Findings

### Finding 1: `.221` has unresolved BE200 adapter ambiguity for property apply and action workflows

Impact:

- property apply on `.221` cannot proceed
- `Status / Disable / Enable / Restart` on `.221` cannot proceed

Observed behavior:

- the toolkit correctly skipped instead of guessing

Risk:

- operator workflows that depend on single-adapter resolution for `.221` will remain blocked until the target is cleaned up or the matching logic is further refined

### Finding 2: Remoting test and discovery do not currently tell the same story for every host

Impact:

- remoting reported `.221` and `.227` as not finding a BE200 adapter
- other workflows, especially Wi-Fi on `.221`, clearly did resolve a BE200 target path

Risk:

- operators may see a `partial` remoting health signal while some downstream workflows still work

## Conclusion

The redesigned GUI is stable enough to open and use locally. The launcher works, the live pages load, the major non-destructive flows work, and the highest-risk workflow tested here, `Restart + RDP`, completed successfully on `.221`.

The main blocker is not the GUI itself. It is the real adapter state on `192.168.22.221`: that host currently presents an ambiguous allowlisted BE200 situation for property apply and BE200 action workflows, and the toolkit correctly refuses to guess.

Recommendation:

- accept the GUI redesign as operationally usable for discovery, Wi-Fi workflows, Open NCPA, Restart + RDP, history, and general monitoring
- do not consider `.221` ready for property apply or BE200 action workflows until the adapter ambiguity on that target is resolved

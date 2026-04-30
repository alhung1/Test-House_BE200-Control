# Validation Guide

This guide defines a staged manual validation plan before any later manual deployment to `192.168.22.8`.

The intended sequence is:

1. Create and review the toolkit locally
2. Validate locally against the lab targets
3. Decide whether the toolkit is ready to be copied manually to `192.168.22.8`

Do not deploy to `192.168.22.8` until every relevant phase below is complete and you are satisfied with the results.

## Phase 1: Static Review

Review the scripts and documentation before running anything.

Checklist:

- Review every public entry script at the toolkit root.
- Review `internal/BE200Toolkit.Common.psm1`.
- Confirm the exact BE200 adapter allowlist is hard-coded:
  - `Intel(R) Wi-Fi 7 BE200 320MHz`
  - `Intel(R) Wi-Fi 7 BE200 320MHz #6`
- Confirm the exact target IP allowlist is hard-coded:
  - `192.168.22.221` through `192.168.22.228`
- Confirm skip-on-ambiguity behavior exists in discovery, validation, apply, and action flows.
- Review that plaintext password support is clearly marked as less secure.
- Review that plaintext passwords are not written to CSV, JSON, reports, or transcripts.

Explicit forbidden-command review:

- Search the repository for the forbidden layer-3 network-modification commands from the requirements.
- Confirm none of those commands are present in the implementation.

## Phase 2: Remoting Validation

Validate remoting in the smallest safe sequence first.

### 2.1 Controller preparation

Run on the controller machine:

```powershell
.\setup-local-remoting.ps1
```

Confirm:

- WinRM is running
- PowerShell remoting is enabled
- TrustedHosts contains exactly the eight lab target IPs
- no network layer-3 settings were changed

### 2.2 Remote bootstrap

RDP into one remote target first and run:

```powershell
.\setup-remote-remoting.ps1
```

Confirm:

- WinRM is running
- PowerShell remoting is enabled
- WinRM firewall rules are enabled
- no BE200 settings were changed
- no IP/DNS/gateway/route settings were changed

Repeat for the remaining remote targets only after the first target behaves as expected.

### 2.3 Remoting test

Run from the controller:

```powershell
.\test-remoting.ps1
```

Confirm:

- each target reports either a clean success result or a clear failure reason
- the summary CSV is generated
- BE200 presence detection matches reality

## Phase 3: Discovery Validation

Run discovery from the controller:

```powershell
.\discover-be200-advanced-properties.ps1
```

Confirm:

- only the exact BE200 adapter names are queried
- discovery completes across all reachable targets
- discovery CSV and JSON are generated
- transcript logging is generated
- property rows look consistent with actual BE200 advanced properties on the targets
- differences between 24H2 and 25H2 systems are handled as data differences, not as failures

Then export the template:

```powershell
.\export-be200-config-template.ps1 -DiscoveryPath <discovery-file>
```

Confirm:

- the template is editable CSV
- the template includes the required columns
- the template preserves both `RegistryKeyword` and `PropertyDisplayName`
- `Apply` defaults to `FALSE`
- generated rows reflect discovery output accurately

## Phase 4: Safe Apply Validation

Start with the lowest-risk path.

### 4.1 Validate the edited config

```powershell
.\validate-be200-config.ps1 -ConfigPath <template-file> -DiscoveryPath <discovery-file>
```

Confirm:

- valid rows, skipped rows, and invalid rows are clearly separated
- invalid rows contain clear reasons
- ambiguous rows are skipped rather than guessed
- a validated config CSV is generated

### 4.2 Dry-run first

```powershell
.\apply-be200-config.ps1 -ValidatedConfigPath <validated-config-file> -Mode WriteOnly -WhatIf
```

Confirm:

- no changes are actually made
- dry-run results are still exported
- targeting and adapter safeguards still hold

### 4.3 Test one property on one machine

Pick one low-risk BE200 advanced property and one target machine first.

Run:

```powershell
.\apply-be200-config.ps1 -ValidatedConfigPath <validated-config-file> -Mode WriteOnly
```

Confirm:

- the intended property was targeted
- only the exact allowlisted BE200 adapter was touched
- no non-BE200 adapters were touched
- no Ethernet adapters were touched
- results CSV and JSON were generated
- rollback CSV and JSON were generated

Then export the before/after report:

```powershell
.\export-be200-before-after-report.ps1 -ApplyResultsPath <apply-results-file>
```

Confirm:

- `OriginalValue`, `TargetValue`, and `FinalValue` are clear
- `ApplySucceeded` and `VerificationSucceeded` reflect actual behavior

### 4.4 Restart mode validation

Only after `WriteOnly` mode behaves correctly, test:

```powershell
.\apply-be200-config.ps1 -ValidatedConfigPath <validated-config-file> -Mode RestartBE200
```

Confirm:

- only the exact BE200 adapter is restarted
- re-read verification happens after restart
- no other adapters are restarted

## Phase 5: Operational Action Validation

Start with one machine first.

### 5.1 Status

```powershell
.\invoke-be200-action.ps1 -Action Status -TargetIP 192.168.22.221
```

Confirm:

- status queries only the allowlisted BE200 adapter names
- action CSV and transcript are generated

### 5.2 Disable and Enable

```powershell
.\invoke-be200-action.ps1 -Action Disable -TargetIP 192.168.22.221
.\invoke-be200-action.ps1 -Action Enable -TargetIP 192.168.22.221
```

Confirm:

- confirmation prompts appear unless `-Force` is used
- only the exact BE200 adapter is affected
- the remote management path remains available through the separate management connectivity

### 5.3 Restart

```powershell
.\invoke-be200-action.ps1 -Action Restart -TargetIP 192.168.22.221
```

Confirm:

- only the allowlisted BE200 adapter is restarted
- status transitions make sense before and after the action

## Phase 6: Limited Batch Validation

Before touching all eight targets, test a small subset.

Recommended progression:

1. One machine
2. Two machines
3. Small subset such as three or four machines
4. All eight machines only after the smaller batches are satisfactory

For each expansion step, confirm:

- no unintended adapter targeting
- no ambiguous rows being applied
- logs and exports remain clear and complete
- failures remain isolated per machine

## Phase 6A: Optional GUI Validation

Complete this phase only if the local GUI under `gui\` is intended to be part of the accepted operator workflow on the controller.

### 6A.1 GUI startup and local safety

Launch the GUI locally:

```powershell
.\launch-be200-gui.ps1
```

Confirm:

- the GUI binds only to the expected local host and port
- the GUI shows only the exact allowlisted targets
- no arbitrary target IP entry is possible through the GUI
- the GUI starts without changing any target state by itself

### 6A.2 GUI discovery, validation, and apply path

Using the GUI:

- run remoting test
- refresh discovery
- generate a config through the property editor
- run validation
- only then run a real apply for a low-risk property on a single target

Confirm:

- the GUI still routes through the same toolkit scripts as the CLI workflow
- validation blocks real apply when rows are invalid or skipped
- job detail shows command, stdout, stderr, and artifact paths
- job status is clear to the operator:
  - `success` when all relevant result rows succeeded
  - `partial` when only some result rows succeeded
  - `failed` when the process failed or no result rows succeeded

### 6A.3 GUI resilience checks

Confirm:

- a long-running GUI-triggered job that exceeds its timeout is recorded as a failed job rather than surfacing only as an unhandled web error
- GUI history survives restart and remains readable
- if `gui\data\history.json` becomes corrupt, the GUI recovers safely and continues with a fresh history index
- the Flask session secret is not hard-coded as a shared fixed value in committed config; prefer `BE200_GUI_SECRET_KEY`, otherwise confirm a local generated secret file is used

### 6A.4 Optional GUI-specific workflows

If the GUI pages are intended for operator use, also validate the accepted GUI-only wrappers:

- `Wi-Fi Connect`
- `Wi-Fi Status`
- `Restart + RDP`
- `Open NCPA`

Confirm:

- each page stays within the same allowlisted target scope
- each workflow exports clear per-target results
- failures are shown per target and do not silently appear as full success

## Phase 7: Deployment Readiness Decision

Only after manual validation succeeds should the toolkit be copied to `192.168.22.8`.

Decision checklist:

- Static review complete
- Forbidden commands confirmed absent
- Remoting setup validated
- Discovery validated
- Template and validation flow validated
- Dry-run apply validated
- `WriteOnly` mode validated
- `RestartBE200` mode validated
- Operational actions validated
- Limited batch validation complete
- GUI validation complete if GUI is part of the accepted operator path

If any of those checks are incomplete or unsatisfactory, do not deploy to `192.168.22.8` yet.

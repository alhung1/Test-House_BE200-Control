# BE200 Toolkit

This toolkit is a PowerShell-based remote management and validation toolkit for Windows 11 test machines that expose an Intel BE200 Wi-Fi adapter.

The toolkit is built for local creation, local review, and staged self-validation first.

It is intentionally not a deployment pipeline.

It does not:
- auto-deploy to `192.168.22.8`
- copy itself to `192.168.22.8`
- auto-run on `192.168.22.8`
- modify controller or remote layer-3 network settings

## Purpose

The toolkit supports three stages:

1. Remoting foundation and discovery
2. Intel BE200 advanced setting apply
3. Intel BE200 operational control

The controller-side concept is currently your local development workspace. Deployment to `192.168.22.8` is intentionally deferred until after you complete manual validation.

## Safety Model

The toolkit is safe by default and enforces these rules throughout:

- Exact target allowlist only:
  - `192.168.22.221`
  - `192.168.22.222`
  - `192.168.22.223`
  - `192.168.22.224`
  - `192.168.22.225`
  - `192.168.22.226`
  - `192.168.22.227`
  - `192.168.22.228`
- Exact adapter allowlist only:
  - `Intel(R) Wi-Fi 7 BE200 320MHz`
  - `Intel(R) Wi-Fi 7 BE200 320MHz #6`
- Skip on ambiguity, never guess
- No automatic rollback
- No layer-3 network reconfiguration
- No Ethernet adapter changes
- No non-BE200 adapter changes

## Forbidden Commands Intentionally Not Used

The toolkit is designed to keep the forbidden layer-3 network-modification commands from the requirements absent from the implementation.

## Credential Handling

Controller-side scripts that connect to remote targets support three credential paths:

1. Preferred non-interactive path: pass `-Credential` with a `PSCredential`
2. Default path: omit `-Credential` and get a secure prompt
3. Lab convenience path: pass `-Username admin -Password password`

Notes:

- Plaintext password input is less secure and is intended for lab use only.
- Plaintext passwords are converted to `SecureString` in memory immediately.
- The toolkit does not write plaintext passwords to transcripts, CSV, JSON, or reports.

## File Layout

Public entry scripts at the toolkit root:

- `setup-local-remoting.ps1`
- `setup-remote-remoting.ps1`
- `test-remoting.ps1`
- `discover-be200-advanced-properties.ps1`
- `export-be200-config-template.ps1`
- `validate-be200-config.ps1`
- `apply-be200-config.ps1`
- `invoke-be200-action.ps1`
- `invoke-be200-wifi.ps1`
- `orchestrate-restart-rdp.ps1`
- `orchestrate-open-ncpa.ps1`
- `launch-be200-gui.ps1`
- `export-be200-before-after-report.ps1`

Shared logic:

- `internal/BE200Toolkit.Common.psm1`

Documentation:

- `README.md`
- `VALIDATION_GUIDE.md`
- `DEPLOYMENT_NOTES.md`
- `gui\README.md`

Optional local GUI wrapper:

- `gui\app.py`
- `gui\services.py`
- `gui\templates\`
- `gui\config.json`
- `gui\start-gui.ps1`

## What Runs Where

Run on the controller machine:

- `setup-local-remoting.ps1`
- `test-remoting.ps1`
- `discover-be200-advanced-properties.ps1`
- `export-be200-config-template.ps1`
- `validate-be200-config.ps1`
- `apply-be200-config.ps1`
- `invoke-be200-action.ps1`
- `invoke-be200-wifi.ps1`
- `orchestrate-restart-rdp.ps1`
- `orchestrate-open-ncpa.ps1`
- `launch-be200-gui.ps1`
- `export-be200-before-after-report.ps1`

Run once locally on each remote PC after RDP sign-in as Administrator:

- `setup-remote-remoting.ps1`

Optional local GUI run path:

- start from `launch-be200-gui.ps1` at the toolkit root, or from `gui\start-gui.ps1`
- the GUI is a local wrapper around the same PowerShell toolkit scripts
- detailed GUI usage and page-level notes live in `gui\README.md`

## Recommended Execution Order

1. Prepare the controller remoting foundation.
2. Prepare remoting on each remote target locally.
3. Test remoting from the controller.
4. Discover BE200 advanced properties.
5. Export an editable config template.
6. Edit the template manually.
7. Validate the edited template.
8. Dry-run apply with `-WhatIf`.
9. Apply in `WriteOnly` mode for low-risk testing.
10. Export a before/after report.
11. Apply in `RestartBE200` mode only after you are satisfied with `WriteOnly` results.
12. Use operational actions for `Status`, `Disable`, `Enable`, or `Restart` as needed.

## Stage 1: Remoting Foundation and Discovery

### 1. Prepare the controller

```powershell
.\setup-local-remoting.ps1
```

What it does:

- enables WinRM
- sets WinRM startup type
- enables PowerShell remoting
- sets `TrustedHosts` to exactly the eight lab target IPs

What it does not do:

- no IP/DNS/gateway/route changes
- no adapter changes
- no deployment

### 2. Prepare each remote target

Run locally on each target after RDP sign-in:

```powershell
.\setup-remote-remoting.ps1
```

What it does:

- enables WinRM
- sets WinRM startup type
- enables PowerShell remoting
- enables WinRM firewall rules

What it does not do:

- no BE200 changes
- no IP/DNS/gateway/route changes

### 3. Test remoting

Secure prompt path:

```powershell
.\test-remoting.ps1
```

PSCredential path:

```powershell
$cred = Get-Credential -UserName admin
.\test-remoting.ps1 -Credential $cred
```

Lab plaintext path:

```powershell
.\test-remoting.ps1 -Username admin -Password password
```

Output:

- readable on-screen summary
- CSV summary with target IP, computer name, current user, WinRM service status, and BE200 presence

### 4. Discover BE200 advanced properties

```powershell
.\discover-be200-advanced-properties.ps1 -Credential $cred
```

What it exports:

- CSV discovery snapshot
- JSON discovery snapshot
- transcript log

Discovery export columns:

- `ComputerName`
- `TargetIP`
- `AdapterName`
- `InterfaceDescription`
- `PropertyDisplayName`
- `RegistryKeyword`
- `CurrentDisplayValue`
- `RegistryValue`
- `PossibleDisplayValues`
- `PossibleRegistryValues`

## Stage 1: Template Export and Validation

### 5. Export the editable config template

```powershell
.\export-be200-config-template.ps1 -DiscoveryPath .\output\csv\be200-discovery-<timestamp>.csv
```

Template columns:

- `Scope`
- `TargetIP`
- `AdapterMatch`
- `PropertyDisplayName`
- `RegistryKeyword`
- `CurrentValue`
- `TargetValue`
- `Apply`
- `Notes`

Design notes:

- Generated rows default to `Scope=ALL`
- `TargetIP` is blank for `Scope=ALL`
- `Apply` defaults to `FALSE`
- `RegistryKeyword` is preserved whenever discovery exposed it
- `PropertyDisplayName` remains in the template for readability

### 6. Validate the edited config

```powershell
.\validate-be200-config.ps1 -ConfigPath .\output\csv\be200-config-template-<timestamp>.csv -DiscoveryPath .\output\csv\be200-discovery-<timestamp>.csv
```

Validation checks:

- target scope
- exact target IP allowlist
- exact adapter name allowlist
- property existence on each target
- valid target value when driver metadata exposes valid values
- ambiguity detection

Validation outputs:

- validation report CSV
- validated config CSV for apply consumption

Validation statuses:

- `Valid`
- `Skipped`
- `Invalid`

## Stage 2: Apply BE200 Advanced Settings

### 7. Dry-run first

Always start with `-WhatIf`.

```powershell
.\apply-be200-config.ps1 -ValidatedConfigPath .\output\csv\be200-validated-config-<timestamp>.csv -Mode WriteOnly -Credential $cred -WhatIf
```

Dry-run behavior:

- resolves targets and rows
- rechecks exact BE200 targeting on the remote side
- does not make changes
- exports structured results

### 8. Apply in `WriteOnly` mode

```powershell
.\apply-be200-config.ps1 -ValidatedConfigPath .\output\csv\be200-validated-config-<timestamp>.csv -Mode WriteOnly -Credential $cred
```

Behavior:

- applies only validated rows where `Apply=TRUE`
- uses `-NoRestart`
- re-reads resulting values
- exports results and rollback data

### 9. Apply in `RestartBE200` mode

```powershell
.\apply-be200-config.ps1 -ValidatedConfigPath .\output\csv\be200-validated-config-<timestamp>.csv -Mode RestartBE200 -Credential $cred
```

Behavior:

- applies only validated rows where `Apply=TRUE`
- writes with `-NoRestart`
- restarts only the exact allowlisted BE200 adapter touched on that target
- re-reads resulting values after restart
- exports results and rollback data

Apply outputs:

- results CSV
- results JSON
- rollback CSV
- rollback JSON
- transcript log

Rollback behavior:

- rollback data is preserved only as exported data
- the toolkit does not automatically revert settings

### 10. Export the before/after report

```powershell
.\export-be200-before-after-report.ps1 -ApplyResultsPath .\output\csv\be200-apply-results-<timestamp>.csv
```

Required report columns:

- `ComputerName`
- `TargetIP`
- `AdapterName`
- `PropertyDisplayName`
- `RegistryKeyword`
- `OriginalValue`
- `TargetValue`
- `FinalValue`
- `ApplyAttempted`
- `ApplySucceeded`
- `VerificationSucceeded`
- `ExecutionMode`
- `Notes`

Optional HTML:

```powershell
.\export-be200-before-after-report.ps1 -ApplyResultsPath .\output\csv\be200-apply-results-<timestamp>.csv -HtmlPath .\output\reports\be200-before-after-report.html
```

## Stage 3: Operational BE200 Actions

### Query status

```powershell
.\invoke-be200-action.ps1 -Action Status -Credential $cred
```

### Disable BE200

```powershell
.\invoke-be200-action.ps1 -Action Disable -Credential $cred
```

### Enable BE200

```powershell
.\invoke-be200-action.ps1 -Action Enable -Credential $cred
```

### Restart BE200

```powershell
.\invoke-be200-action.ps1 -Action Restart -Credential $cred
```

## Additional Controller Workflows

### Wi-Fi connect / verify / status

Connect:

```powershell
.\invoke-be200-wifi.ps1 -Action Connect -TargetIP 192.168.22.221 -SSID <ssid> -Username admin -Password password
```

Verify:

```powershell
.\invoke-be200-wifi.ps1 -Action Verify -TargetIP 192.168.22.221 -SSID <ssid> -Username admin -Password password
```

Status:

```powershell
.\invoke-be200-wifi.ps1 -Action Status -TargetIP ALL -Username admin -Password password
```

Behavior:

- targets only the exact allowlisted BE200 adapter descriptions
- does not touch Ethernet adapters or layer-3 configuration
- exports CSV results and transcript logs

### Restart + RDP orchestration

```powershell
.\orchestrate-restart-rdp.ps1 -TargetIP 192.168.22.221 -Username admin -Password password -CsvPath .\output\csv\restart.csv -TranscriptPath .\output\transcripts\restart.log
```

Behavior:

- issues an OS restart through WinRM
- waits for ping recovery
- optionally checks TCP 3389
- optionally launches `mstsc` from the controller in sequence

### Open NCPA orchestration

```powershell
.\orchestrate-open-ncpa.ps1 -TargetIP 192.168.22.221 -Username admin -Password password -CsvPath .\output\csv\open-ncpa.csv -TranscriptPath .\output\transcripts\open-ncpa.log
```

Behavior:

- uses WinRM to register a one-shot scheduled task on the target
- attempts to open `ncpa.cpl` on the target's interactive desktop
- can optionally launch `mstsc` from the controller
- does not change IP, gateway, DNS, routes, metrics, proxy, or Ethernet settings

## Optional Local GUI

The repository also contains a local Flask GUI under `gui\`.

Design intent:

- the GUI does not replace the PowerShell toolkit
- the GUI orchestrates the same validated scripts and writes local job history
- the GUI is optional; CLI remains the primary reference workflow in this README

Operator-visible behavior:

- job status can be `success`, `partial`, or `failed`
- job detail shows a status reason when the subprocess succeeded but one or more target rows did not
- GUI history is stored locally under `gui\data\`
- the Flask session secret should come from `BE200_GUI_SECRET_KEY` when supplied, otherwise the GUI generates or reuses a local secret file under `gui\data\`

For installation, startup, routes, and detailed page behavior, use `gui\README.md`.

Targeting examples:

All targets:

```powershell
.\invoke-be200-action.ps1 -Action Status -Credential $cred -TargetIP ALL
```

One target:

```powershell
.\invoke-be200-action.ps1 -Action Restart -Credential $cred -TargetIP 192.168.22.221
```

Subset:

```powershell
.\invoke-be200-action.ps1 -Action Status -Credential $cred -TargetIP 192.168.22.221,192.168.22.223
```

Dry-run path for state-changing actions:

```powershell
.\invoke-be200-action.ps1 -Action Restart -Credential $cred -TargetIP 192.168.22.221 -WhatIf
```

Action safeguards:

- `Disable`, `Enable`, and `Restart` require confirmation unless `-Force` is supplied
- only the exact allowlisted BE200 adapter names are targeted
- non-BE200 adapters are never touched

Action outputs:

- CSV action results
- transcript log

## Generated Files

The toolkit generates local artifacts under `output\`:

- `output\csv\`
- `output\json\`
- `output\reports\`
- `output\transcripts\`
- `output\logs\`

Typical generated files:

- remoting summary CSV
- discovery CSV and JSON
- config template CSV
- validation report CSV
- validated config CSV
- apply results CSV and JSON
- rollback CSV and JSON
- before/after report CSV
- optional HTML report
- action result CSV
- transcript logs

## What Is Intentionally Not Automated Yet

The toolkit intentionally does not automate:

- deployment to `192.168.22.8`
- copying files to `192.168.22.8`
- auto-running on `192.168.22.8`
- automatic rollback
- changing controller network configuration
- changing remote management NIC layer-3 settings

## Deployment Timing

Deployment to `192.168.22.8` should happen only after manual validation succeeds.

Use `VALIDATION_GUIDE.md` for the staged review and self-validation workflow, then use `DEPLOYMENT_NOTES.md` for the later manual move to `192.168.22.8`.

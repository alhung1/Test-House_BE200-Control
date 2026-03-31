[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Status', 'Disable', 'Enable', 'Restart')]
    [string]$Action,

    [Parameter()]
    [string[]]$TargetIP = @('ALL'),

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [string]$Username = 'admin',

    [Parameter()]
    [string]$Password,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [string]$TranscriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Performs exact-scope operational actions against allowlisted Intel BE200 adapters.

.DESCRIPTION
Supported actions:
- Status
- Disable
- Enable
- Restart

Safety rules:
- exact target allowlist only
- exact BE200 adapter allowlist only
- never touch Ethernet adapters or non-BE200 adapters
- support -WhatIf for dry-run on state-changing actions
- confirmation is required for Disable, Enable, and Restart unless -Force is supplied
#>

$resolvedTargets = Resolve-BE200TargetIPs -TargetIP $TargetIP
$effectiveCredential = Resolve-BE200Credential -Credential $Credential -Username $Username -Password $Password
$allowedInterfaceDescriptions = Get-BE200AllowedInterfaceDescriptions
$transcriptStarted = $false

if ($env:BE200_NONINTERACTIVE -eq '1') {
    $ConfirmPreference = 'None'
}

if (-not $CsvPath) {
    $CsvPath = New-BE200OutputFilePath -Category 'csv' -BaseName ('be200-action-' + $Action.ToLowerInvariant()) -Extension 'csv'
}

if (-not $TranscriptPath) {
    $TranscriptPath = New-BE200OutputFilePath -Category 'transcripts' -BaseName ('invoke-be200-action-' + $Action.ToLowerInvariant()) -Extension 'log'
}

function Get-BE200ActionStatePath {
    param([string]$Target)

    $stateRoot = Join-Path (New-BE200OutputRoot) 'state'
    if (-not (Test-Path -LiteralPath $stateRoot)) {
        [void](New-Item -ItemType Directory -Path $stateRoot -Force)
    }

    $safeTarget = ($Target -replace '[^0-9A-Za-z._-]', '-').Trim('-')
    return (Join-Path $stateRoot ("be200-action-state-{0}.json" -f $safeTarget))
}

function Load-BE200ActionState {
    param([string]$Target)

    $path = Get-BE200ActionStatePath -Target $Target
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }

    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if (-not $content.Trim()) {
        return @()
    }

    $data = $content | ConvertFrom-Json
    if ($data -is [System.Collections.IEnumerable] -and -not ($data -is [string])) {
        return @($data)
    }

    return @($data)
}

function Save-BE200ActionState {
    param(
        [string]$Target,
        [object[]]$StateRows
    )

    $path = Get-BE200ActionStatePath -Target $Target
    $directory = Split-Path -Path $path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    @($StateRows) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Remove-BE200ActionState {
    param([string]$Target)

    $path = Get-BE200ActionStatePath -Target $Target
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$results = New-Object System.Collections.Generic.List[object]

if ($Action -ne 'Status' -and -not $Force) {
    if ($env:BE200_NONINTERACTIVE -eq '1') {
        throw "Non-interactive BE200 action '$Action' requires -Force. The GUI path must not prompt."
    }

    $caption = 'Confirm BE200 operational action'
    $message = "Proceed with action '$Action' against the requested allowlisted BE200 adapters only?"
    if (-not $PSCmdlet.ShouldContinue($message, $caption)) {
        throw 'The operator cancelled the requested BE200 action.'
    }
}

try {
    try {
        Start-Transcript -Path $TranscriptPath -Force | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Warning ("Transcript could not be started. Continuing without transcript capture. {0}" -f $_.Exception.Message)
    }

    Write-BE200Section -Message ('Invoking BE200 action: {0}' -f $Action)
    Write-Host ('Targets: {0}' -f ($resolvedTargets -join ', ')) -ForegroundColor Yellow

    foreach ($target in $resolvedTargets) {
        $performAction = if ($Action -eq 'Status') {
            $true
        }
        else {
            $PSCmdlet.ShouldProcess($target, ("Perform BE200 action '{0}'" -f $Action))
        }

        try {
            $requestedIdentities = if ($Action -eq 'Enable') {
                @(Load-BE200ActionState -Target $target)
            }
            else {
                @()
            }

            $remoteRows = Invoke-Command -ComputerName $target -Credential $effectiveCredential -ErrorAction Stop -ScriptBlock {
                param($RequestedAction, $PerformAction, $AllowedInterfaceDescriptions, $RequestedIdentities)

                function Normalize-BE200Text {
                    param([object]$Value)

                    if ($null -eq $Value) {
                        return ''
                    }

                    return $Value.ToString().Trim()
                }

                function Get-BE200CandidateAdapters {
                    param([string[]]$AllowedInterfaceDescriptions)

                    return @(
                        Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
                            Where-Object {
                                $_ -and
                                $AllowedInterfaceDescriptions -contains $_.InterfaceDescription -and
                                $_.Status -ne 'Not Present'
                            }
                    )
                }

                function Get-BE200AdapterIdentity {
                    param(
                        [object]$Adapter,
                        [string]$ResolutionSource = 'PreferredSelection'
                    )

                    $cim = @(
                        Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue |
                            Where-Object {
                                $_ -and (
                                    ($_.NetConnectionID -and $_.NetConnectionID -eq $Adapter.Name) -or
                                    ($_.InterfaceIndex -and $_.InterfaceIndex -eq $Adapter.ifIndex)
                                )
                            } |
                            Select-Object -First 1
                    )

                    return [pscustomobject]@{
                        Name                 = $Adapter.Name
                        InterfaceDescription = $Adapter.InterfaceDescription
                        Status               = $Adapter.Status
                        ifIndex              = $Adapter.ifIndex
                        MacAddress           = $Adapter.MacAddress
                        InterfaceGuid        = if ($Adapter.InterfaceGuid) { $Adapter.InterfaceGuid.Guid } else { $null }
                        PnPDeviceID          = if ($cim) { $cim.PNPDeviceID } else { $null }
                        NetConnectionID      = if ($cim) { $cim.NetConnectionID } else { $null }
                        CimGuid              = if ($cim) { $cim.GUID } else { $null }
                        ResolutionSource     = $ResolutionSource
                    }
                }

                function Select-PreferredBE200Adapters {
                    param(
                        [string[]]$AllowedInterfaceDescriptions,
                        [string]$RequestedAction
                    )

                    $selected = New-Object System.Collections.Generic.List[object]
                    $issues = New-Object System.Collections.Generic.List[string]
                    $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
                    $preferredStatuses = if ($RequestedAction -eq 'Enable') {
                        @('Disabled', 'Up', 'Disconnected')
                    }
                    elseif ($RequestedAction -eq 'Status') {
                        @('Up', 'Disconnected', 'Disabled')
                    }
                    else {
                        @('Up', 'Disconnected')
                    }

                    foreach ($interfaceDescription in $AllowedInterfaceDescriptions) {
                        $matching = @(
                            $allAdapters |
                                Where-Object {
                                    $_ -and
                                    $_.InterfaceDescription -eq $interfaceDescription -and
                                    $_.Status -ne 'Not Present'
                                }
                        )

                        if ($matching.Count -eq 0) {
                            continue
                        }

                        $resolved = $false
                        foreach ($preferredStatus in $preferredStatuses) {
                            $preferredMatches = @($matching | Where-Object { $_.Status -eq $preferredStatus })
                            if ($preferredMatches.Count -eq 1) {
                                [void]$selected.Add($preferredMatches[0])
                                $resolved = $true
                                break
                            }

                            if ($preferredMatches.Count -gt 1) {
                                [void]$issues.Add(("Multiple adapters matched allowlisted InterfaceDescription '{0}' with Status '{1}'. Skipping to avoid ambiguity." -f $interfaceDescription, $preferredStatus))
                                $resolved = $true
                                break
                            }
                        }

                        if ($resolved) {
                            continue
                        }

                        if ($matching.Count -eq 1) {
                            [void]$selected.Add($matching[0])
                            continue
                        }

                        [void]$issues.Add(("Multiple adapters matched allowlisted InterfaceDescription '{0}' with non-preferred statuses. Skipping to avoid ambiguity." -f $interfaceDescription))
                    }

                    return [pscustomobject]@{
                        SelectedAdapters = @($selected.ToArray())
                        SelectionIssues  = @($issues.ToArray())
                    }
                }

                function Resolve-BE200AdaptersFromIdentity {
                    param(
                        [object[]]$RequestedIdentities,
                        [string[]]$AllowedInterfaceDescriptions
                    )

                    $selected = New-Object System.Collections.Generic.List[object]
                    $issues = New-Object System.Collections.Generic.List[string]
                    $candidateAdapters = @(Get-BE200CandidateAdapters -AllowedInterfaceDescriptions $AllowedInterfaceDescriptions)

                    foreach ($identity in @($RequestedIdentities)) {
                        $resolved = $null
                        $resolutionSource = $null

                        foreach ($attempt in @(
                            @{ Label = 'Name'; Matches = @($candidateAdapters | Where-Object { $_.Name -eq (Normalize-BE200Text $identity.Name) -and $_.InterfaceDescription -eq (Normalize-BE200Text $identity.InterfaceDescription) }) },
                            @{ Label = 'MacAddress'; Matches = @($candidateAdapters | Where-Object { (Normalize-BE200Text $_.MacAddress) -eq (Normalize-BE200Text $identity.MacAddress) -and $_.InterfaceDescription -eq (Normalize-BE200Text $identity.InterfaceDescription) }) },
                            @{ Label = 'ifIndex'; Matches = @($candidateAdapters | Where-Object { $_.ifIndex -eq $identity.ifIndex -and $_.InterfaceDescription -eq (Normalize-BE200Text $identity.InterfaceDescription) }) }
                        )) {
                            if ($attempt.Matches.Count -eq 1) {
                                $resolved = $attempt.Matches[0]
                                $resolutionSource = $attempt.Label
                                break
                            }

                            if ($attempt.Matches.Count -gt 1) {
                                [void]$issues.Add(("Saved adapter identity matched more than one adapter via {0}. Skipping to avoid ambiguity." -f $attempt.Label))
                                $resolved = $null
                                $resolutionSource = $null
                                break
                            }
                        }

                        if (-not $resolved) {
                            if (-not $resolutionSource) {
                                [void]$issues.Add("Saved adapter identity could not be resolved on the remote target.")
                            }
                            continue
                        }

                        if (@($selected | Where-Object { $_.Name -eq $resolved.Name }).Count -eq 0) {
                            [void]$selected.Add($resolved)
                        }
                    }

                    return [pscustomobject]@{
                        SelectedAdapters = @($selected.ToArray())
                        SelectionIssues  = @($issues.ToArray())
                    }
                }

                $computerName = $env:COMPUTERNAME
                $rows = New-Object System.Collections.Generic.List[object]

                $selection = if ($RequestedAction -eq 'Enable' -and @($RequestedIdentities).Count -gt 0) {
                    Resolve-BE200AdaptersFromIdentity -RequestedIdentities @($RequestedIdentities) -AllowedInterfaceDescriptions $AllowedInterfaceDescriptions
                }
                else {
                    Select-PreferredBE200Adapters -AllowedInterfaceDescriptions $AllowedInterfaceDescriptions -RequestedAction $RequestedAction
                }
                foreach ($issue in $selection.SelectionIssues) {
                    [void]$rows.Add([pscustomobject]@{
                        ComputerName         = $computerName
                        AdapterName          = $null
                        InterfaceDescription = $null
                        AdapterMacAddress    = $null
                        AdapterIfIndex       = $null
                        AdapterInterfaceGuid = $null
                        AdapterPnPDeviceID   = $null
                        ResolutionSource     = $null
                        InitialStatus        = $null
                        FinalStatus          = $null
                        Action               = $RequestedAction
                        ActionAttempted      = $PerformAction
                        ActionSucceeded      = $false
                        Notes                = $issue
                    })
                }

                $adapters = @($selection.SelectedAdapters)
                if ($adapters.Count -eq 0) {
                    [void]$rows.Add([pscustomobject]@{
                        ComputerName         = $computerName
                        AdapterName          = $null
                        InterfaceDescription = $null
                        AdapterMacAddress    = $null
                        AdapterIfIndex       = $null
                        AdapterInterfaceGuid = $null
                        AdapterPnPDeviceID   = $null
                        ResolutionSource     = $null
                        InitialStatus        = $null
                        FinalStatus          = $null
                        Action               = $RequestedAction
                        ActionAttempted      = $PerformAction
                        ActionSucceeded      = $false
                        Notes                = 'No allowlisted Intel BE200 adapter was resolved on this target.'
                    })
                    return @($rows.ToArray())
                }

                foreach ($adapter in $adapters) {
                    $initial = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
                    $actionSucceeded = $false
                    $notes = New-Object System.Collections.Generic.List[string]
                    $resolutionSource = if ($RequestedAction -eq 'Enable' -and @($RequestedIdentities).Count -gt 0) {
                        'SavedIdentity'
                    }
                    else {
                        'PreferredSelection'
                    }
                    $identity = Get-BE200AdapterIdentity -Adapter $adapter -ResolutionSource $resolutionSource

                    if ($RequestedAction -eq 'Status') {
                        $actionSucceeded = $true
                    }
                    elseif (-not $PerformAction) {
                        [void]$notes.Add('Dry-run / WhatIf: no state-changing action executed.')
                    }
                    else {
                        try {
                            switch ($RequestedAction) {
                                'Disable' { Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop }
                                'Enable'  { Enable-NetAdapter -Name $adapter.Name -IncludeHidden -Confirm:$false -ErrorAction Stop }
                                'Restart' { Restart-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop }
                            }
                            $actionSucceeded = $true
                        }
                        catch {
                            [void]$notes.Add($_.Exception.Message)
                        }
                    }

                    $final = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
                    [void]$rows.Add([pscustomobject]@{
                        ComputerName         = $computerName
                        AdapterName          = $adapter.Name
                        InterfaceDescription = $adapter.InterfaceDescription
                        AdapterMacAddress    = $identity.MacAddress
                        AdapterIfIndex       = $identity.ifIndex
                        AdapterInterfaceGuid = $identity.InterfaceGuid
                        AdapterPnPDeviceID   = $identity.PnPDeviceID
                        ResolutionSource     = $identity.ResolutionSource
                        InitialStatus        = if ($initial) { $initial.Status } else { $null }
                        FinalStatus          = if ($final) { $final.Status } else { $null }
                        Action               = $RequestedAction
                        ActionAttempted      = $PerformAction
                        ActionSucceeded      = $actionSucceeded
                        Notes                = ($notes -join ' ')
                    })
                }

                return @($rows.ToArray())
            } -ArgumentList $Action, $performAction, $allowedInterfaceDescriptions, $requestedIdentities

            foreach ($remoteRow in @($remoteRows)) {
                [void]$results.Add([pscustomobject]@{
                    TargetIP              = $target
                    ComputerName          = $remoteRow.ComputerName
                    AdapterName           = $remoteRow.AdapterName
                    InterfaceDescription  = $remoteRow.InterfaceDescription
                    AdapterMacAddress     = $remoteRow.AdapterMacAddress
                    AdapterIfIndex        = $remoteRow.AdapterIfIndex
                    AdapterInterfaceGuid  = $remoteRow.AdapterInterfaceGuid
                    AdapterPnPDeviceID    = $remoteRow.AdapterPnPDeviceID
                    ResolutionSource      = $remoteRow.ResolutionSource
                    Action                = $remoteRow.Action
                    InitialStatus         = $remoteRow.InitialStatus
                    FinalStatus           = $remoteRow.FinalStatus
                    ActionAttempted       = $remoteRow.ActionAttempted
                    ActionSucceeded       = $remoteRow.ActionSucceeded
                    Notes                 = $remoteRow.Notes
                })
            }

            if ($Action -eq 'Disable') {
                $stateRows = @(
                    foreach ($remoteRow in @($remoteRows)) {
                        if ($remoteRow.ActionSucceeded) {
                            [pscustomobject]@{
                                Name                 = $remoteRow.AdapterName
                                InterfaceDescription = $remoteRow.InterfaceDescription
                                MacAddress           = $remoteRow.AdapterMacAddress
                                ifIndex              = $remoteRow.AdapterIfIndex
                                InterfaceGuid        = $remoteRow.AdapterInterfaceGuid
                                PnPDeviceID          = $remoteRow.AdapterPnPDeviceID
                                SavedAt              = (Get-Date).ToString('o')
                            }
                        }
                    }
                )

                if ($stateRows.Count -gt 0) {
                    Save-BE200ActionState -Target $target -StateRows $stateRows
                }
                else {
                    Remove-BE200ActionState -Target $target
                }
            }
            elseif ($Action -eq 'Enable') {
                $successfulNames = @(
                    $remoteRows |
                        Where-Object { $_.ActionSucceeded } |
                        ForEach-Object { $_.AdapterName } |
                        Where-Object { $_ }
                )
                $remainingState = @(
                    foreach ($savedIdentity in @($requestedIdentities)) {
                        if ($successfulNames -notcontains $savedIdentity.Name) {
                            $savedIdentity
                        }
                    }
                )

                if ($remainingState.Count -eq 0) {
                    Remove-BE200ActionState -Target $target
                }
                else {
                    Save-BE200ActionState -Target $target -StateRows $remainingState
                }
            }
        }
        catch {
            [void]$results.Add([pscustomobject]@{
                TargetIP              = $target
                ComputerName          = $null
                AdapterName           = $null
                InterfaceDescription  = $null
                AdapterMacAddress     = $null
                AdapterIfIndex        = $null
                AdapterInterfaceGuid  = $null
                AdapterPnPDeviceID    = $null
                ResolutionSource      = $null
                Action                = $Action
                InitialStatus         = $null
                FinalStatus           = $null
                ActionAttempted       = $performAction
                ActionSucceeded       = $false
                Notes                 = ('Remote action failed: {0}' -f $_.Exception.Message)
            })
        }
    }

    Export-BE200Csv -InputObject @($results.ToArray()) -Path $CsvPath

    Write-Host
    Write-Host 'Action summary:' -ForegroundColor Green
    @($results.ToArray()) | Sort-Object TargetIP, AdapterName | Format-Table -AutoSize

    Write-Host
    Write-Host ("Action result CSV: {0}" -f $CsvPath) -ForegroundColor Green
    Write-Host ("Transcript log:    {0}" -f $TranscriptPath) -ForegroundColor Green
}
finally {
    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}

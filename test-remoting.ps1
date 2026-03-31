[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$TargetIP = @('ALL'),

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [string]$Username = 'admin',

    [Parameter()]
    [string]$Password,

    [Parameter()]
    [string]$CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Tests PowerShell remoting connectivity to the BE200 lab targets.

.DESCRIPTION
This script connects from the controller machine to one, many, or all allowed target
IPs and collects a compact result set for manual review.

Credential handling:
- Preferred non-interactive path: pass -Credential with a PSCredential object.
- Default interactive path: omit -Credential and -Password to get a secure credential prompt.
- Lab convenience path: pass -Username and -Password to build a PSCredential in memory.
  This is less secure than a prompt or PSCredential object. The plaintext password is
  never written to transcripts, CSV, JSON, or screen output by this toolkit.

The script does NOT modify:
- IP addresses
- subnet masks
- default gateways
- DNS settings
- routes
- interface metrics
- proxy settings
- Ethernet adapters
- non-BE200 adapters
#>

$resolvedTargets = Resolve-BE200TargetIPs -TargetIP $TargetIP
$effectiveCredential = Resolve-BE200Credential -Credential $Credential -Username $Username -Password $Password

if (-not $CsvPath) {
    $CsvPath = New-BE200OutputFilePath -Category 'csv' -BaseName 'test-remoting-summary' -Extension 'csv'
}

Write-BE200Section -Message 'Testing remote PowerShell access'
Write-Host ('Targets: {0}' -f ($resolvedTargets -join ', ')) -ForegroundColor Yellow

$scriptBlock = {
    function Select-PreferredBE200Adapters {
        param([string[]]$AllowedInterfaceDescriptions)

        $selected = New-Object System.Collections.Generic.List[object]
        $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)

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
            foreach ($preferredStatus in @('Up', 'Disconnected')) {
                $preferredMatches = @($matching | Where-Object { $_.Status -eq $preferredStatus })
                if ($preferredMatches.Count -eq 1) {
                    [void]$selected.Add($preferredMatches[0])
                    $resolved = $true
                    break
                }

                if ($preferredMatches.Count -gt 1) {
                    $resolved = $true
                    break
                }
            }

            if ($resolved) {
                continue
            }

            if ($matching.Count -eq 1) {
                [void]$selected.Add($matching[0])
            }
        }

        return @($selected.ToArray())
    }

    $allowedInterfaceDescriptions = @(
        'Intel(R) Wi-Fi 7 BE200 320MHz'
        'Intel(R) Wi-Fi 7 BE200 320MHz #6'
    )

    $matchingAdapters = @(Select-PreferredBE200Adapters -AllowedInterfaceDescriptions $allowedInterfaceDescriptions)

    [pscustomobject]@{
        ComputerName      = $env:COMPUTERNAME
        CurrentUser       = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
        WinRMServiceStatus = (Get-Service -Name WinRM).Status
        BE200AdapterFound = ($matchingAdapters.Count -gt 0)
    }
}

$rawResults = Invoke-BE200RemoteCommand -TargetIP $resolvedTargets -Credential $effectiveCredential -ScriptBlock $scriptBlock

$summary = foreach ($result in $rawResults) {
    if ($result.Success) {
        [pscustomobject]@{
            TargetIP           = $result.TargetIP
            Reachable          = $true
            ComputerName       = $result.Data.ComputerName
            CurrentUser        = $result.Data.CurrentUser
            WinRMServiceStatus = $result.Data.WinRMServiceStatus
            BE200AdapterFound  = $result.Data.BE200AdapterFound
            ErrorMessage       = $null
        }
        continue
    }

    [pscustomobject]@{
        TargetIP           = $result.TargetIP
        Reachable          = $false
        ComputerName       = $null
        CurrentUser        = $null
        WinRMServiceStatus = $null
        BE200AdapterFound  = $false
        ErrorMessage       = $result.ErrorMessage
    }
}

Export-BE200Csv -InputObject $summary -Path $CsvPath

Write-Host
Write-Host 'Readable summary:' -ForegroundColor Green
$summary | Sort-Object TargetIP | Format-Table -AutoSize

Write-Host
Write-Host ("CSV summary exported to: {0}" -f $CsvPath) -ForegroundColor Green

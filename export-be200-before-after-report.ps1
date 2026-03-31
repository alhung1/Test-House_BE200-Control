[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApplyResultsPath,

    [Parameter()]
    [string]$DiscoveryPath,

    [Parameter()]
    [string]$ReportCsvPath,

    [Parameter()]
    [string]$HtmlPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Exports a consolidated BE200 before/after report after apply operations.

.DESCRIPTION
This script reads the structured apply results and emits a required CSV report with:
- ComputerName
- TargetIP
- AdapterName
- PropertyDisplayName
- RegistryKeyword
- OriginalValue
- TargetValue
- FinalValue
- ApplyAttempted
- ApplySucceeded
- VerificationSucceeded
- ExecutionMode
- Notes

If a discovery snapshot is supplied, the script can use it to backfill OriginalValue
when an apply result row does not contain one.
#>

$applyRows = @(Import-BE200DataFile -Path $ApplyResultsPath)
$discoveryRows = if ($DiscoveryPath) { @(Import-BE200DataFile -Path $DiscoveryPath) } else { @() }

if ($applyRows.Count -eq 0) {
    throw 'The apply results file did not contain any rows to report.'
}

if (-not $ReportCsvPath) {
    $ReportCsvPath = New-BE200OutputFilePath -Category 'reports' -BaseName 'be200-before-after-report' -Extension 'csv'
}

$reportRows = foreach ($row in $applyRows) {
    $originalValue = $row.OriginalValue
    if ([string]::IsNullOrWhiteSpace($originalValue) -and $discoveryRows.Count -gt 0) {
        $discoveryMatch = @(
            $discoveryRows |
                Where-Object {
                    $_.TargetIP -eq $row.TargetIP -and
                    $_.AdapterName -eq $row.AdapterName -and
                    $_.RegistryKeyword -eq $row.RegistryKeyword -and
                    (
                        $_.PropertyDisplayName -eq $row.PropertyDisplayName -or
                        [string]::IsNullOrWhiteSpace($row.PropertyDisplayName)
                    )
                }
        ) | Select-Object -First 1

        if ($discoveryMatch) {
            $originalValue = $discoveryMatch.CurrentDisplayValue
        }
    }

    [pscustomobject]@{
        ComputerName          = $row.ComputerName
        TargetIP              = $row.TargetIP
        AdapterName           = $row.AdapterName
        PropertyDisplayName   = $row.PropertyDisplayName
        RegistryKeyword       = $row.RegistryKeyword
        OriginalValue         = $originalValue
        TargetValue           = $row.TargetValue
        FinalValue            = $row.FinalValue
        ApplyAttempted        = $row.ApplyAttempted
        ApplySucceeded        = $row.ApplySucceeded
        VerificationSucceeded = $row.VerificationSucceeded
        ExecutionMode         = $row.ExecutionMode
        Notes                 = $row.Notes
    }
}

Export-BE200Csv -InputObject $reportRows -Path $ReportCsvPath

if ($HtmlPath) {
    $reportRows |
        Sort-Object TargetIP, AdapterName, RegistryKeyword, PropertyDisplayName |
        ConvertTo-Html -Title 'BE200 Before/After Report' |
        Set-Content -Path $HtmlPath -Encoding UTF8
}

Write-BE200Section -Message 'BE200 before/after report exported'
Write-Host ('CSV report path: {0}' -f $ReportCsvPath) -ForegroundColor Green
if ($HtmlPath) {
    Write-Host ('HTML report path: {0}' -f $HtmlPath) -ForegroundColor Green
}

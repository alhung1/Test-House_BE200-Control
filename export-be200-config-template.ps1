[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DiscoveryPath,

    [Parameter()]
    [string]$TemplatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Builds an editable BE200 configuration template from discovery output.

.DESCRIPTION
The generated CSV is pre-populated from discovery data so you can review and edit it
before validation and apply. It preserves both RegistryKeyword and DisplayName fields:
- RegistryKeyword is preferred internally for precision.
- PropertyDisplayName is kept for readability.

The template uses:
- Scope = ALL for broad rows by default
- TargetIP = blank when Scope is ALL
- Apply = FALSE by default

This design is robust across slight machine differences because validation later checks
each row against the actual discovery data for each target and skips unsupported rows
instead of guessing.
#>

$discoveryRows = @(Import-BE200DataFile -Path $DiscoveryPath)
if ($discoveryRows.Count -eq 0) {
    throw 'The discovery file did not contain any rows to build a template from.'
}

if (-not $TemplatePath) {
    $TemplatePath = New-BE200OutputFilePath -Category 'csv' -BaseName 'be200-config-template' -Extension 'csv'
}

$groupedRows = $discoveryRows |
    Where-Object {
        $_.InterfaceDescription -and
        (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription $_.InterfaceDescription) -and
        ($_.RegistryKeyword -or $_.PropertyDisplayName)
    } |
    Group-Object InterfaceDescription, RegistryKeyword, PropertyDisplayName

$templateRows = foreach ($group in $groupedRows) {
    $first = $group.Group | Select-Object -First 1
    $currentValues = @(
        $group.Group |
            ForEach-Object { $_.CurrentDisplayValue } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $targetCoverage = @(
        $group.Group |
            ForEach-Object { $_.TargetIP } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    $currentValue = if ($currentValues.Count -eq 0) {
        ''
    }
    elseif ($currentValues.Count -eq 1) {
        $currentValues[0]
    }
    else {
        'Mixed: ' + ($currentValues -join ' | ')
    }

    $notesParts = New-Object System.Collections.Generic.List[string]
    [void]$notesParts.Add(('Generated from discovery across {0} target(s).' -f $targetCoverage.Count))
    if ($targetCoverage.Count -gt 0) {
        [void]$notesParts.Add(('Targets: {0}' -f ($targetCoverage -join ', ')))
    }
    if (-not [string]::IsNullOrWhiteSpace($first.PossibleDisplayValues)) {
        [void]$notesParts.Add(('PossibleDisplayValues: {0}' -f $first.PossibleDisplayValues))
    }
    if (-not [string]::IsNullOrWhiteSpace($first.PossibleRegistryValues)) {
        [void]$notesParts.Add(('PossibleRegistryValues: {0}' -f $first.PossibleRegistryValues))
    }

    [pscustomobject]@{
        Scope               = 'ALL'
        TargetIP            = ''
        AdapterMatch        = $first.InterfaceDescription
        PropertyDisplayName = $first.PropertyDisplayName
        RegistryKeyword     = $first.RegistryKeyword
        CurrentValue        = $currentValue
        TargetValue         = ''
        Apply               = 'FALSE'
        Notes               = ($notesParts -join ' ')
    }
}

$templateRows = @($templateRows | Sort-Object AdapterMatch, RegistryKeyword, PropertyDisplayName)
Export-BE200Csv -InputObject $templateRows -Path $TemplatePath

Write-BE200Section -Message 'BE200 config template exported'
Write-Host ('Rows exported: {0}' -f $templateRows.Count) -ForegroundColor Green
Write-Host ('Template path: {0}' -f $TemplatePath) -ForegroundColor Green

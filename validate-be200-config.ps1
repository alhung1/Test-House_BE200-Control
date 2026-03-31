[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$DiscoveryPath,

    [Parameter()]
    [string]$ValidationReportPath,

    [Parameter()]
    [string]$ValidatedConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Validates a user-edited BE200 configuration template against discovery output.

.DESCRIPTION
This script does not apply any changes. It expands each input row into per-target
validation results and classifies them as:
- Valid
- Skipped
- Invalid

Validation enforces:
- exact target allowlist only
- exact BE200 adapter allowlist only
- skip on ambiguity, never guess

When the driver exposes valid display or registry values, the validator checks the
TargetValue against those sets. If the driver does not expose valid values, the
validator preserves the row as valid only when the operator input can be treated as a
direct display value or a direct numeric registry value without a display-to-registry
mapping guess.
#>

function Split-ValidationValueList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split '\s*;\s*' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

$configRows = @(Import-Csv -Path $ConfigPath)
$discoveryRows = @(Import-BE200DataFile -Path $DiscoveryPath)

if ($configRows.Count -eq 0) {
    throw 'The config template did not contain any rows to validate.'
}

if ($discoveryRows.Count -eq 0) {
    throw 'The discovery file did not contain any rows for validation.'
}

if (-not $ValidationReportPath) {
    $ValidationReportPath = New-BE200OutputFilePath -Category 'csv' -BaseName 'be200-validation-report' -Extension 'csv'
}

if (-not $ValidatedConfigPath) {
    $ValidatedConfigPath = New-BE200OutputFilePath -Category 'csv' -BaseName 'be200-validated-config' -Extension 'csv'
}

$reportRows = New-Object System.Collections.Generic.List[object]
$validatedRows = New-Object System.Collections.Generic.List[object]

for ($index = 0; $index -lt $configRows.Count; $index++) {
    $rowNumber = $index + 1
    $row = $configRows[$index]
    $applyRequested = ConvertTo-BE200Boolean -Value $row.Apply

    try {
        $effectiveTargets = Resolve-BE200ScopeTargets -Scope $row.Scope -TargetIP $row.TargetIP
    }
    catch {
        [void]$reportRows.Add([pscustomobject]@{
            InputRowNumber         = $rowNumber
            ValidationStatus       = 'Invalid'
            Reason                 = $_.Exception.Message
            Scope                  = $row.Scope
            InputTargetIP          = $row.TargetIP
            EffectiveTargetIP      = $null
            AdapterMatch           = $row.AdapterMatch
            PropertyDisplayName    = $row.PropertyDisplayName
            RegistryKeyword        = $row.RegistryKeyword
            CurrentValue           = $row.CurrentValue
            TargetValue            = $row.TargetValue
            Apply                  = $row.Apply
            TargetValueType        = $null
            PossibleDisplayValues  = $null
            PossibleRegistryValues = $null
            ComputerName           = $null
            Notes                  = $null
        })
        continue
    }

    if (-not (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription $row.AdapterMatch)) {
        foreach ($target in $effectiveTargets) {
            [void]$reportRows.Add([pscustomobject]@{
                InputRowNumber         = $rowNumber
                ValidationStatus       = 'Invalid'
                Reason                 = 'AdapterMatch must be one of the exact allowlisted Intel BE200 InterfaceDescription values.'
                Scope                  = $row.Scope
                InputTargetIP          = $row.TargetIP
                EffectiveTargetIP      = $target
                AdapterMatch           = $row.AdapterMatch
                PropertyDisplayName    = $row.PropertyDisplayName
                RegistryKeyword        = $row.RegistryKeyword
                CurrentValue           = $row.CurrentValue
                TargetValue            = $row.TargetValue
                Apply                  = $row.Apply
                TargetValueType        = $null
                PossibleDisplayValues  = $null
                PossibleRegistryValues = $null
                ComputerName           = $null
                Notes                  = $null
            })
        }
        continue
    }

    try {
        $selector = Resolve-BE200PropertySelector -RegistryKeyword $row.RegistryKeyword -PropertyDisplayName $row.PropertyDisplayName
    }
    catch {
        foreach ($target in $effectiveTargets) {
            [void]$reportRows.Add([pscustomobject]@{
                InputRowNumber         = $rowNumber
                ValidationStatus       = 'Invalid'
                Reason                 = $_.Exception.Message
                Scope                  = $row.Scope
                InputTargetIP          = $row.TargetIP
                EffectiveTargetIP      = $target
                AdapterMatch           = $row.AdapterMatch
                PropertyDisplayName    = $row.PropertyDisplayName
                RegistryKeyword        = $row.RegistryKeyword
                CurrentValue           = $row.CurrentValue
                TargetValue            = $row.TargetValue
                Apply                  = $row.Apply
                TargetValueType        = $null
                PossibleDisplayValues  = $null
                PossibleRegistryValues = $null
                ComputerName           = $null
                Notes                  = $null
            })
        }
        continue
    }

    foreach ($target in $effectiveTargets) {
        $matchingRows = @(
            $discoveryRows |
                Where-Object {
                    $_.TargetIP -eq $target -and
                    $_.InterfaceDescription -eq $row.AdapterMatch
                }
        )

        if ($selector.IdentifierType -eq 'RegistryKeyword') {
            $matchingRows = @($matchingRows | Where-Object { $_.RegistryKeyword -eq $selector.IdentifierValue })
            if (-not [string]::IsNullOrWhiteSpace($row.PropertyDisplayName)) {
                $matchingRows = @($matchingRows | Where-Object { $_.PropertyDisplayName -eq $row.PropertyDisplayName })
            }
        }
        else {
            $matchingRows = @($matchingRows | Where-Object { $_.PropertyDisplayName -eq $selector.IdentifierValue })
        }

        if ($matchingRows.Count -eq 0) {
            [void]$reportRows.Add([pscustomobject]@{
                InputRowNumber         = $rowNumber
                ValidationStatus       = 'Skipped'
                Reason                 = 'The target/adapter/property combination was not found in discovery output.'
                Scope                  = $row.Scope
                InputTargetIP          = $row.TargetIP
                EffectiveTargetIP      = $target
                AdapterMatch           = $row.AdapterMatch
                PropertyDisplayName    = $row.PropertyDisplayName
                RegistryKeyword        = $row.RegistryKeyword
                CurrentValue           = $row.CurrentValue
                TargetValue            = $row.TargetValue
                Apply                  = $row.Apply
                TargetValueType        = $null
                PossibleDisplayValues  = $null
                PossibleRegistryValues = $null
                ComputerName           = $null
                Notes                  = $null
            })
            continue
        }

        if ($matchingRows.Count -gt 1) {
            [void]$reportRows.Add([pscustomobject]@{
                InputRowNumber         = $rowNumber
                ValidationStatus       = 'Skipped'
                Reason                 = 'The row matched more than one discovered property on the same target; skipping to avoid ambiguity.'
                Scope                  = $row.Scope
                InputTargetIP          = $row.TargetIP
                EffectiveTargetIP      = $target
                AdapterMatch           = $row.AdapterMatch
                PropertyDisplayName    = $row.PropertyDisplayName
                RegistryKeyword        = $row.RegistryKeyword
                CurrentValue           = $row.CurrentValue
                TargetValue            = $row.TargetValue
                Apply                  = $row.Apply
                TargetValueType        = $null
                PossibleDisplayValues  = (($matchingRows | Select-Object -ExpandProperty PossibleDisplayValues | Sort-Object -Unique) -join ' | ')
                PossibleRegistryValues = (($matchingRows | Select-Object -ExpandProperty PossibleRegistryValues | Sort-Object -Unique) -join ' | ')
                ComputerName           = (($matchingRows | Select-Object -ExpandProperty ComputerName | Sort-Object -Unique) -join ' | ')
                Notes                  = 'Add RegistryKeyword or exact PropertyDisplayName to narrow the row.'
            })
            continue
        }

        $match = $matchingRows[0]
        $validationStatus = 'Valid'
        $reason = 'Row is valid and safe to consume.'
        $targetValueType = $null
        $notes = New-Object System.Collections.Generic.List[string]
        $possibleDisplayValues = Split-ValidationValueList -Value $match.PossibleDisplayValues
        $possibleRegistryValues = Split-ValidationValueList -Value $match.PossibleRegistryValues
        $targetValue = if ($null -eq $row.TargetValue) { '' } else { $row.TargetValue.ToString().Trim() }

        if (-not $applyRequested) {
            $validationStatus = 'Skipped'
            $reason = 'Apply is FALSE, so the row will not be consumed by apply-be200-config.ps1.'
        }
        elseif (-not $targetValue) {
            $validationStatus = 'Invalid'
            $reason = 'TargetValue is required when Apply is TRUE.'
        }
        elseif (($possibleDisplayValues -contains $targetValue) -and ($possibleRegistryValues -contains $targetValue)) {
            $validationStatus = 'Skipped'
            $reason = 'TargetValue matched both display and registry valid-value sets; skipping to avoid ambiguity.'
        }
        elseif ($possibleDisplayValues -contains $targetValue) {
            $targetValueType = 'DisplayValue'
        }
        elseif ($possibleRegistryValues -contains $targetValue) {
            $targetValueType = 'RegistryValue'
        }
        elseif ($possibleDisplayValues.Count -gt 0 -or $possibleRegistryValues.Count -gt 0) {
            $validationStatus = 'Invalid'
            $reason = 'TargetValue did not match the valid values discovered for this property.'
        }
        elseif ($targetValue -match '^\s*-?\d+(\s*,\s*-?\d+)*\s*$') {
            $targetValueType = 'RegistryValue'
            [void]$notes.Add('Driver did not expose valid values; treating numeric TargetValue as an explicit registry value.')
        }
        else {
            $targetValueType = 'DisplayValue'
            [void]$notes.Add('Driver did not expose valid values; treating textual TargetValue as a direct display value.')
        }

        $reportRow = [pscustomobject]@{
            InputRowNumber         = $rowNumber
            ValidationStatus       = $validationStatus
            Reason                 = $reason
            Scope                  = $row.Scope
            InputTargetIP          = $row.TargetIP
            EffectiveTargetIP      = $target
            AdapterMatch           = $row.AdapterMatch
            PropertyDisplayName    = if ($match.PropertyDisplayName) { $match.PropertyDisplayName } else { $row.PropertyDisplayName }
            RegistryKeyword        = if ($match.RegistryKeyword) { $match.RegistryKeyword } else { $row.RegistryKeyword }
            CurrentValue           = $match.CurrentDisplayValue
            TargetValue            = $targetValue
            Apply                  = if ($applyRequested) { 'TRUE' } else { 'FALSE' }
            TargetValueType        = $targetValueType
            PossibleDisplayValues  = $match.PossibleDisplayValues
            PossibleRegistryValues = $match.PossibleRegistryValues
            ComputerName           = $match.ComputerName
            Notes                  = ($notes -join ' ')
        }
        [void]$reportRows.Add($reportRow)

        if ($validationStatus -eq 'Valid') {
            [void]$validatedRows.Add([pscustomobject]@{
                InputRowNumber         = $rowNumber
                Scope                  = $row.Scope
                InputTargetIP          = $row.TargetIP
                EffectiveTargetIP      = $target
                ComputerName           = $match.ComputerName
                AdapterMatch           = $row.AdapterMatch
                PropertyDisplayName    = if ($match.PropertyDisplayName) { $match.PropertyDisplayName } else { $row.PropertyDisplayName }
                RegistryKeyword        = if ($match.RegistryKeyword) { $match.RegistryKeyword } else { $row.RegistryKeyword }
                CurrentValue           = $match.CurrentDisplayValue
                CurrentRegistryValue   = $match.RegistryValue
                TargetValue            = $targetValue
                Apply                  = 'TRUE'
                TargetValueType        = $targetValueType
                PossibleDisplayValues  = $match.PossibleDisplayValues
                PossibleRegistryValues = $match.PossibleRegistryValues
                Notes                  = ($notes -join ' ')
            })
        }
    }
}

Export-BE200Csv -InputObject @($reportRows.ToArray()) -Path $ValidationReportPath
Export-BE200Csv -InputObject @($validatedRows.ToArray()) -Path $ValidatedConfigPath

Write-BE200Section -Message 'BE200 config validation completed'
Write-Host ('Valid rows:   {0}' -f (@($reportRows.ToArray() | Where-Object { $_.ValidationStatus -eq 'Valid' }).Count)) -ForegroundColor Green
Write-Host ('Skipped rows: {0}' -f (@($reportRows.ToArray() | Where-Object { $_.ValidationStatus -eq 'Skipped' }).Count)) -ForegroundColor Yellow
Write-Host ('Invalid rows: {0}' -f (@($reportRows.ToArray() | Where-Object { $_.ValidationStatus -eq 'Invalid' }).Count)) -ForegroundColor Red
Write-Host ('Validation report: {0}' -f $ValidationReportPath) -ForegroundColor Green
Write-Host ('Validated config:  {0}' -f $ValidatedConfigPath) -ForegroundColor Green

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
    [string]$CsvPath,

    [Parameter()]
    [string]$JsonPath,

    [Parameter()]
    [string]$TranscriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Discovers Intel BE200 advanced properties across the allowed lab targets.

.DESCRIPTION
This script remotely queries the exact allowlisted Intel BE200 adapter names only:
- Intel(R) Wi-Fi 7 BE200 320MHz
- Intel(R) Wi-Fi 7 BE200 320MHz #6

For each discovered property, the script exports:
- ComputerName
- TargetIP
- AdapterName
- InterfaceDescription
- PropertyDisplayName
- RegistryKeyword
- CurrentDisplayValue
- RegistryValue
- PossibleDisplayValues
- PossibleRegistryValues

Advanced properties may differ by machine because:
- driver builds can differ between targets
- Windows 11 24H2 and 25H2 may expose different labels
- some properties expose display names and valid values while others do not

The script never changes adapter settings. It only reads BE200 advanced-property data
from the exact allowlisted targets and adapters, then exports local CSV and JSON files.
#>

$resolvedTargets = Resolve-BE200TargetIPs -TargetIP $TargetIP
$effectiveCredential = Resolve-BE200Credential -Credential $Credential -Username $Username -Password $Password

if (-not $CsvPath) {
    $CsvPath = New-BE200OutputFilePath -Category 'csv' -BaseName 'be200-discovery' -Extension 'csv'
}

if (-not $JsonPath) {
    $JsonPath = New-BE200OutputFilePath -Category 'json' -BaseName 'be200-discovery' -Extension 'json'
}

if (-not $TranscriptPath) {
    $TranscriptPath = New-BE200OutputFilePath -Category 'transcripts' -BaseName 'discover-be200-advanced-properties' -Extension 'log'
}

$discoveryRows = New-Object System.Collections.Generic.List[object]
$summaryRows = New-Object System.Collections.Generic.List[object]

try {
    Start-Transcript -Path $TranscriptPath -Force | Out-Null

    Write-BE200Section -Message 'Discovering BE200 advanced properties'
    Write-Host ('Targets: {0}' -f ($resolvedTargets -join ', ')) -ForegroundColor Yellow

    $scriptBlock = {
        param($AllowedInterfaceDescriptions)

        function Join-ValueList {
            param([object]$Value)

            if ($null -eq $Value) {
                return ''
            }

            if ($Value -is [string]) {
                return $Value.Trim()
            }

            $items = @(
                foreach ($item in $Value) {
                    if ($null -ne $item) {
                        $text = $item.ToString().Trim()
                        if ($text) {
                            $text
                        }
                    }
                }
            )

            return ($items -join '; ')
        }

        function Select-PreferredBE200Adapters {
            param([string[]]$AllowedInterfaceDescriptions)

            function Resolve-BE200AdapterFromWlanInterface {
                param(
                    [object[]]$Candidates,
                    [string]$InterfaceDescription
                )

                try {
                    $raw = & netsh wlan show interfaces 2>&1
                }
                catch {
                    return [pscustomobject]@{ Adapter = $null; Note = $null }
                }

                $text = ($raw | Out-String)
                if (-not $text -or $text.Trim().Length -eq 0) {
                    return [pscustomobject]@{ Adapter = $null; Note = $null }
                }

                $blocks = $text -split '(?=\s+Name\s+:)'
                foreach ($block in $blocks) {
                    $info = @{}
                    foreach ($line in ($block -split "`n")) {
                        if ($line -match '^\s+(.+?)\s+:\s+(.+)$') {
                            $info[$Matches[1].Trim()] = $Matches[2].Trim()
                        }
                    }

                    if (-not $info.ContainsKey('Name')) {
                        continue
                    }

                    if ($info.ContainsKey('Description') -and $info['Description'] -ne $InterfaceDescription) {
                        continue
                    }

                    $namedMatches = @($Candidates | Where-Object { $_.Name -eq $info['Name'] -and $_.InterfaceDescription -eq $InterfaceDescription })
                    if ($namedMatches.Count -eq 1) {
                        return [pscustomobject]@{
                            Adapter = $namedMatches[0]
                            Note    = ("Multiple adapters matched allowlisted InterfaceDescription '{0}'. Resolved via WLAN interface '{1}' for read-only discovery." -f $InterfaceDescription, $info['Name'])
                        }
                    }
                }

                return [pscustomobject]@{ Adapter = $null; Note = $null }
            }

            $selected = New-Object System.Collections.Generic.List[object]
            $issues = New-Object System.Collections.Generic.List[string]
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
                        $wlanSelection = Resolve-BE200AdapterFromWlanInterface -Candidates $preferredMatches -InterfaceDescription $interfaceDescription
                        if ($null -ne $wlanSelection.Adapter) {
                            [void]$selected.Add($wlanSelection.Adapter)
                            [void]$issues.Add($wlanSelection.Note)
                        }
                        else {
                            $sorted = @($preferredMatches | Sort-Object ifIndex)
                            [void]$selected.Add($sorted[0])
                            [void]$issues.Add(("Multiple adapters matched allowlisted InterfaceDescription '{0}' with Status '{1}'. Selected lowest ifIndex ({2}) for read-only discovery." -f $interfaceDescription, $preferredStatus, $sorted[0].ifIndex))
                        }
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

                $wlanSelection = Resolve-BE200AdapterFromWlanInterface -Candidates $matching -InterfaceDescription $interfaceDescription
                if ($null -ne $wlanSelection.Adapter) {
                    [void]$selected.Add($wlanSelection.Adapter)
                    [void]$issues.Add($wlanSelection.Note)
                    continue
                }

                $sorted = @($matching | Sort-Object ifIndex)
                [void]$selected.Add($sorted[0])
                [void]$issues.Add(("Multiple adapters matched allowlisted InterfaceDescription '{0}' with non-preferred statuses. Selected lowest ifIndex ({1}) for read-only discovery." -f $interfaceDescription, $sorted[0].ifIndex))
            }

            return [pscustomobject]@{
                SelectedAdapters = @($selected.ToArray())
                SelectionIssues  = @($issues.ToArray())
            }
        }

        $computerName = $env:COMPUTERNAME
        $output = New-Object System.Collections.Generic.List[object]

        $selection = Select-PreferredBE200Adapters -AllowedInterfaceDescriptions $AllowedInterfaceDescriptions
        foreach ($issue in $selection.SelectionIssues) {
            [void]$output.Add([pscustomobject]@{
                RecordType             = 'Info'
                ComputerName           = $computerName
                AdapterName            = $null
                InterfaceDescription   = $null
                PropertyDisplayName    = $null
                RegistryKeyword        = $null
                CurrentDisplayValue    = $null
                RegistryValue          = $null
                PossibleDisplayValues  = $null
                PossibleRegistryValues = $null
                Notes                  = $issue
            })
        }

        $matchingAdapters = @($selection.SelectedAdapters)
        if ($matchingAdapters.Count -eq 0) {
            [void]$output.Add([pscustomobject]@{
                RecordType             = 'Info'
                ComputerName           = $computerName
                AdapterName            = $null
                InterfaceDescription   = $null
                PropertyDisplayName    = $null
                RegistryKeyword        = $null
                CurrentDisplayValue    = $null
                RegistryValue          = $null
                PossibleDisplayValues  = $null
                PossibleRegistryValues = $null
                Notes                  = 'No allowlisted Intel BE200 adapter was resolved on this target.'
            })

            return @($output.ToArray())
        }

        foreach ($adapter in $matchingAdapters) {
            $properties = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -AllProperties -ErrorAction SilentlyContinue)
            if ($properties.Count -eq 0) {
                [void]$output.Add([pscustomobject]@{
                    RecordType             = 'Info'
                    ComputerName           = $computerName
                    AdapterName            = $adapter.Name
                    InterfaceDescription   = $adapter.InterfaceDescription
                    PropertyDisplayName    = $null
                    RegistryKeyword        = $null
                    CurrentDisplayValue    = $null
                    RegistryValue          = $null
                    PossibleDisplayValues  = $null
                    PossibleRegistryValues = $null
                    Notes                  = 'The adapter was found, but no advanced properties were returned by the driver.'
                })
                continue
            }

            foreach ($property in $properties) {
                [void]$output.Add([pscustomobject]@{
                    RecordType             = 'Property'
                    ComputerName           = $computerName
                    AdapterName            = $adapter.Name
                    InterfaceDescription   = $adapter.InterfaceDescription
                    PropertyDisplayName    = $property.DisplayName
                    RegistryKeyword        = $property.RegistryKeyword
                    CurrentDisplayValue    = $property.DisplayValue
                    RegistryValue          = Join-ValueList -Value $property.RegistryValue
                    PossibleDisplayValues  = Join-ValueList -Value $property.ValidDisplayValues
                    PossibleRegistryValues = Join-ValueList -Value $property.ValidRegistryValues
                    Notes                  = $null
                })
            }
        }

        return @($output.ToArray())
    }

    $rawResults = Invoke-BE200RemoteCommand -TargetIP $resolvedTargets -Credential $effectiveCredential -ScriptBlock $scriptBlock -ArgumentList (, (Get-BE200AllowedInterfaceDescriptions))

    foreach ($result in $rawResults) {
        if (-not $result.Success) {
            [void]$summaryRows.Add([pscustomobject]@{
                TargetIP            = $result.TargetIP
                ComputerName        = $null
                DiscoverySucceeded  = $false
                PropertyRowCount    = 0
                Notes               = $result.ErrorMessage
            })
            continue
        }

        $rows = @($result.Data)
        $propertyRows = @($rows | Where-Object { $_.RecordType -eq 'Property' })
        $infoRows = @($rows | Where-Object { $_.RecordType -eq 'Info' })
        $computerName = if ($rows.Count -gt 0) { $rows[0].ComputerName } else { $null }

        foreach ($row in $propertyRows) {
            [void]$discoveryRows.Add([pscustomobject]@{
                ComputerName           = $row.ComputerName
                TargetIP               = $result.TargetIP
                AdapterName            = $row.AdapterName
                InterfaceDescription   = $row.InterfaceDescription
                PropertyDisplayName    = $row.PropertyDisplayName
                RegistryKeyword        = $row.RegistryKeyword
                CurrentDisplayValue    = $row.CurrentDisplayValue
                RegistryValue          = $row.RegistryValue
                PossibleDisplayValues  = $row.PossibleDisplayValues
                PossibleRegistryValues = $row.PossibleRegistryValues
            })
        }

        $notes = if ($infoRows.Count -gt 0) {
            ($infoRows | ForEach-Object { $_.Notes } | Where-Object { $_ } | Sort-Object -Unique) -join ' | '
        }
        else {
            $null
        }

        [void]$summaryRows.Add([pscustomobject]@{
            TargetIP           = $result.TargetIP
            ComputerName       = $computerName
            DiscoverySucceeded = $true
            PropertyRowCount   = $propertyRows.Count
            Notes              = $notes
        })
    }

    Export-BE200Csv -InputObject @($discoveryRows.ToArray()) -Path $CsvPath
    Export-BE200Json -InputObject @($discoveryRows.ToArray()) -Path $JsonPath

    Write-Host
    Write-Host 'Discovery summary:' -ForegroundColor Green
    @($summaryRows.ToArray()) | Sort-Object TargetIP | Format-Table -AutoSize

    Write-Host
    Write-Host ("Discovery CSV exported to: {0}" -f $CsvPath) -ForegroundColor Green
    Write-Host ("Discovery JSON exported to: {0}" -f $JsonPath) -ForegroundColor Green
    Write-Host ("Transcript log exported to: {0}" -f $TranscriptPath) -ForegroundColor Green
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}

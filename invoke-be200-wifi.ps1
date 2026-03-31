[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Connect', 'Verify', 'Status')]
    [string]$Action,

    [Parameter()]
    [string[]]$TargetIP = @('ALL'),

    [Parameter()]
    [string]$Username = 'admin',

    [Parameter()]
    [string]$Password,

    [Parameter()]
    [string]$SSID,

    [Parameter()]
    [string]$WiFiPassword,

    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [string]$TranscriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

if ($Action -eq 'Connect') {
    if ([string]::IsNullOrWhiteSpace($SSID)) {
        throw 'The -SSID parameter is required for the Connect action.'
    }
}

if ($Action -eq 'Verify') {
    if ([string]::IsNullOrWhiteSpace($SSID)) {
        throw 'The -SSID parameter is required for the Verify action.'
    }
}

$resolvedTargets = Resolve-BE200TargetIPs -TargetIP $TargetIP
$effectiveCredential = Resolve-BE200Credential -Username $Username -Password $Password
$allowedInterfaceDescriptions = Get-BE200AllowedInterfaceDescriptions

if (-not $CsvPath) {
    $CsvPath = New-BE200OutputFilePath -Category 'csv' -BaseName ('be200-wifi-' + $Action.ToLowerInvariant()) -Extension 'csv'
}

if (-not $TranscriptPath) {
    $TranscriptPath = New-BE200OutputFilePath -Category 'transcripts' -BaseName ('invoke-be200-wifi-' + $Action.ToLowerInvariant()) -Extension 'log'
}

$results = New-Object System.Collections.Generic.List[object]
$transcriptStarted = $false

try {
    try {
        Start-Transcript -Path $TranscriptPath -Force | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Warning ("Transcript could not be started. {0}" -f $_.Exception.Message)
    }

    Write-BE200Section -Message ('Invoking BE200 Wi-Fi action: {0}' -f $Action)
    Write-Host ('Targets: {0}' -f ($resolvedTargets -join ', ')) -ForegroundColor Yellow
    if ($SSID) {
        Write-Host ('SSID: {0}' -f $SSID) -ForegroundColor Yellow
    }

    foreach ($target in $resolvedTargets) {
        Write-Host ''
        Write-Host ('--- Target: {0} ---' -f $target) -ForegroundColor Cyan

        try {
            $remoteResult = Invoke-Command -ComputerName $target -Credential $effectiveCredential -ErrorAction Stop -ScriptBlock {
                param($RequestedAction, $RequestedSSID, $RequestedWiFiPassword, $AllowedInterfaceDescriptions)

                $ErrorActionPreference = 'Stop'

                $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' })
                $be200Adapter = $null
                $selectionNote = $null

                foreach ($desc in $AllowedInterfaceDescriptions) {
                    $matching = @($allAdapters | Where-Object { $_.InterfaceDescription -eq $desc })
                    if ($matching.Count -eq 1) {
                        $be200Adapter = $matching[0]
                        break
                    }
                    if ($matching.Count -gt 1) {
                        $be200Adapter = ($matching | Sort-Object ifIndex | Select-Object -First 1)
                        $selectionNote = "Multiple adapters matched '$desc'; selected lowest ifIndex ($($be200Adapter.ifIndex))."
                        break
                    }
                }

                if (-not $be200Adapter) {
                    return [pscustomobject]@{
                        AdapterName    = ''
                        Action         = $RequestedAction
                        Success        = 'False'
                        State          = 'Error'
                        SSID           = ''
                        RequestedSSID  = $RequestedSSID
                        RadioType      = ''
                        Signal         = ''
                        Authentication = ''
                        Channel        = ''
                        Message        = 'No BE200 adapter found matching the allowlisted interface descriptions.'
                    }
                }

                $adapterDesc = $be200Adapter.InterfaceDescription

                if ($be200Adapter.Status -eq 'Disabled') {
                    return [pscustomobject]@{
                        AdapterName    = $be200Adapter.Name
                        Action         = $RequestedAction
                        Success        = 'False'
                        State          = 'Disabled'
                        SSID           = ''
                        RequestedSSID  = $RequestedSSID
                        RadioType      = ''
                        Signal         = ''
                        Authentication = ''
                        Channel        = ''
                        Message        = "BE200 adapter '$($be200Adapter.Name)' is Disabled. Enable it before Wi-Fi operations."
                    }
                }

                function Get-WlanInterfaceBlock {
                    param(
                        [string]$InterfaceDescription
                    )

                    try {
                        $raw = & netsh wlan show interfaces 2>&1
                    }
                    catch {
                        return $null
                    }

                    $text = ($raw | Out-String)
                    if (-not $text -or $text.Trim().Length -eq 0) {
                        return $null
                    }

                    $parsed = @()
                    $blocks = $text -split '(?=\s+Name\s+:)'
                    foreach ($block in $blocks) {
                        $info = @{}
                        $lines = $block -split "`n"
                        foreach ($line in $lines) {
                            if ($line -match '^\s+(.+?)\s{2,}:\s+(.+)$') {
                                $info[$Matches[1].Trim()] = $Matches[2].Trim()
                            }
                        }
                        if ($info.Count -gt 0 -and $info.ContainsKey('Name')) {
                            $parsed += , $info
                        }
                    }

                    foreach ($p in $parsed) {
                        if ($p['Description'] -eq $InterfaceDescription) {
                            return $p
                        }
                    }
                    return $null
                }

                $wlanBlock = Get-WlanInterfaceBlock -InterfaceDescription $adapterDesc
                $adapterName = if ($wlanBlock) { $wlanBlock['Name'] } else { $be200Adapter.Name }

                if ($RequestedAction -eq 'Connect') {
                    $escapedSSID = [System.Security.SecurityElement]::Escape($RequestedSSID)
                    $useWpa2 = (-not [string]::IsNullOrEmpty($RequestedWiFiPassword))

                    if ($useWpa2) {
                        $escapedPw = [System.Security.SecurityElement]::Escape($RequestedWiFiPassword)
                        $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$escapedSSID</name>
  <SSIDConfig>
    <SSID>
      <name>$escapedSSID</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$escapedPw</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
"@
                    }
                    else {
                        $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$escapedSSID</name>
  <SSIDConfig>
    <SSID>
      <name>$escapedSSID</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>open</authentication>
        <encryption>none</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
    </security>
  </MSM>
</WLANProfile>
"@
                    }
                    $tempFile = [System.IO.Path]::Combine(
                        [System.IO.Path]::GetTempPath(),
                        "be200-wifi-$([System.Guid]::NewGuid().ToString('N')).xml"
                    )

                    try {
                        [System.IO.File]::WriteAllText($tempFile, $profileXml, [System.Text.Encoding]::UTF8)
                        $addOut = & netsh wlan add profile "filename=$tempFile" "interface=$adapterName" 2>&1
                        $addText = ($addOut | Out-String).Trim()
                        Write-Host "Profile add: $addText"
                    }
                    finally {
                        if (Test-Path $tempFile) {
                            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                        }
                    }

                    $connOut = & netsh wlan connect "name=$RequestedSSID" "ssid=$RequestedSSID" "interface=$adapterName" 2>&1
                    $connText = ($connOut | Out-String).Trim()
                    Write-Host "Connect: $connText"

                    Start-Sleep -Seconds 5

                    $wlan = Get-WlanInterfaceBlock -InterfaceDescription $adapterDesc
                    $state  = if ($wlan -and $wlan['State'])          { $wlan['State'] }          else { 'unknown' }
                    $actual = if ($wlan -and $wlan['SSID'])           { $wlan['SSID'] }           else { '' }
                    $radio  = if ($wlan -and $wlan['Radio type'])     { $wlan['Radio type'] }     else { '' }
                    $sig    = if ($wlan -and $wlan['Signal'])         { $wlan['Signal'] }         else { '' }
                    $auth   = if ($wlan -and $wlan['Authentication']) { $wlan['Authentication'] } else { '' }
                    $ch     = if ($wlan -and $wlan['Channel'])        { $wlan['Channel'] }        else { '' }

                    $isConnected = ($state -eq 'connected')
                    $ssidMatch   = ($isConnected -and $actual -eq $RequestedSSID)

                    $msg = $connText
                    if ($selectionNote) { $msg = "$selectionNote $msg" }
                    if ($isConnected -and $ssidMatch) {
                        $msg = "Connected to '$actual'. $msg"
                    }
                    elseif ($isConnected -and -not $ssidMatch) {
                        $msg = "Connected but to '$actual' instead of requested '$RequestedSSID'. $msg"
                    }
                    else {
                        $msg = "Connection attempt completed but state is '$state'. $msg"
                    }

                    return [pscustomobject]@{
                        AdapterName    = $adapterName
                        Action         = 'Connect'
                        Success        = $(if ($ssidMatch) { 'True' } else { 'False' })
                        State          = $state
                        SSID           = $actual
                        RequestedSSID  = $RequestedSSID
                        RadioType      = $radio
                        Signal         = $sig
                        Authentication = $auth
                        Channel        = $ch
                        Message        = $msg
                    }
                }
                elseif ($RequestedAction -eq 'Verify') {
                    $wlan = Get-WlanInterfaceBlock -InterfaceDescription $adapterDesc
                    $state  = if ($wlan -and $wlan['State'])          { $wlan['State'] }          else { 'unknown' }
                    $actual = if ($wlan -and $wlan['SSID'])           { $wlan['SSID'] }           else { '' }
                    $radio  = if ($wlan -and $wlan['Radio type'])     { $wlan['Radio type'] }     else { '' }
                    $sig    = if ($wlan -and $wlan['Signal'])         { $wlan['Signal'] }         else { '' }
                    $auth   = if ($wlan -and $wlan['Authentication']) { $wlan['Authentication'] } else { '' }
                    $ch     = if ($wlan -and $wlan['Channel'])        { $wlan['Channel'] }        else { '' }

                    $isConnected = ($state -eq 'connected')
                    $ssidMatch   = ($isConnected -and $actual -eq $RequestedSSID)

                    $msg = ''
                    if ($selectionNote) { $msg = $selectionNote }
                    if ($isConnected -and $ssidMatch) {
                        $msg = "Verified: connected to '$actual'." + $(if ($msg) { " $msg" } else { '' })
                    }
                    elseif ($isConnected -and -not $ssidMatch) {
                        $msg = "Connected to '$actual' but expected '$RequestedSSID'." + $(if ($msg) { " $msg" } else { '' })
                    }
                    else {
                        $msg = "Not connected (state: '$state')." + $(if ($msg) { " $msg" } else { '' })
                    }

                    return [pscustomobject]@{
                        AdapterName    = $adapterName
                        Action         = 'Verify'
                        Success        = $(if ($ssidMatch) { 'True' } else { 'False' })
                        State          = $state
                        SSID           = $actual
                        RequestedSSID  = $RequestedSSID
                        RadioType      = $radio
                        Signal         = $sig
                        Authentication = $auth
                        Channel        = $ch
                        Message        = $msg
                    }
                }
                else {
                    $wlan = Get-WlanInterfaceBlock -InterfaceDescription $adapterDesc
                    $state  = if ($wlan -and $wlan['State'])          { $wlan['State'] }          else { 'unknown' }
                    $actual = if ($wlan -and $wlan['SSID'])           { $wlan['SSID'] }           else { '' }
                    $radio  = if ($wlan -and $wlan['Radio type'])     { $wlan['Radio type'] }     else { '' }
                    $sig    = if ($wlan -and $wlan['Signal'])         { $wlan['Signal'] }         else { '' }
                    $auth   = if ($wlan -and $wlan['Authentication']) { $wlan['Authentication'] } else { '' }
                    $ch     = if ($wlan -and $wlan['Channel'])        { $wlan['Channel'] }        else { '' }

                    $msg = if ($selectionNote) { $selectionNote } else { 'Status retrieved.' }

                    return [pscustomobject]@{
                        AdapterName    = $adapterName
                        Action         = 'Status'
                        Success        = 'True'
                        State          = $state
                        SSID           = $actual
                        RequestedSSID  = ''
                        RadioType      = $radio
                        Signal         = $sig
                        Authentication = $auth
                        Channel        = $ch
                        Message        = $msg
                    }
                }
            } -ArgumentList $Action, $SSID, $WiFiPassword, $allowedInterfaceDescriptions

            foreach ($row in @($remoteResult)) {
                $row | Add-Member -NotePropertyName 'TargetIP' -NotePropertyValue $target -Force
                Write-Host ("  Result: State={0}  SSID={1}  Success={2}" -f $row.State, $row.SSID, $row.Success)
                [void]$results.Add($row)
            }
        }
        catch {
            Write-Host ("  ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
            [void]$results.Add([pscustomobject]@{
                TargetIP       = $target
                AdapterName    = ''
                Action         = $Action
                Success        = 'False'
                State          = 'Error'
                SSID           = ''
                RequestedSSID  = $(if ($SSID) { $SSID } else { '' })
                RadioType      = ''
                Signal         = ''
                Authentication = ''
                Channel        = ''
                Message        = $_.Exception.Message
            })
        }
    }

    Export-BE200Csv -InputObject @($results.ToArray()) -Path $CsvPath

    Write-BE200Section -Message 'Wi-Fi action complete'
    Write-Host ("Results CSV: {0}" -f $CsvPath)
    Write-Host ("Targets processed: {0}" -f $results.Count)
}
finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

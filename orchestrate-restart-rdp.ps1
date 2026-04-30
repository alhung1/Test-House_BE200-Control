<#
.SYNOPSIS
  OS restart selected fleet hosts, wait for ping (and optional RDP port), optionally launch mstsc sequentially.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetIP,
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $true)]
    [string]$TranscriptPath,
    [Parameter()][int]$PingTimeoutSeconds = 600,
    [Parameter()][int]$PingIntervalSeconds = 5,
    [Parameter()][int]$PostRestartGraceSeconds = 15,
    [Parameter()][int]$RdpDelaySeconds = 3,
    [Parameter()][string]$ForbiddenControllerIp = '192.168.22.8',
    [switch]$CheckRdpPort,
    [switch]$AutoOpenRdp,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force
if ($env:BE200_NONINTERACTIVE -eq '1') { $ConfirmPreference = 'None' }
$cred = Resolve-BE200Credential -Username $Username -Password $Password
$parts = @($TargetIP -split '[,;|\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ordered = @(Resolve-BE200TargetIPs -TargetIP $parts)
if ($ordered -contains $ForbiddenControllerIp) {
    throw "Refusing to run: controller address $ForbiddenControllerIp must never be targeted."
}
$dir = Split-Path -Path $TranscriptPath -Parent
if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
Start-Transcript -Path $TranscriptPath -Force | Out-Null
$rows = New-Object System.Collections.Generic.List[object]
try {
    Write-BE200Section "Orchestrated OS restart + recovery for: $($ordered -join ', ')"
    foreach ($t in $ordered) {
        $row = [ordered]@{
            TargetIP = $t; RestartRequested = 'Yes'; RestartIssued = 'No'; RestartError = ''
            PingReachable = 'No'; RecoverySeconds = ''
            RdpPortOpen = $(if ($CheckRdpPort) { 'Pending' } else { 'Skipped' })
            RdpLaunched = 'No'; FinalStatus = 'Pending'; Message = ''
        }
        if ($DryRun) {
            $row.RestartIssued = 'Simulated'; $row.PingReachable = 'Simulated'; $row.RecoverySeconds = '0'
            $row.RdpPortOpen = if ($CheckRdpPort) { 'Simulated' } else { 'Skipped' }
            $row.RdpLaunched = if ($AutoOpenRdp) { 'Simulated' } else { 'No' }
            $row.FinalStatus = 'Simulated'; $row.Message = 'DryRun: no network actions.'
            [void]$rows.Add([pscustomobject]$row); continue
        }
        $issuedAt = Get-Date
        try {
            Invoke-Command -ComputerName $t -Credential $cred -ScriptBlock {
                Restart-Computer -Force -ErrorAction Stop
            } -ErrorAction Stop
            $row.RestartIssued = 'Yes'
        } catch {
            $row.RestartIssued = 'No'; $row.RestartError = $_.Exception.Message
            $row.PingReachable = 'N/A'; $row.RdpPortOpen = 'N/A'; $row.FinalStatus = 'Failed'
            $row.Message = 'Restart failed; skipped wait/RDP.'
            [void]$rows.Add([pscustomobject]$row); continue
        }
        $rowObj = [pscustomobject]$row
        $rowObj | Add-Member -NotePropertyName '_IssuedAt' -NotePropertyValue $issuedAt -Force
        $rowObj | Add-Member -NotePropertyName '_PingDeadline' -NotePropertyValue ($issuedAt.AddSeconds($PingTimeoutSeconds)) -Force
        [void]$rows.Add($rowObj)
        Start-Sleep -Seconds 2
    }
    if (-not $DryRun) {
        $any = @($rows | Where-Object { $_.RestartIssued -eq 'Yes' })
        if ($any.Count -gt 0) {
            Write-BE200Section "Grace period ${PostRestartGraceSeconds}s after restart commands"
            Start-Sleep -Seconds $PostRestartGraceSeconds
        }
        Write-BE200Section 'Ping polling'
        while ($true) {
            $pending = @($rows | Where-Object { $_.RestartIssued -eq 'Yes' -and $_.PingReachable -eq 'No' })
            if ($pending.Count -eq 0) { break }
            $now = Get-Date; $still = $false
            foreach ($r in $pending) {
                if ($now -gt $r._PingDeadline) {
                    $r.PingReachable = 'Timeout'
                    $r.Message = "No ping within ${PingTimeoutSeconds}s."
                    continue
                }
                if (Test-Connection -ComputerName $r.TargetIP -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                    $sec = [int](($now - $r._IssuedAt).TotalSeconds)
                    if ($sec -lt 0) { $sec = 0 }
                    $r.PingReachable = 'Yes'; $r.RecoverySeconds = "$sec"
                } else { $still = $true }
            }
            if (-not $still) { break }
            Start-Sleep -Seconds $PingIntervalSeconds
        }
        foreach ($r in $rows) {
            if ($r.RestartIssued -ne 'Yes') { continue }
            if ($r.PingReachable -eq 'No') {
                $r.PingReachable = 'Timeout'
                if (-not $r.Message) { $r.Message = 'Ping timeout.' }
            }
        }
        if ($CheckRdpPort) {
            foreach ($r in $rows) {
                if ($r.PingReachable -ne 'Yes') {
                    $r.RdpPortOpen = if ($r.PingReachable -in @('N/A', 'Timeout', 'Simulated')) { 'N/A' } else { 'Skipped' }
                    continue
                }
                try {
                    $tn = Test-NetConnection -ComputerName $r.TargetIP -Port 3389 -WarningAction SilentlyContinue -ErrorAction Stop
                    $r.RdpPortOpen = if ($tn.TcpTestSucceeded) { 'Yes' } else { 'No' }
                } catch { $r.RdpPortOpen = 'No' }
            }
        }
        foreach ($r in $rows) {
            if ($r.RestartIssued -eq 'No' -and $r.FinalStatus -eq 'Failed') { continue }
            if ($r.PingReachable -eq 'Yes') {
                $r.FinalStatus = 'Success'
                if (-not $r.Message) { $r.Message = 'Ping recovered.' }
            } else { $r.FinalStatus = 'Partial' }
        }
        $mstsc = Join-Path $env:SystemRoot 'System32\mstsc.exe'
        if ($AutoOpenRdp) {
            foreach ($t in $ordered) {
                $r = $rows | Where-Object { $_.TargetIP -eq $t } | Select-Object -First 1
                if (-not $r -or $r.PingReachable -ne 'Yes') { continue }
                if (-not (Test-Path -LiteralPath $mstsc)) { continue }
                Start-Process -FilePath $mstsc -ArgumentList @('/v', $r.TargetIP) -WindowStyle Normal
                $r.RdpLaunched = 'Yes'
                Start-Sleep -Seconds $RdpDelaySeconds
            }
        } else {
            foreach ($r in $rows) {
                if ($r.PingReachable -eq 'Yes') {
                    $r.Message = ($r.Message + ' Manual: use job Launch RDP or re-run with auto-open.').Trim()
                }
            }
        }
        foreach ($r in $rows) {
            $r.PSObject.Properties.Remove('_IssuedAt')
            $r.PSObject.Properties.Remove('_PingDeadline')
        }
    }
        $rowArray = foreach ($x in $rows) { $x }
    Export-BE200Csv -InputObject $rowArray -Path $CsvPath
} finally { try { Stop-Transcript } catch {} }
$failAll = @($rows | Where-Object { $_.FinalStatus -eq 'Failed' }).Count
if ($failAll -eq $rows.Count -and $rows.Count -gt 0) { exit 1 }
exit 0



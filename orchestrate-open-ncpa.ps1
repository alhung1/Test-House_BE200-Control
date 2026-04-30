<#
.SYNOPSIS
  Sequentially open WinRM to fleet hosts and launch ncpa.cpl on each target's interactive desktop (one-shot scheduled task).
.DESCRIPTION
  Does not modify IP, DNS, routes, or adapter settings. Optional mstsc launches run only on the orchestrator machine.
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
    [Parameter()][int]$DelaySecondsBetweenTargets = 3,
    [Parameter()][string]$ForbiddenControllerIp = '192.168.22.8',
    [switch]$OpenMstsc,
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
$mstscExe = Join-Path $env:SystemRoot 'System32\mstsc.exe'
try {
    Write-BE200Section "Open NCPA (interactive task) for: $($ordered -join ', ')"
    foreach ($t in $ordered) {
        $row = [ordered]@{
            TargetIP                 = $t
            RemoteSessionAttempted   = 'No'
            NcpaLaunchAttempted      = 'No'
            NcpaSuccess              = 'No'
            MstscLaunched            = 'No'
            Success                  = 'No'
            Message                  = ''
        }
        if ($DryRun) {
            $row.RemoteSessionAttempted = 'Simulated'
            $row.NcpaLaunchAttempted = 'Simulated'
            $row.NcpaSuccess = 'Simulated'
            $row.MstscLaunched = if ($OpenMstsc) { 'Simulated' } else { 'No' }
            $row.Success = 'Simulated'
            $row.Message = 'DryRun: no remote actions.'
            [void]$rows.Add([pscustomobject]$row)
            continue
        }
        $row.RemoteSessionAttempted = 'Yes'
        $row.NcpaLaunchAttempted = 'Yes'
        $remoteErr = $null
        try {
            $remoteErr = Invoke-Command -ComputerName $t -Credential $cred -ScriptBlock {
                param([string]$TaskUserName, [string]$TaskPassword)
                $taskName = 'BE200_OpenNcpa_' + ([guid]::NewGuid().ToString('N').Substring(0, 12))
                $qUser = if ($TaskUserName -match '\\') {
                    $TaskUserName.Trim()
                }
                else {
                    '{0}\{1}' -f $env:COMPUTERNAME, $TaskUserName.Trim()
                }
                try {
                    $service = New-Object -ComObject 'Schedule.Service'
                    $service.Connect()
                    $folder = $service.GetFolder('\')
                    $taskDef = $service.NewTask(0)
                    $taskDef.RegistrationInfo.Description = 'BE200 Open Network Connections (one-shot)'
                    $taskDef.Settings.Enabled = $true
                    $taskDef.Settings.AllowDemandStart = $true
                    $taskDef.Settings.DisallowStartIfOnBatteries = $false
                    $taskDef.Settings.StopIfGoingOnBatteries = $false
                    $taskDef.Settings.ExecutionTimeLimit = 'PT2M'
                    $taskDef.Principal.UserId = $qUser
                    $taskDef.Principal.LogonType = 3  # InteractiveTokenOrPassword
                    $act = $taskDef.Actions.Create(0)
                    $act.Path = 'rundll32.exe'
                    $act.Arguments = 'shell32.dll,Control_RunDLL ncpa.cpl'
                    $folder.RegisterTaskDefinition(
                        $taskName, $taskDef, 6, $qUser, $TaskPassword, 3
                    ) | Out-Null
                    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                    return $null
                }
                catch {
                    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                    return $_.Exception.Message
                }
            } -ArgumentList $Username, $Password -ErrorAction Stop
        }
        catch {
            $remoteErr = $_.Exception.Message
        }
        if ([string]::IsNullOrWhiteSpace($remoteErr)) {
            $row.NcpaSuccess = 'Yes'
            $row.Success = 'Yes'
            $row.Message = 'Network Connections (ncpa.cpl) opened via interactive scheduled task on the target desktop.'
        }
        else {
            $row.NcpaSuccess = 'No'
            $row.Success = 'No'
            $row.Message = $remoteErr
        }
        if ($OpenMstsc) {
            if (Test-Path -LiteralPath $mstscExe) {
                try {
                    Start-Process -FilePath $mstscExe -ArgumentList @('/v', $t) -WindowStyle Normal -ErrorAction Stop
                    $row.MstscLaunched = 'Yes'
                }
                catch {
                    $row.MstscLaunched = 'No'
                    $row.Message = ($row.Message + ' mstsc: ' + $_.Exception.Message).Trim()
                }
            }
            else {
                $row.MstscLaunched = 'No'
                $row.Message = ($row.Message + ' mstsc.exe not found on orchestrator.').Trim()
            }
        }
        [void]$rows.Add([pscustomobject]$row)
        if ($DelaySecondsBetweenTargets -gt 0 -and $t -ne $ordered[-1]) {
            Start-Sleep -Seconds $DelaySecondsBetweenTargets
        }
    }
    $rowArray = foreach ($x in $rows) { $x }
    Export-BE200Csv -InputObject $rowArray -Path $CsvPath
}
finally { try { Stop-Transcript } catch { } }
$failed = @($rows | Where-Object { $_.Success -eq 'No' }).Count
if ($failed -eq $rows.Count -and $rows.Count -gt 0) { exit 1 }
exit 0

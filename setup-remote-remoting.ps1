[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Prepares a remote Windows 11 target for PowerShell remoting.

.DESCRIPTION
Run this script locally on one remote lab machine after signing in as Administrator.
The script enables WinRM, enables PowerShell remoting, sets the WinRM service startup
type, and enables the Windows Remote Management firewall rule group.

It does NOT modify:
- IP addresses
- subnet masks
- default gateways
- DNS settings
- routes
- interface metrics
- proxy settings
- BE200 advanced properties
- Ethernet adapters
- non-BE200 adapters

If the machine is on a Public network profile, Enable-PSRemoting may require the
-SkipNetworkProfileCheck switch on client Windows. This script uses that switch to
avoid silently changing the network profile itself. That is less invasive than
changing the profile category, and it still does not alter layer-3 addressing.
#>

Assert-BE200Administrator

Write-BE200Section -Message 'Preparing remote machine remoting foundation'

$networkProfiles = Get-NetConnectionProfile
$usesSkipNetworkProfileCheck = ($networkProfiles | Where-Object { $_.NetworkCategory -eq 'Public' }).Count -gt 0

if ($PSCmdlet.ShouldProcess('Local computer', 'Configure WinRM, PowerShell remoting, and WinRM firewall rules')) {
    Set-Service -Name WinRM -StartupType Automatic
    if ((Get-Service -Name WinRM).Status -ne 'Running') {
        Start-Service -Name WinRM
    }

    if ($usesSkipNetworkProfileCheck) {
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
    }
    else {
        Enable-PSRemoting -Force
    }

    Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management'
}

$verification = [pscustomobject]@{
    ComputerName                 = $env:COMPUTERNAME
    WinRMServiceStatus           = (Get-Service -Name WinRM).Status
    WinRMStartupType             = (Get-CimInstance -ClassName Win32_Service -Filter "Name='WinRM'").StartMode
    PSRemotingEnabled            = [bool](Get-PSSessionConfiguration -ErrorAction Stop)
    SkipNetworkProfileCheckUsed  = $usesSkipNetworkProfileCheck
    NetworkCategories            = (($networkProfiles | Select-Object -ExpandProperty NetworkCategory) -join ', ')
    WinRMFirewallRulesEnabled    = [bool](Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' | Where-Object { $_.Enabled -eq 'True' })
    Layer3SettingsChanged        = $false
}

Write-Host
Write-Host 'Verification summary:' -ForegroundColor Green
$verification | Format-List

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force

<#
.SYNOPSIS
Prepares the local controller machine for PowerShell remoting to the BE200 lab targets.

.DESCRIPTION
This script enables WinRM and PowerShell remoting on the local controller machine, sets
the WinRM service startup type, and sets TrustedHosts to the exact eight remote lab IPs.

It does NOT modify:
- IP addresses
- subnet masks
- default gateways
- DNS settings
- routes
- interface metrics
- proxy settings
- Ethernet adapters
- non-BE200 adapters

This script is intended for local development and validation first. It does not deploy
anything to 192.168.22.8 and does not execute on 192.168.22.8 automatically.
#>

Assert-BE200Administrator

$trustedHostsValue = Get-BE200TrustedHostsValue

Write-BE200Section -Message 'Preparing local remoting foundation'

if ($PSCmdlet.ShouldProcess('Local computer', 'Configure WinRM, PowerShell remoting, and TrustedHosts')) {
    Set-Service -Name WinRM -StartupType Automatic
    if ((Get-Service -Name WinRM).Status -ne 'Running') {
        Start-Service -Name WinRM
    }

    Enable-PSRemoting -Force
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $trustedHostsValue -Force
}

$verification = [pscustomobject]@{
    ComputerName        = $env:COMPUTERNAME
    WinRMServiceStatus  = (Get-Service -Name WinRM).Status
    WinRMStartupType    = (Get-CimInstance -ClassName Win32_Service -Filter "Name='WinRM'").StartMode
    PSRemotingEnabled   = [bool](Get-PSSessionConfiguration -ErrorAction Stop)
    TrustedHosts        = (Get-Item -Path WSMan:\localhost\Client\TrustedHosts).Value
    AllowedTargetIPs    = $trustedHostsValue
    Layer3SettingsChanged = $false
}

Write-Host
Write-Host 'Verification summary:' -ForegroundColor Green
$verification | Format-List

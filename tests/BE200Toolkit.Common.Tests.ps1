Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\internal\BE200Toolkit.Common.psm1'
Import-Module $modulePath -Force

Describe 'BE200 toolkit shared safety helpers' {
    It 'returns the exact allowed target list' {
        $targets = Get-BE200AllowedTargetIPs

        $targets.Count | Should Be 8
        ($targets -join ',') | Should Be (@(
            '192.168.22.221'
            '192.168.22.222'
            '192.168.22.223'
            '192.168.22.224'
            '192.168.22.225'
            '192.168.22.226'
            '192.168.22.227'
            '192.168.22.228'
        ) -join ',')
    }

    It 'resolves ALL to the exact allowed target list' {
        $resolved = Resolve-BE200TargetIPs -TargetIP 'ALL'

        ($resolved -join ',') | Should Be ((Get-BE200AllowedTargetIPs) -join ',')
    }

    It 'deduplicates and validates explicit target lists' {
        $resolved = Resolve-BE200TargetIPs -TargetIP @(
            '192.168.22.221'
            '192.168.22.221'
            '192.168.22.223'
        )

        ($resolved -join ',') | Should Be (@(
            '192.168.22.221'
            '192.168.22.223'
        ) -join ',')
    }

    It 'rejects out-of-scope targets' {
        { Resolve-BE200TargetIPs -TargetIP '192.168.22.30' } | Should Throw
    }

    It 'accepts only the exact allowed BE200 interface descriptions' {
        (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription 'Intel(R) Wi-Fi 7 BE200 320MHz') | Should Be $true
        (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription 'Intel(R) Wi-Fi 7 BE200 320MHz #6') | Should Be $true
        (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription 'Wi-Fi') | Should Be $false
        (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription 'Intel(R) Ethernet Controller') | Should Be $false
    }

    It 'prefers Up over Disconnected and excludes Not Present when selecting adapters' {
        $selection = Select-BE200PreferredAdapters -Adapters @(
            [pscustomobject]@{
                Name = 'Wi-Fi'
                InterfaceDescription = 'Intel(R) Wi-Fi 7 BE200 320MHz'
                Status = 'Disconnected'
            }
            [pscustomobject]@{
                Name = 'Wi-Fi 2'
                InterfaceDescription = 'Intel(R) Wi-Fi 7 BE200 320MHz'
                Status = 'Up'
            }
            [pscustomobject]@{
                Name = 'Wi-Fi 3'
                InterfaceDescription = 'Intel(R) Wi-Fi 7 BE200 320MHz #6'
                Status = 'Not Present'
            }
        )

        $selection.SelectedAdapters.Count | Should Be 1
        $selection.SelectedAdapters[0].Name | Should Be 'Wi-Fi 2'
        $selection.SelectionIssues.Count | Should Be 0
    }

    It 'creates a PSCredential from explicit username and plaintext password' {
        $credential = Resolve-BE200Credential -Username 'admin' -Password 'password'

        ($credential.GetType().FullName) | Should Be 'System.Management.Automation.PSCredential'
        $credential.UserName | Should Be 'admin'
    }

    It 'parses boolean-like values for config rows' {
        (ConvertTo-BE200Boolean -Value 'TRUE') | Should Be $true
        (ConvertTo-BE200Boolean -Value 'yes') | Should Be $true
        (ConvertTo-BE200Boolean -Value '0') | Should Be $false
        (ConvertTo-BE200Boolean -Value $null) | Should Be $false
    }

    It 'resolves scope ALL without requiring a TargetIP column' {
        $resolved = Resolve-BE200ScopeTargets -Scope 'ALL' -TargetIP ''

        ($resolved -join ',') | Should Be ((Get-BE200AllowedTargetIPs) -join ',')
    }

    It 'resolves explicit scope target strings into exact allowed targets' {
        $resolved = Resolve-BE200ScopeTargets -Scope 'Targets' -TargetIP '192.168.22.221, 192.168.22.223'

        ($resolved -join ',') | Should Be '192.168.22.221,192.168.22.223'
    }

    It 'prefers RegistryKeyword when resolving a property selector' {
        $selector = Resolve-BE200PropertySelector -RegistryKeyword '*SomeKeyword' -PropertyDisplayName 'Some Property'

        $selector.IdentifierType | Should Be 'RegistryKeyword'
        $selector.IdentifierValue | Should Be '*SomeKeyword'
    }
}

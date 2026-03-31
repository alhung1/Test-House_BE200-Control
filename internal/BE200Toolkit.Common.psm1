$script:AllowedTargetIPs = @(
    '192.168.22.221'
    '192.168.22.222'
    '192.168.22.223'
    '192.168.22.224'
    '192.168.22.225'
    '192.168.22.226'
    '192.168.22.227'
    '192.168.22.228'
)

$script:AllowedInterfaceDescriptions = @(
    'Intel(R) Wi-Fi 7 BE200 320MHz'
    'Intel(R) Wi-Fi 7 BE200 320MHz #6'
)

function Get-BE200ToolkitRoot {
    [CmdletBinding()]
    param()

    return (Split-Path -Path $PSScriptRoot -Parent)
}

function Get-BE200AllowedTargetIPs {
    [CmdletBinding()]
    param()

    return @($script:AllowedTargetIPs)
}

function Get-BE200AllowedAdapterNames {
    [CmdletBinding()]
    param()

    return Get-BE200AllowedInterfaceDescriptions
}

function Get-BE200AllowedInterfaceDescriptions {
    [CmdletBinding()]
    param()

    return @($script:AllowedInterfaceDescriptions)
}

function Get-BE200TrustedHostsValue {
    [CmdletBinding()]
    param()

    return ((Get-BE200AllowedTargetIPs) -join ',')
}

function Test-BE200AdapterNameAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterName
    )

    return (Test-BE200InterfaceDescriptionAllowed -InterfaceDescription $AdapterName)
}

function Test-BE200InterfaceDescriptionAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceDescription
    )

    return (Get-BE200AllowedInterfaceDescriptions) -contains $InterfaceDescription
}

function Select-BE200PreferredAdapters {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Adapters = @(),

        [Parameter()]
        [string[]]$AllowedInterfaceDescriptions = (Get-BE200AllowedInterfaceDescriptions)
    )

    $selected = New-Object System.Collections.Generic.List[object]
    $issues = New-Object System.Collections.Generic.List[string]

    foreach ($interfaceDescription in $AllowedInterfaceDescriptions) {
        $matching = @(
            $Adapters |
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
                [void]$issues.Add(("Multiple adapters matched allowlisted InterfaceDescription '{0}' with Status '{1}'. Skipping to avoid ambiguity." -f $interfaceDescription, $preferredStatus))
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

        [void]$issues.Add(("Multiple adapters matched allowlisted InterfaceDescription '{0}' with non-preferred statuses. Skipping to avoid ambiguity." -f $interfaceDescription))
    }

    return [pscustomobject]@{
        SelectedAdapters = @($selected.ToArray())
        SelectionIssues  = @($issues.ToArray())
    }
}

function Resolve-BE200TargetIPs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$TargetIP = @('ALL')
    )

    $allowed = Get-BE200AllowedTargetIPs

    if (-not $TargetIP -or $TargetIP.Count -eq 0) {
        return $allowed
    }

    if ($TargetIP.Count -eq 1 -and $TargetIP[0].ToUpperInvariant() -eq 'ALL') {
        return $allowed
    }

    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $TargetIP) {
        foreach ($normalized in (Split-BE200TargetString -TargetIP $entry)) {
            if (-not $normalized) {
                continue
            }

            if ($normalized.ToUpperInvariant() -eq 'ALL') {
                throw "The ALL target scope cannot be mixed with explicit target IPs."
            }

            if ($allowed -notcontains $normalized) {
                throw "Target '$normalized' is outside the allowed scope."
            }

            if ($resolved -notcontains $normalized) {
                [void]$resolved.Add($normalized)
            }
        }
    }

    if ($resolved.Count -eq 0) {
        throw 'No valid target IPs were provided.'
    }

    return @($resolved.ToArray())
}

function Split-BE200TargetString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$TargetIP
    )

    if ([string]::IsNullOrWhiteSpace($TargetIP)) {
        return @()
    }

    $parts = $TargetIP -split '[,;|\s]+'
    return @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Resolve-BE200ScopeTargets {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Scope = 'ALL',

        [Parameter()]
        [AllowEmptyString()]
        [string]$TargetIP
    )

    $normalizedScope = if ([string]::IsNullOrWhiteSpace($Scope)) {
        if ([string]::IsNullOrWhiteSpace($TargetIP)) { 'ALL' } else { 'TARGETS' }
    }
    else {
        $Scope.Trim().ToUpperInvariant()
    }

    switch ($normalizedScope) {
        'ALL' {
            if (-not [string]::IsNullOrWhiteSpace($TargetIP) -and $TargetIP.Trim().ToUpperInvariant() -ne 'ALL') {
                throw "Scope 'ALL' cannot be combined with explicit TargetIP values."
            }

            return Resolve-BE200TargetIPs -TargetIP 'ALL'
        }
        'TARGET' { return Resolve-BE200TargetIPs -TargetIP (Split-BE200TargetString -TargetIP $TargetIP) }
        'TARGETS' { return Resolve-BE200TargetIPs -TargetIP (Split-BE200TargetString -TargetIP $TargetIP) }
        'SUBSET' { return Resolve-BE200TargetIPs -TargetIP (Split-BE200TargetString -TargetIP $TargetIP) }
        default {
            throw "Unsupported scope '$Scope'. Allowed values are ALL, TARGET, TARGETS, or SUBSET."
        }
    }
}

function ConvertTo-BE200Boolean {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value,

        [Parameter()]
        [bool]$Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }

    $text = $Value.ToString().Trim()
    if (-not $text) {
        return $Default
    }

    switch ($text.ToUpperInvariant()) {
        'TRUE' { return $true }
        'FALSE' { return $false }
        'YES' { return $true }
        'NO' { return $false }
        'Y' { return $true }
        'N' { return $false }
        '1' { return $true }
        '0' { return $false }
        default { return $Default }
    }
}

function ConvertTo-BE200ListString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [string]) {
        return $Value.Trim()
    }

    if ($Value -is [System.Collections.IEnumerable]) {
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

    return $Value.ToString()
}

function Resolve-BE200PropertySelector {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$RegistryKeyword,

        [Parameter()]
        [AllowEmptyString()]
        [string]$PropertyDisplayName
    )

    if (-not [string]::IsNullOrWhiteSpace($RegistryKeyword)) {
        return [pscustomobject]@{
            IdentifierType  = 'RegistryKeyword'
            IdentifierValue = $RegistryKeyword.Trim()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PropertyDisplayName)) {
        return [pscustomobject]@{
            IdentifierType  = 'DisplayName'
            IdentifierValue = $PropertyDisplayName.Trim()
        }
    }

    throw 'A property selector requires RegistryKeyword or PropertyDisplayName.'
}

function Resolve-BE200Credential {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [string]$Username = 'admin',

        [Parameter()]
        [string]$Password
    )

    if ($Credential) {
        return $Credential
    }

    if ($PSBoundParameters.ContainsKey('Password')) {
        if ([string]::IsNullOrEmpty($Password)) {
            if ($env:BE200_NONINTERACTIVE -eq '1') {
                throw 'Non-interactive BE200 execution requires a non-empty -Password value. The GUI path must not fall back to Get-Credential.'
            }

            throw 'The Password parameter was provided but empty.'
        }

        $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential ($Username, $securePassword)
    }

    if ($env:BE200_NONINTERACTIVE -eq '1') {
        throw 'Non-interactive BE200 execution requires explicit -Username and -Password or -Credential. The GUI path must not fall back to Get-Credential.'
    }

    return Get-Credential -UserName $Username -Message 'Enter the remoting credential for the Windows 11 BE200 lab targets.'
}

function Test-BE200Administrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-BE200Administrator {
    [CmdletBinding()]
    param()

    if (-not (Test-BE200Administrator)) {
        throw 'This script must be run from an elevated PowerShell session.'
    }
}

function New-BE200OutputRoot {
    [CmdletBinding()]
    param()

    $root = Join-Path (Get-BE200ToolkitRoot) 'output'
    foreach ($child in @('csv', 'json', 'reports', 'transcripts', 'logs')) {
        $path = Join-Path $root $child
        if (-not (Test-Path -LiteralPath $path)) {
            [void](New-Item -ItemType Directory -Path $path -Force)
        }
    }

    return $root
}

function New-BE200OutputFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('csv', 'json', 'reports', 'transcripts', 'logs')]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $outputRoot = New-BE200OutputRoot
    $categoryPath = Join-Path $outputRoot $Category
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeBaseName = ($BaseName -replace '[^a-zA-Z0-9._-]', '-').Trim('-')

    if (-not $safeBaseName) {
        $safeBaseName = 'artifact'
    }

    return (Join-Path $categoryPath ('{0}-{1}.{2}' -f $safeBaseName, $timestamp, $Extension))
}

function Start-BE200ToolkitTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $path = New-BE200OutputFilePath -Category 'transcripts' -BaseName $Name -Extension 'log'
    Start-Transcript -Path $path -Force | Out-Null
    return $path
}

function Stop-BE200ToolkitTranscript {
    [CmdletBinding()]
    param()

    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Ignore the case where no transcript is active.
    }
}

function Write-BE200Section {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Export-BE200Csv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    $InputObject | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Export-BE200Json {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    $InputObject | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
}

function Import-BE200DataFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Input file not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    switch ($extension.ToLowerInvariant()) {
        '.json' {
            $content = Get-Content -Path $Path -Raw -Encoding UTF8
            if (-not $content.Trim()) {
                return @()
            }

            $data = $content | ConvertFrom-Json
            if ($data -is [System.Collections.IEnumerable] -and -not ($data -is [string])) {
                return @($data)
            }

            return @($data)
        }
        '.csv' {
            return @(Import-Csv -Path $Path)
        }
        default {
            throw "Unsupported input file type '$extension'. Use CSV or JSON."
        }
    }
}

function Get-BE200MatchingAdapters {
    [CmdletBinding()]
    param()

    $selection = Select-BE200PreferredAdapters -Adapters @(Get-NetAdapter -ErrorAction SilentlyContinue)

    return @($selection.SelectedAdapters)
}

function Invoke-BE200RemoteCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TargetIP,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList = @()
    )

    $resolvedTargets = Resolve-BE200TargetIPs -TargetIP $TargetIP
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($target in $resolvedTargets) {
        try {
            $remoteData = Invoke-Command -ComputerName $target -Credential $Credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
            [void]$results.Add([pscustomobject]@{
                TargetIP     = $target
                Success      = $true
                ErrorMessage = $null
                Data         = $remoteData
            })
        }
        catch {
            [void]$results.Add([pscustomobject]@{
                TargetIP     = $target
                Success      = $false
                ErrorMessage = $_.Exception.Message
                Data         = $null
            })
        }
    }

    return @($results.ToArray())
}

Export-ModuleMember -Function @(
    'Assert-BE200Administrator'
    'ConvertTo-BE200Boolean'
    'ConvertTo-BE200ListString'
    'Export-BE200Csv'
    'Export-BE200Json'
    'Get-BE200AllowedAdapterNames'
    'Get-BE200AllowedInterfaceDescriptions'
    'Get-BE200AllowedTargetIPs'
    'Get-BE200MatchingAdapters'
    'Get-BE200ToolkitRoot'
    'Get-BE200TrustedHostsValue'
    'Import-BE200DataFile'
    'Invoke-BE200RemoteCommand'
    'New-BE200OutputFilePath'
    'New-BE200OutputRoot'
    'Resolve-BE200Credential'
    'Resolve-BE200PropertySelector'
    'Resolve-BE200ScopeTargets'
    'Resolve-BE200TargetIPs'
    'Select-BE200PreferredAdapters'
    'Split-BE200TargetString'
    'Start-BE200ToolkitTranscript'
    'Stop-BE200ToolkitTranscript'
    'Test-BE200AdapterNameAllowed'
    'Test-BE200InterfaceDescriptionAllowed'
    'Test-BE200Administrator'
    'Write-BE200Section'
)

# BE200 Control Console — start Flask GUI (double-click Launch-BE200-GUI.bat)
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$GuiDir = Join-Path $Root 'gui'
$AppPy = Join-Path $GuiDir 'app.py'
$ReqTxt = Join-Path $GuiDir 'requirements.txt'
$ConfigPath = Join-Path $GuiDir 'config.json'

function Write-Err($msg) {
    Write-Host $msg -ForegroundColor Red
}

if (-not (Test-Path -LiteralPath $GuiDir)) {
    Write-Err "GUI folder not found: $GuiDir"
    exit 1
}
if (-not (Test-Path -LiteralPath $AppPy)) {
    Write-Err "Missing $AppPy"
    exit 1
}

$python = $null
$pythonArgs = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $python = 'py'
        $pythonArgs = @('-3')
    }
}
if (-not $python -and (Get-Command python -ErrorAction SilentlyContinue)) {
    python -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $python = 'python'
        $pythonArgs = @()
    }
}
if (-not $python) {
    Write-Err "Python 3.9+ not found. Install Python and ensure 'py' or 'python' is on PATH."
    exit 1
}

Push-Location -LiteralPath $GuiDir
try {
    & $python @pythonArgs -c "import flask" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Flask not available; installing from requirements.txt ..." -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $ReqTxt)) {
            Write-Err "Missing $ReqTxt"
            exit 1
        }
        & $python @pythonArgs -m pip install -r $ReqTxt
        if ($LASTEXITCODE -ne 0) {
            Write-Err "pip install failed."
            exit 1
        }
    }
} finally {
    Pop-Location
}

$listenHost = '127.0.0.1'
$listenPort = 5000
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.app.host) { $listenHost = [string]$cfg.app.host }
        if ($null -ne $cfg.app.port) { $listenPort = [int]$cfg.app.port }
    } catch {
        Write-Host "(Using default URL; could not read gui\config.json: $($_.Exception.Message))" -ForegroundColor DarkYellow
    }
}

$url = "http://${listenHost}:${listenPort}/"
Write-Host ""
Write-Host "BE200 Control Console" -ForegroundColor Cyan
Write-Host "  Working directory: $GuiDir"
Write-Host "  Opening $url when the server is ready (browser may open once)."
Write-Host "  Press Ctrl+C in this window to stop the server."
Write-Host ""

if ($env:BE200_LAUNCHER_NO_BROWSER -ne '1') {
    $u = $url -replace "'", "''"
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
        "Start-Sleep -Seconds 2; Start-Process '$u'"
    ) | Out-Null
}

Push-Location -LiteralPath $GuiDir
try {
    & $python @pythonArgs app.py
    exit $LASTEXITCODE
} finally {
    Pop-Location
}

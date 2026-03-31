$ErrorActionPreference = "Stop"

$GuiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $GuiRoot "config.json"
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$Url = "http://{0}:{1}" -f $Config.app.host, $Config.app.port
$AppPath = Join-Path $GuiRoot "app.py"

Write-Host "BE200 GUI root: $GuiRoot" -ForegroundColor Cyan
Write-Host "Toolkit root: $($Config.toolkit_root)" -ForegroundColor Cyan
Write-Host "Starting local GUI at $Url" -ForegroundColor Green
Write-Host "Python command: py -3" -ForegroundColor Yellow

try {
    & py -3 -m pip show Flask | Out-Null
}
catch {
    Write-Host "Flask is not installed. Install dependencies first with:" -ForegroundColor Yellow
    Write-Host "  py -3 -m pip install -r `"$GuiRoot\requirements.txt`"" -ForegroundColor Yellow
    throw
}

Start-Process $Url | Out-Null
Set-Location -LiteralPath $GuiRoot
& py -3 $AppPath

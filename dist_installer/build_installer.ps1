param(
  [string]$Version = "1.0.1",
  [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$issPath = Join-Path $PSScriptRoot "Leemon.iss"

if (-not (Test-Path $IsccPath)) {
  throw "ISCC.exe not found: $IsccPath"
}

if (-not (Test-Path $issPath)) {
  throw "Installer script not found: $issPath"
}

Write-Host "Building installer version $Version..."

Push-Location $repoRoot
try {
  & $IsccPath "/DMyAppVersion=$Version" "/DOutputBaseFilename=Leemon_Setup_$Version" $issPath
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "Done."
Write-Host "Installer output dir: $PSScriptRoot"

param(
  [string]$Version = "1.0.1",
  [string]$Channel = "stable"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$updaterProject = Join-Path $repoRoot "updater\Leemon.Updater.csproj"
$updaterPublishDir = Join-Path $repoRoot "updater\bin\Release\net8.0-windows\win-x64\publish"
$zipPath = Join-Path $PSScriptRoot ("Leemon_{0}_win_x64.zip" -f $Version)

Write-Host "Building Flutter Windows release $Version ($Channel)..."
Push-Location $repoRoot
try {
  flutter build windows --release --dart-define=APP_UPDATE_CHANNEL=$Channel --dart-define=APP_UPDATE_PACKAGE_TYPE=zip

  Write-Host "Publishing updater..."
  dotnet publish $updaterProject -c Release
}
finally {
  Pop-Location
}

if (-not (Test-Path $releaseDir)) {
  throw "Flutter release folder not found: $releaseDir"
}

if (-not (Test-Path $updaterPublishDir)) {
  throw "Updater publish folder not found: $updaterPublishDir"
}

if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Write-Host "Packing update zip..."
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath

Write-Host ""
Write-Host "Done."
Write-Host "Release folder: $releaseDir"
Write-Host "Updater publish: $updaterPublishDir"
Write-Host "Update zip: $zipPath"

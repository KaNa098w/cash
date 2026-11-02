$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$versionSource = Get-Content -LiteralPath (Join-Path $repository 'lib\core\service\app_build_info.dart') -Raw
$versionMatch = [regex]::Match($versionSource, "appVersion\s*=\s*'([^']+)'")
if (-not $versionMatch.Success) { throw 'AppBuildInfo.appVersion не найден.' }
$releaseVersion = $versionMatch.Groups[1].Value
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Версия выпуска должна иметь вид 2.0.7.' }
Push-Location -LiteralPath $repository
try {
    dotnet publish updater\Leemon.Updater.csproj -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось собрать обновлятор.' }
    # Use the exact same version in Windows metadata and the POS update API.
    flutter build windows --release --build-name $releaseVersion
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось собрать кассу.' }
    $bundle = Join-Path $repository 'build\windows\x64\runner\Release'
    $helperDirectory = Join-Path $bundle 'updater'
    New-Item -ItemType Directory -Path $helperDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repository 'updater\bin\Release\net8.0-windows\win-x64\publish\Leemon.Updater.exe') -Destination (Join-Path $helperDirectory 'Leemon.Updater.exe') -Force
    # The old helper skips updater/; the root copy bootstraps the new helper.
    Copy-Item -LiteralPath (Join-Path $helperDirectory 'Leemon.Updater.exe') -Destination (Join-Path $bundle 'Leemon.Updater.exe') -Force
    foreach ($relative in @('Leemon.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', 'updater\Leemon.Updater.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $relative) -PathType Leaf)) { throw "Неполная сборка: $relative" }
    }
    foreach ($item in Get-ChildItem -LiteralPath $bundle -Force) {
        $allowedDirectory = $item.PSIsContainer -and $item.Name -in @('data', 'updater')
        $allowedFile = -not $item.PSIsContainer -and ($item.Name -in @('Leemon.exe', 'Leemon.Updater.exe', 'native_assets.json') -or $item.Extension -in @('.dll', '.pdb'))
        if (-not ($allowedDirectory -or $allowedFile)) { throw "Лишний файл в сборке: $($item.Name). Пакет не создан." }
    }
    $packages = Join-Path $repository 'build\update-packages'
    New-Item -ItemType Directory -Path $packages -Force | Out-Null
    $archive = Join-Path $packages "Leemon-$releaseVersion-windows.zip"
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -Force
    $metadata = [ordered]@{
        version = $releaseVersion
        package_type = 'zip'
        file_size = (Get-Item -LiteralPath $archive).Length
        checksum_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath ($archive + '.json') -Encoding UTF8
    Write-Host "Пакет готов: $archive"
    Write-Host 'Пакет не опубликован. Новый helper включён также в корень ZIP для перехода со старых версий.'
} finally { Pop-Location }

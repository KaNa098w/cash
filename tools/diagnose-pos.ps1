param([string]$AppDirectory = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'

# This launcher collects only application logs and crash metadata. It does not
# read POS preferences, database files, credentials or PIN codes.
function Protect-LogText([string]$Value) {
    $Value = $Value -replace '(/organizations/pos/)[^/\s?"'']+', '$1<POS_KEY>'
    $Value = $Value -replace '(?im)(X-Return-Access-Key|Authorization|accessToken|refreshToken|pin_code|pinCode)\s*[=:]\s*[^\r\n,}]+', '$1=<redacted>'
    return $Value
}

$candidate = Join-Path $AppDirectory 'Leemon.exe'
if (-not (Test-Path -LiteralPath $candidate)) {
    $candidate = Join-Path $AppDirectory 'build\windows\x64\runner\Release\Leemon.exe'
}
if (-not (Test-Path -LiteralPath $candidate)) {
    throw 'Leemon.exe не найден. Положите diagnose-pos.ps1 и Диагностика кассы.cmd в папку с Leemon.exe.'
}
$executable = (Resolve-Path -LiteralPath $candidate).Path
$appFolder = Split-Path -Parent $executable
if (Get-Process -Name Leemon -ErrorAction SilentlyContinue) {
    throw 'Касса уже запущена. Закройте её штатно и повторите диагностику. Процессы принудительно не завершаются.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportFolder = Join-Path $appFolder "diagnostics\$stamp"
New-Item -ItemType Directory -Force -Path $reportFolder | Out-Null
$report = Join-Path $reportFolder 'report.txt'
$stdout = Join-Path $reportFolder 'stdout.txt'
$stderr = Join-Path $reportFolder 'stderr.txt'
$started = Get-Date
@(
    "Started: $($started.ToString('o'))"
    "Executable: $executable"
    "Windows: $([Environment]::OSVersion.VersionString)"
    "64-bit OS: $([Environment]::Is64BitOperatingSystem)"
    "App version: $((Get-Item -LiteralPath $executable).VersionInfo.FileVersion)"
    "Executable SHA256: $((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash)"
) | Set-Content -LiteralPath $report -Encoding UTF8
foreach ($relative in @('flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets\AssetManifest.bin')) {
    $asset = Join-Path $appFolder $relative
    if (Test-Path -LiteralPath $asset) {
        $item = Get-Item -LiteralPath $asset
        "Asset: $relative; bytes=$($item.Length); version=$($item.VersionInfo.FileVersion)" | Add-Content -LiteralPath $report -Encoding UTF8
    } else {
        "MISSING ASSET: $relative" | Add-Content -LiteralPath $report -Encoding UTF8
    }
}

Write-Host 'Откроется касса. Введите PIN только в кассе и повторите сбой.'
Write-Host 'Это окно оставьте открытым. После закрытия кассы будет создан диагностический ZIP.'
$process = Start-Process -FilePath $executable -WorkingDirectory $appFolder -PassThru `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$process.WaitForExit()
$process.Refresh()
"Exited: $((Get-Date).ToString('o')); code=$($process.ExitCode)" | Add-Content -LiteralPath $report -Encoding UTF8

# Allow Windows Error Reporting a short time to publish the crash event.
Start-Sleep -Seconds 3
try {
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001,1002; StartTime=$started.AddSeconds(-5)} -ErrorAction Stop |
        Where-Object { $_.Message -match 'Leemon\.exe' } |
        Select-Object TimeCreated, Id, Message | Format-List | Out-String
    Protect-LogText $events | Set-Content -LiteralPath (Join-Path $reportFolder 'windows-events.txt') -Encoding UTF8
} catch {
    "Windows events: $($_.Exception.Message)" | Add-Content -LiteralPath $report -Encoding UTF8
}
$startupLog = Join-Path $env:TEMP 'leemon_pos_startup.log'
if (Test-Path -LiteralPath $startupLog) {
    $tail = Get-Content -LiteralPath $startupLog -Tail 300 -Encoding UTF8 | Out-String
    Protect-LogText $tail | Set-Content -LiteralPath (Join-Path $reportFolder 'startup.txt') -Encoding UTF8
}
foreach ($log in @($stdout, $stderr)) {
    if (Test-Path -LiteralPath $log) {
        $text = Get-Content -LiteralPath $log -Tail 2000 -Encoding UTF8 | Out-String
        Protect-LogText $text | Set-Content -LiteralPath $log -Encoding UTF8
    }
}
$zip = Join-Path $appFolder "diagnostics\leemon-diagnostic-$stamp.zip"
Compress-Archive -Path (Join-Path $reportFolder '*') -DestinationPath $zip
Write-Host "Диагностика сохранена: $zip"
Write-Host 'Пришлите этот ZIP для разбора причины закрытия.'
Start-Process -FilePath explorer.exe -ArgumentList @('/select,', ('"' + $zip + '"')) -WindowStyle Hidden

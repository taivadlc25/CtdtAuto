[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$Changelog = 'Cập nhật tính năng và tối ưu hệ thống.'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

$versionJsonPath = Join-Path $root 'version.json'
$currentVersion = '2026.11.22.3'
if (Test-Path $versionJsonPath) {
    try {
        $json = Get-Content $versionJsonPath -Raw | ConvertFrom-Json
        if ($json.version) { $currentVersion = [string]$json.version }
    } catch {}
}

if (-not $Version) {
    $parts = $currentVersion.Split('.')
    if ($parts.Length -eq 4) {
        $parts[3] = ([int]$parts[3] + 1).ToString()
        $Version = $parts -join '.'
    } else {
        $Version = (Get-Date -Format 'yyyy.MM.dd') + '.1'
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   BAT DAU BUILD VA PHAT HANH v$Version" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Cap nhat ma nguon CTDT_auto_custom.au3
$au3Path = Join-Path $root 'CTDT_auto_custom.au3'
$content = [System.IO.File]::ReadAllText($au3Path, [System.Text.Encoding]::UTF8)
$content = $content -replace '#pragma compile\(FileVersion, [0-9.]+\)', "#pragma compile(FileVersion, $Version)"
$content = $content -replace '#pragma compile\(ProductVersion, [0-9.]+\)', "#pragma compile(ProductVersion, $Version)"
$content = $content -replace 'Global Const \$UPDATE_VERSION = "[0-9.]+"', "Global Const `$UPDATE_VERSION = `"$Version`""
[System.IO.File]::WriteAllText($au3Path, $content, [System.Text.UTF8Encoding]::new($true))
Write-Host "[1/5] Da cap nhat version trong ma nguon AutoIt." -ForegroundColor Green

# 2. Kiem tra cu phap AutoIt
$autoit = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'AutoIt3'
& (Join-Path $autoit 'Au3Check.exe') $au3Path
if ($LASTEXITCODE -ne 0) { throw 'Loi cu phap AutoIt, vui long kiem tra lai code.' }
Write-Host "[2/5] Kiem tra cu phap AutoIt OK." -ForegroundColor Green

# 3. Bien dich CtdtAuto.exe voi Icon
$iconPath = Join-Path $root 'CtdtAuto.ico'
$exePath = Join-Path $root 'CtdtAuto.exe'
$argsText = "/in `"$au3Path`" /out `"$exePath`" /icon `"$iconPath`" /x64 /comp 1 /gui"
$compiler = Start-Process -FilePath (Join-Path $autoit 'Aut2Exe\Aut2exe_x64.exe') -ArgumentList $argsText -Wait -PassThru -NoNewWindow
if ($compiler.ExitCode -ne 0 -or !(Test-Path $exePath)) { throw 'Bien dich CtdtAuto.exe that bai.' }
Write-Host "[3/5] Da bien dich CtdtAuto.exe thanh cong." -ForegroundColor Green

# 4. Cap nhat version.json
$newJson = [ordered]@{
    version      = $Version
    download_url = "https://github.com/taivadlc25/CtdtAuto/releases/download/v$Version/CtdtAuto.exe"
    changelog    = $Changelog
    required     = $false
}
$newJson | ConvertTo-Json -Depth 4 | Set-Content $versionJsonPath -Encoding UTF8
Write-Host "[4/5] Da cap nhat version.json." -ForegroundColor Green

# 5. Day len GitHub (Git commit + GitHub Release)
Write-Host "[5/5] Dang phat hanh len GitHub Releases..." -ForegroundColor Yellow
git add version.json CTDT_auto_custom.au3
git commit -m "Release v$Version: $Changelog" --allow-empty
git push origin main

& gh release create "v$Version" $exePath --title "CtdtAuto v$Version" --notes "$Changelog"
if ($LASTEXITCODE -ne 0) { throw 'Phat hanh GitHub Release that bai.' }

Write-Host "==========================================" -ForegroundColor Green
Write-Host " PHAT HANH THANH CONG BAN v$Version!" -ForegroundColor Green
Write-Host " Link: https://github.com/taivadlc25/CtdtAuto/releases/tag/v$Version" -ForegroundColor Cyan
Write-Host " Tat ca may nguoi dung se tu dong nhan ban moi khi mo app!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

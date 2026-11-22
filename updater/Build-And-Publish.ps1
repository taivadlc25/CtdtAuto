[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$DriveRemote = $env:CTDT_DRIVE_REMOTE,
    [string]$ManifestId = $env:CTDT_DRIVE_MANIFEST_ID,
    [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$autoit = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'AutoIt3'
$folderId = '1FWAshoHwxR2NqkBdrQBvFqKYH6W2wC7k'
$publishConfigPath = Join-Path $PSScriptRoot 'publish-config.json'
if ([IO.File]::Exists($publishConfigPath)) {
    $savedConfig = [IO.File]::ReadAllText($publishConfigPath) | ConvertFrom-Json
    if (-not $DriveRemote) { $DriveRemote = [string]$savedConfig.driveRemote }
    if (-not $ManifestId) { $ManifestId = [string]$savedConfig.manifestId }
}
$releaseName = "CtdtAuto_$Version.exe"
if (-not $BuildOnly) {
    if ($DriveRemote -notmatch '^[a-zA-Z0-9_.-]+:$' -or $ManifestId -notmatch '^[A-Za-z0-9_-]{10,200}$') {
        throw 'Set CTDT_DRIVE_REMOTE to a configured rclone Google Drive remote and CTDT_DRIVE_MANIFEST_ID to the ID of latest.txt.'
    }
    $rcloneCommand = Get-Command rclone -CommandType Application -ErrorAction SilentlyContinue
    if ($rcloneCommand) { $rclone = $rcloneCommand.Source }
    else {
        $rclone = Join-Path $env:LOCALAPPDATA 'Programs\rclone\rclone.exe'
        if (-not [IO.File]::Exists($rclone)) { throw 'Install rclone and configure the ctdt Google Drive remote.' }
    }
}
function Invoke-Drive {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Options)
    $result = & $rclone @Options --drive-root-folder-id $folderId
    if ($LASTEXITCODE) { throw "Google Drive command failed with exit code $LASTEXITCODE." }
    $result
}
function Get-PublicFile($id, $path) {
    if ($id -notmatch '^[A-Za-z0-9_-]{10,200}$') { throw 'Invalid remote file ID.' }
    $url = 'https://drive.usercontent.google.com/download?id=' + $id + '&export=download&confirm=t'
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $url -OutFile $path
}
if (-not $Version) {
    if ($BuildOnly -or $ManifestId -notmatch '^[A-Za-z0-9_-]{10,200}$') {
        throw 'Provide -Version for build-only mode, or configure the public Drive manifest for auto-versioning.'
    }
    $probe = Join-Path ([IO.Path]::GetTempPath()) ('CTDT-current-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        Get-PublicFile $ManifestId $probe
        $currentText = [IO.File]::ReadAllText($probe)
        if ($currentText -notmatch '(?m)^version=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*$') {
            throw 'The current Drive manifest has no valid version for automatic versioning.'
        }
        $currentVersion = [version]$Matches[1]
        if ($currentVersion.Revision -ge 65534) { throw 'The release revision reached its maximum.' }
        $Version = '{0}.{1}.{2}.{3}' -f $currentVersion.Major, $currentVersion.Minor, $currentVersion.Build, ($currentVersion.Revision + 1)
    } finally {
        if ([IO.File]::Exists($probe)) { [IO.File]::Delete($probe) }
    }
}
if ($Version -notmatch '^[0-9]{1,5}(\.[0-9]{1,5}){3}$') { throw 'Version must contain four numeric parts, for example 2026.11.22.3.' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('CTDT-build-' + [Guid]::NewGuid().ToString('N'))
$helperDir = Join-Path $stage 'updater'
[void][IO.Directory]::CreateDirectory($helperDir)
try {
    $source = [IO.File]::ReadAllText((Join-Path $root 'CTDT_auto_custom.au3'))
    $source = $source -replace '#pragma compile\(FileVersion, [0-9.]+\)', "#pragma compile(FileVersion, $Version)"
    $source = $source -replace '#pragma compile\(ProductVersion, [0-9.]+\)', "#pragma compile(ProductVersion, $Version)"
    $source = $source -replace '\$UPDATE_VERSION = "[0-9.]+"', ('$UPDATE_VERSION = "' + $Version + '"')
    if ($ManifestId -match '^[A-Za-z0-9_-]{10,200}$') {
        $source = $source -replace '\$UPDATE_FEED_ID = "[^"]*"', ('$UPDATE_FEED_ID = "' + $ManifestId + '"')
    }
    $stagedSource = Join-Path $stage 'CTDT_auto_custom.au3'
    [IO.File]::WriteAllText($stagedSource, $source, [Text.UTF8Encoding]::new($true))
    $icon = Join-Path $root 'CtdtAuto.ico'
    if ([IO.File]::Exists($icon)) {
        Copy-Item -LiteralPath $icon -Destination (Join-Path $stage 'CtdtAuto.ico') -Force
    }
    $csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $helper = Join-Path $helperDir 'CTDT.Update.exe'
    $resource = '/resource:' + (Join-Path $PSScriptRoot 'release-public.xml') + ',CTDT.ReleaseKey'
    & $csc /nologo /target:winexe /optimize+ /codepage:65001 "/out:$helper" $resource (Join-Path $PSScriptRoot 'DriveUpdater.cs')
    if ($LASTEXITCODE) { throw 'Updater compilation failed.' }
    & (Join-Path $autoit 'Au3Check.exe') $stagedSource
    if ($LASTEXITCODE) { throw 'AutoIt syntax check failed.' }
    $exe = Join-Path $stage $releaseName
    $argsText = '/in "' + $stagedSource + '" /out "' + $exe + '" /icon "' + $icon + '" /x64 /comp 1 /console'
    $compiler = Start-Process -FilePath (Join-Path $autoit 'Aut2Exe\Aut2exe_x64.exe') -ArgumentList $argsText -WorkingDirectory $stage -Wait -PassThru -NoNewWindow
    if ($compiler.ExitCode -or ![IO.File]::Exists($exe)) { throw 'CTDT Auto compilation failed.' }
    if ([Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion -ne $Version) { throw 'Compiled EXE version mismatch.' }
    if (-not $BuildOnly) {
        $feedPath = $DriveRemote + 'latest.txt'
        $exePath = $DriveRemote + $Version + '/CtdtAuto.exe'
        $feed = Invoke-Drive lsjson --stat $feedPath | ConvertFrom-Json
        if ($feed.ID -ne $ManifestId) { throw 'latest.txt does not match CTDT_DRIVE_MANIFEST_ID.' }
        $downloaded = Join-Path $stage 'published.txt'
        Get-PublicFile $ManifestId $downloaded
        $previous = [IO.File]::ReadAllText($downloaded)
        if ($previous -notmatch '^CTDT-AUTO-1(?:\r?\n|$)') { throw 'latest.txt is not publicly readable as an update index.' }
        if ($previous -match '(?m)^version=([0-9.]+)\s*$' -and [version]$Version -le [version]$Matches[1]) {
            throw "The release version must be newer than $($Matches[1])."
        }
        Invoke-Drive mkdir ($DriveRemote + $Version) | Out-Null
        Invoke-Drive copyto $exe $exePath --checksum --immutable | Out-Null
        Invoke-Drive link $exePath | Out-Null
        $artifact = Invoke-Drive lsjson --stat $exePath | ConvertFrom-Json
        $verify = Join-Path $stage 'verify.exe'
        Get-PublicFile $artifact.ID $verify
        if ((Get-FileHash $exe).Hash -ne (Get-FileHash $verify).Hash) { throw 'Public download hash differs from the build.' }
        $manifest = Join-Path $stage 'latest.txt'
        & (Join-Path $PSScriptRoot 'New-Release.ps1') -Exe $exe -Version $Version -DriveFileId $artifact.ID -OutFile $manifest
        Invoke-Drive copyto $manifest $feedPath --checksum | Out-Null
        Invoke-Drive link $feedPath | Out-Null
        $feed = Invoke-Drive lsjson --stat $feedPath | ConvertFrom-Json
        if ($feed.ID -ne $ManifestId) { throw 'Google Drive changed the ID of latest.txt.' }
        Get-PublicFile $ManifestId $downloaded
        if ((Get-FileHash $manifest).Hash -ne (Get-FileHash $downloaded).Hash) { throw 'The published release index could not be verified.' }
        Write-Output "Published $Version to Google Drive."
    }
    $output = Join-Path $root ('releases\' + $Version)
    [void][IO.Directory]::CreateDirectory($output)
    $outFile = Join-Path $output 'CtdtAuto.exe'
    Copy-Item -LiteralPath $exe -Destination $outFile -Force
    Copy-Item -LiteralPath $exe -Destination (Join-Path $output 'CTDT_auto_custom.exe') -Force
    Copy-Item -LiteralPath $exe -Destination (Join-Path $root 'CtdtAuto.exe') -Force
    Copy-Item -LiteralPath $exe -Destination (Join-Path $root 'CTDT_auto_custom.exe') -Force
    Write-Output $outFile
} finally {
    Get-ChildItem -LiteralPath $helperDir -File | Remove-Item
    Remove-Item -LiteralPath $helperDir
    Get-ChildItem -LiteralPath $stage -File | Remove-Item
    Remove-Item -LiteralPath $stage
}

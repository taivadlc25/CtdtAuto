[CmdletBinding(DefaultParameterSetName = 'Sign')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Initialize')]
    [switch]$InitializeKey,

    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [string]$Exe,

    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [ValidatePattern('^(0|[1-9][0-9]{0,4})(\.(0|[1-9][0-9]{0,4})){3}$')]
    [string]$Version,

    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [ValidatePattern('^[A-Za-z0-9_-]{10,200}$')]
    [string]$DriveFileId,

    [Parameter(Mandatory, ParameterSetName = 'Sign')]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$publicFile = Join-Path $PSScriptRoot 'release-public.xml'
$parameters = [Security.Cryptography.CspParameters]::new(24, 'Microsoft Enhanced RSA and AES Cryptographic Provider', 'CTDT.Auto.Drive.Release.v1')
$parameters.KeyNumber = [int][Security.Cryptography.KeyNumber]::Signature
$parameters.Flags = [Security.Cryptography.CspProviderFlags]::UseExistingKey -bor [Security.Cryptography.CspProviderFlags]::NoPrompt
$rsa = $null

try {
    try {
        $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new($parameters)
    }
    catch {
        $cause = $_.Exception.GetBaseException()
        if ($cause.HResult.ToString('X8') -ne '80090016') { throw }
        if (-not $InitializeKey -or [IO.File]::Exists($publicFile)) {
            throw 'The signing key is unavailable. Use the Windows account on the original publishing machine.'
        }
        $parameters.Flags = [Security.Cryptography.CspProviderFlags]::UseNonExportableKey -bor [Security.Cryptography.CspProviderFlags]::NoPrompt
        $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(3072, $parameters)
        $rsa.PersistKeyInCsp = $true
    }

    if ($rsa.KeySize -ne 3072 -or $rsa.CspKeyContainerInfo.Exportable) {
        throw 'The existing key does not match the release key requirements.'
    }
    $publicXml = $rsa.ToXmlString($false)
    if ([IO.File]::Exists($publicFile)) {
        if ([IO.File]::ReadAllText($publicFile).Trim() -cne $publicXml) {
            throw 'The signing key does not match the public key pinned by this application.'
        }
    }
    elseif ($InitializeKey) {
        $stream = [IO.File]::Open($publicFile, 'CreateNew', 'Write', 'None')
        try {
            $bytes = $utf8.GetBytes($publicXml)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    }
    else { throw 'Missing release-public.xml. Initialize the publishing account first.' }

    if ($InitializeKey) {
        Write-Output "Public release key ready at $publicFile"
        return
    }

    $binary = (Resolve-Path -LiteralPath $Exe).ProviderPath
    $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    if ($binary -eq $destination -or $publicFile -eq $destination) { throw 'Choose a separate destination for the release manifest.' }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($destination))) { throw 'The manifest directory does not exist.' }
    $stream = [IO.File]::Open($binary, 'Open', 'Read', 'Read')
    try {
        $reader = [IO.BinaryReader]::new($stream, $utf8, $true)
        try {
            if ($stream.Length -lt 128 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid Windows executable.' }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadUInt32()
            if ($peOffset -lt 64 -or $peOffset -gt $stream.Length - 24) { throw 'Invalid PE header offset.' }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x4550) { throw 'Invalid PE executable.' }
        } finally { $reader.Dispose() }

        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary)
        $actualVersion = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
        if ([string]::IsNullOrWhiteSpace($info.FileVersion) -or $actualVersion -cne $Version) {
            throw "Requested version $Version does not match the executable version $actualVersion."
        }
        $stream.Position = 0
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
        $size = $stream.Length.ToString([Globalization.CultureInfo]::InvariantCulture)
    } finally { $stream.Dispose() }

    $message = @('CTDT-AUTO-1', "version=$Version", "file=$DriveFileId", "size=$size", "sha256=$hash", '') -join "`n"
    $signature = $rsa.SignData($utf8.GetBytes($message), [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'))
    $manifest = $message + 'signature=' + [Convert]::ToBase64String($signature) + [char]10
    $temporary = "$destination.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $manifest, $utf8)
        if ([IO.File]::Exists($destination)) { [IO.File]::Replace($temporary, $destination, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $destination) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    Write-Output "Signed version $Version at $destination"
} finally {
    if ($null -ne $rsa) { $rsa.Dispose() }
}

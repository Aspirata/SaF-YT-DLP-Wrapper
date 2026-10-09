[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-AsciiField {
    param(
        [byte[]]$Header,
        [int]$Offset,
        [int]$Length,
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value)
    if ($bytes.Length -gt $Length) {
        throw "Tar header value is too long: $Value"
    }
    [System.Array]::Copy($bytes, 0, $Header, $Offset, $bytes.Length)
}

function Set-OctalField {
    param(
        [byte[]]$Header,
        [int]$Offset,
        [int]$Length,
        [long]$Value
    )

    $digits = [Convert]::ToString($Value, 8)
    if ($digits.Length -gt ($Length - 1)) {
        throw "Tar numeric value does not fit in its header field: $Value"
    }
    Set-AsciiField -Header $Header -Offset $Offset -Length $Length -Value ($digits.PadLeft($Length - 1, '0') + "`0")
}

function New-TarHeader {
    param(
        [string]$Name,
        [int]$Mode,
        [long]$Size,
        [long]$ModifiedTime
    )

    [byte[]]$header = New-Object byte[] 512
    Set-AsciiField -Header $header -Offset 0 -Length 100 -Value $Name
    Set-OctalField -Header $header -Offset 100 -Length 8 -Value $Mode
    Set-OctalField -Header $header -Offset 108 -Length 8 -Value 0
    Set-OctalField -Header $header -Offset 116 -Length 8 -Value 0
    Set-OctalField -Header $header -Offset 124 -Length 12 -Value $Size
    Set-OctalField -Header $header -Offset 136 -Length 12 -Value $ModifiedTime

    for ($index = 148; $index -lt 156; $index++) {
        $header[$index] = 32
    }

    $header[156] = [byte][char]'0'
    Set-AsciiField -Header $header -Offset 257 -Length 6 -Value "ustar`0"
    Set-AsciiField -Header $header -Offset 263 -Length 2 -Value '00'
    Set-AsciiField -Header $header -Offset 265 -Length 32 -Value 'root'
    Set-AsciiField -Header $header -Offset 297 -Length 32 -Value 'root'
    Set-OctalField -Header $header -Offset 329 -Length 8 -Value 0
    Set-OctalField -Header $header -Offset 337 -Length 8 -Value 0

    [long]$checksum = 0
    foreach ($value in $header) {
        $checksum += $value
    }
    $checksumDigits = [Convert]::ToString($checksum, 8).PadLeft(6, '0')
    Set-AsciiField -Header $header -Offset 148 -Length 8 -Value ($checksumDigits + "`0 ")
    return $header
}

$sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory)
$archivePath = [System.IO.Path]::GetFullPath($OutputPath)
$epoch = [DateTime]::SpecifyKind([datetime]'1970-01-01', [DateTimeKind]::Utc)
$entries = @(
    @{ Name = 'SaF-YTDLP.sh'; Mode = 493 }
    @{ Name = 'config.ini'; Mode = 420 }
    @{ Name = 'README.md'; Mode = 420 }
    @{ Name = 'LICENSE'; Mode = 420 }
)

foreach ($entry in $entries) {
    $entry.Path = Join-Path $sourceRoot $entry.Name
    if (-not (Test-Path -LiteralPath $entry.Path -PathType Leaf)) {
        throw "Required Unix release file is missing: $($entry.Name)"
    }
}

$outputStream = [System.IO.File]::Open($archivePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try {
    $gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [System.IO.Compression.CompressionMode]::Compress, $true)
    try {
        foreach ($entry in $entries) {
            $file = Get-Item -LiteralPath $entry.Path
            [long]$modifiedTime = [Math]::Floor(($file.LastWriteTimeUtc - $epoch).TotalSeconds)
            [byte[]]$header = New-TarHeader -Name $entry.Name -Mode $entry.Mode -Size $file.Length -ModifiedTime $modifiedTime
            $gzipStream.Write($header, 0, $header.Length)

            $inputStream = [System.IO.File]::OpenRead($entry.Path)
            try {
                $inputStream.CopyTo($gzipStream)
            }
            finally {
                $inputStream.Dispose()
            }

            $paddingLength = [int]((512 - ($file.Length % 512)) % 512)
            if ($paddingLength -gt 0) {
                [byte[]]$padding = New-Object byte[] $paddingLength
                $gzipStream.Write($padding, 0, $padding.Length)
            }
        }

        [byte[]]$endBlocks = New-Object byte[] 1024
        $gzipStream.Write($endBlocks, 0, $endBlocks.Length)
    }
    finally {
        $gzipStream.Dispose()
    }
}
finally {
    $outputStream.Dispose()
}

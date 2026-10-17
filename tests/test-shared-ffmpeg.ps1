$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-WindowsDependencyMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )

    $commandLine = 'call "{0}" --internal-dependency-map {1}' -f $windowsLauncher, $Architecture
    $output = @(& $env:ComSpec /d /c $commandLine)
    Assert-True ($LASTEXITCODE -eq 0) "Windows dependency map failed for $Architecture."
    return $output -join "`n"
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$windowsLauncher = Join-Path $repositoryRoot 'SaF-YTDLP.cmd'

$windowsX64 = Get-WindowsDependencyMap -Architecture 'AMD64'
$windowsArm64 = Get-WindowsDependencyMap -Architecture 'ARM64'

if ($env:SAF_EXPECTED_ARCH) {
    $commandLine = 'call "{0}" --internal-dependency-map' -f $windowsLauncher
    $nativeMap = @(& $env:ComSpec /d /c $commandLine) -join "`n"
    Assert-True ($LASTEXITCODE -eq 0) 'Windows native dependency map failed.'
    Assert-True ($nativeMap -match "(?m)^PLATFORM=windows-$($env:SAF_EXPECTED_ARCH)$") 'Windows native dependency map selected the wrong runner architecture.'
}

Assert-True (
    $windowsX64 -match [regex]::Escape('FFMPEG_URL=https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip')
) 'Windows x64 does not select the yt-dlp GPL Shared FFmpeg package.'
Assert-True (
    $windowsArm64 -match [regex]::Escape('FFMPEG_URL=https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-winarm64-gpl-shared.zip')
) 'Windows ARM64 does not select the yt-dlp GPL Shared FFmpeg package.'
Assert-True ($windowsX64 -match 'FFMPEG_PATH=.*\\ffmpeg-shared\\bin\\ffmpeg\.exe') 'Windows x64 does not run FFmpeg from the Shared runtime directory.'
Assert-True ($windowsArm64 -match 'FFMPEG_PATH=.*\\ffmpeg-shared\\bin\\ffmpeg\.exe') 'Windows ARM64 does not run FFmpeg from the Shared runtime directory.'

Write-Host 'PASS: every supported Windows architecture selects GPL Shared FFmpeg.'

$ErrorActionPreference = 'Stop'

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

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$buildScript = Join-Path $repositoryRoot 'build-release.cmd'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('saf-release-test-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'source with spaces'
$outputRoot = Join-Path $testRoot 'release output'
$windowsExtract = Join-Path $testRoot 'windows extract'
$unixExtract = Join-Path $testRoot 'unix extract'
$previousPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
$previousProgramFiles = [Environment]::GetEnvironmentVariable('ProgramFiles', 'Process')
$previousProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Process')
$previousGnuTar = [Environment]::GetEnvironmentVariable('SAF_GNU_TAR', 'Process')

try {
    New-Item -ItemType Directory -Path $fixtureRoot, $outputRoot, $windowsExtract, $unixExtract | Out-Null
    $emptyTools = Join-Path $testRoot 'empty tools'
    New-Item -ItemType Directory -Path $emptyTools | Out-Null

    foreach ($name in @('README.md', 'LICENSE', 'SaF-YTDLP.cmd', 'SaF-YTDLP.sh')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $name) -Destination (Join-Path $fixtureRoot $name)
    }

    $personalConfig = "PROFILE=QUALITY`nCOOKIE_BROWSER=firefox`n"
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'config.ini') -Value $personalConfig -NoNewline -Encoding ascii

    $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
    $env:ProgramFiles = $emptyTools
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $emptyTools, 'Process')
    $env:SAF_GNU_TAR = Join-Path $testRoot 'missing-gnu-tar.exe'
    $commandLine = '"{0}" "{1}" "{2}"' -f $buildScript, $fixtureRoot, $outputRoot
    & $env:ComSpec /d /c $commandLine
    $buildExitCode = $LASTEXITCODE

    Assert-True ($buildExitCode -eq 0) "Release build failed without Git or GNU tar (exit code $buildExitCode)."

    $windowsArchive = Join-Path $outputRoot 'SaF-yt-dlp-Wrapper-Windows.zip'
    $unixArchive = Join-Path $outputRoot 'SaF-yt-dlp-Wrapper-Unix.tar.gz'
    Assert-True (Test-Path -LiteralPath $windowsArchive) 'The Windows release archive was not created.'
    Assert-True (Test-Path -LiteralPath $unixArchive) 'The Unix release archive was not created.'

    $expectedWindowsEntries = 'config.ini|LICENSE|README.md|SaF-YTDLP.cmd'
    $expectedUnixEntries = 'config.ini|LICENSE|README.md|SaF-YTDLP.sh'
    $windowsEntries = @(& "$env:SystemRoot\System32\tar.exe" -tf $windowsArchive | ForEach-Object { ($_ -replace '\\', '/') -replace '^\./', '' } | Sort-Object) -join '|'
    $unixEntries = @(& "$env:SystemRoot\System32\tar.exe" -tf $unixArchive | ForEach-Object { ($_ -replace '\\', '/') -replace '^\./', '' } | Sort-Object) -join '|'
    Assert-True ($windowsEntries -eq $expectedWindowsEntries) "Unexpected Windows archive entries: $windowsEntries"
    Assert-True ($unixEntries -eq $expectedUnixEntries) "Unexpected Unix archive entries: $unixEntries"

    $unixListing = @(& "$env:SystemRoot\System32\tar.exe" -tvf $unixArchive)
    $launcherListing = @($unixListing | Where-Object { $_ -match 'SaF-YTDLP\.sh$' })
    Assert-True ($launcherListing.Count -eq 1) 'The Unix launcher was missing or duplicated in the archive listing.'
    Assert-True ($launcherListing[0] -match '^-rwxr-xr-x\s') "The Unix launcher mode was not 755: $($launcherListing[0])"

    & "$env:SystemRoot\System32\tar.exe" -xf $windowsArchive -C $windowsExtract
    Assert-True ($LASTEXITCODE -eq 0) 'The Windows release archive could not be extracted.'
    & "$env:SystemRoot\System32\tar.exe" -xf $unixArchive -C $unixExtract
    Assert-True ($LASTEXITCODE -eq 0) 'The Unix release archive could not be extracted.'

    $sourceLauncherHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fixtureRoot 'SaF-YTDLP.sh')).Hash
    $archivedLauncherHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $unixExtract 'SaF-YTDLP.sh')).Hash
    Assert-True ($archivedLauncherHash -eq $sourceLauncherHash) 'The Unix launcher content or LF line endings changed while it was archived.'

    $expectedReleaseConfig = @(
        'PROFILE=MODERN'
        'MAX_HEIGHT=1080'
        'DEFAULT_MODE=video'
        'TRANSCODE_VP9_TO_AV1=YES'
        'ALLOW_HARDWARE_TRANSCODING=YES'
        'STORE_OPUS_IN_MP4=YES'
        'DOWNLOAD_ALL_AUDIO_TRACKS=YES'
        'COOKIE_BROWSER='
    ) -join "`n"

    $windowsConfig = (Get-Content -Raw -LiteralPath (Join-Path $windowsExtract 'config.ini')) -replace "`r`n", "`n"
    $unixConfig = (Get-Content -Raw -LiteralPath (Join-Path $unixExtract 'config.ini')) -replace "`r`n", "`n"
    Assert-True ($windowsConfig.TrimEnd("`r", "`n") -eq $expectedReleaseConfig) 'The Windows archive contains the wrong release configuration.'
    Assert-True ($unixConfig.TrimEnd("`r", "`n") -eq $expectedReleaseConfig) 'The Unix archive contains the wrong release configuration.'

    $fixtureConfig = (Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'config.ini')) -replace "`r`n", "`n"
    Assert-True ($fixtureConfig -eq $personalConfig) 'The release build changed the working configuration.'

    Write-Host 'PASS: release build works without Git or GNU tar and preserves Unix mode 755.'
}
finally {
    [Environment]::SetEnvironmentVariable('Path', $previousPath, 'Process')
    [Environment]::SetEnvironmentVariable('ProgramFiles', $previousProgramFiles, 'Process')
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $previousProgramFilesX86, 'Process')

    if ($null -eq $previousGnuTar) {
        Remove-Item Env:SAF_GNU_TAR -ErrorAction SilentlyContinue
    }
    else {
        $env:SAF_GNU_TAR = $previousGnuTar
    }

    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

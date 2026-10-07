$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $repositoryRoot

$actualArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$expectedArchitecture = $env:SAF_EXPECTED_ARCH.ToLowerInvariant()
if ($actualArchitecture -ne $expectedArchitecture) {
    throw "Expected $expectedArchitecture runner, but Windows reports $actualArchitecture."
}

Write-Host "Runner architecture: $actualArchitecture"
$inputFile = Join-Path $env:RUNNER_TEMP 'saf-live-download-input.txt'
$env:SAF_CI_INPUT = $inputFile
try {
    [System.IO.File]::WriteAllText(
        $inputFile,
        "$env:SAF_SMOKE_URL`r`n`r`n`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    & cmd.exe /d /c 'call SaF-YTDLP.cmd < "%SAF_CI_INPUT%"'
    $launcherExitCode = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $inputFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:SAF_CI_INPUT -ErrorAction SilentlyContinue
}
if ($launcherExitCode -ne 0) {
    throw "SaF-YTDLP.cmd exited with code $launcherExitCode."
}

$mediaFiles = @(Get-ChildItem -LiteralPath 'Downloads' -File -Recurse)
if ($mediaFiles.Count -ne 1) {
    throw "Expected exactly one downloaded media file, found $($mediaFiles.Count)."
}

$mediaFile = $mediaFiles[0]
if ($mediaFile.Length -le 0) {
    throw "Downloaded file is empty: $($mediaFile.FullName)"
}

$temporaryItems = @(Get-ChildItem -LiteralPath 'internal\temp' -Force -ErrorAction SilentlyContinue)
if ($temporaryItems.Count -ne 0) {
    throw "Temporary data remains after the download: $($temporaryItems.FullName -join ', ')"
}

$ffprobe = Join-Path $repositoryRoot 'internal\dependencies\ffprobe.exe'
if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) {
    throw 'The wrapper did not install ffprobe.exe.'
}

$probeArguments = @(
    '-v', 'error',
    '-show_entries', 'format=filename,format_name,format_long_name,duration,size,bit_rate:format_tags=title,artist',
    '-show_entries', 'stream=index,codec_type,codec_name,codec_long_name,profile,width,height,pix_fmt,r_frame_rate,avg_frame_rate,bit_rate,sample_rate,channels,channel_layout:stream_tags=language,title,handler_name',
    '-of', 'default=noprint_wrappers=0',
    $mediaFile.FullName
)
$mediaReport = (& $ffprobe @probeArguments 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe could not inspect $($mediaFile.FullName)."
}

$sizeMiB = [Math]::Round($mediaFile.Length / 1MB, 2)
Write-Host "Downloaded file: $($mediaFile.FullName) ($sizeMiB MiB)"
Write-Host 'Media report:'
Write-Host $mediaReport

if ($env:GITHUB_STEP_SUMMARY) {
    $summary = @(
        "## Downloaded video - $env:SAF_EXPECTED_ARCH",
        '',
        "- File: ``$($mediaFile.Name)``",
        "- Size: $sizeMiB MiB",
        '',
        '```text',
        $mediaReport,
        '```',
        ''
    ) -join [Environment]::NewLine
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding utf8
}

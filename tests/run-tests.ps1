$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SaF-YTDLP.cmd'
$script:passed = 0
$script:failed = 0
$fixtureRoot = Join-Path $env:TEMP ("saf-ytdlp-fixture-" + [guid]::NewGuid().ToString('N'))
$fakeYtdlpFixture = Join-Path $fixtureRoot 'yt-dlp.exe'
$fakeFfmpegFixture = Join-Path $fixtureRoot 'ffmpeg.exe'
$fakeGnuTarFixture = Join-Path $fixtureRoot 'gnu-tar.exe'
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

$script:testConfigDefaults = @'
PROFILE=MODERN
MAX_HEIGHT=1080
DEFAULT_MODE=video
TRANSCODE_VP9_TO_AV1=YES
ALLOW_HARDWARE_TRANSCODING=NO
STORE_OPUS_IN_MP4=NO
DOWNLOAD_ALL_AUDIO_TRACKS=NO
COOKIE_BROWSER=
'@

$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "C# compiler not found at $compiler"
}
& $compiler /nologo /target:exe /out:$fakeYtdlpFixture (Join-Path $PSScriptRoot 'FakeYtdlp.cs')
if ($LASTEXITCODE -ne 0) {
    throw 'Could not build the yt-dlp test fixture.'
}
& $compiler /nologo /target:exe /out:$fakeFfmpegFixture (Join-Path $PSScriptRoot 'FakeFfmpeg.cs')
if ($LASTEXITCODE -ne 0) {
    throw 'Could not build the FFmpeg test fixture.'
}
& $compiler /nologo /target:exe /out:$fakeGnuTarFixture (Join-Path $PSScriptRoot 'FakeGnuTar.cs')
if ($LASTEXITCODE -ne 0) {
    throw 'Could not build the GNU tar test fixture.'
}
function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Scenario {
    param(
        [string]$Config,
        [string[]]$InputLines,
        [int]$UpdateExitCode = 0,
        [int]$DownloadExitCode = 0,
        [string]$VideoCodec,
        [string]$AudioCodec = 'opus',
        [string]$ActualAudioCodec,
        [string]$ActualAudioCodecs,
        [string]$HardwareEncoders,
        [string]$FailEncoder,
        [int]$FailEncoderExit = 1,
        [string]$PixelFormat = 'yuv420p',
        [string]$MediaName = 'sample.webm',
        [string]$SecondMediaName,
        [string]$SecondVideoCodec,
        [string]$FailInputContains,
        [string]$VideoBitrate = '8000000',
        [int]$VideoHeight = 1080,
        [string]$VideoDuration = '10',
        [string]$VideoPacketSizes = '5000000,5000000',
        [int]$InitialCodePage = 0,
        [string]$CookieSuccess,
        [string]$DownloadFailCookie,
        [string]$DownloadFailCookieItem,
        [string]$ModernFormatsJson,
        [switch]$ObsoleteCookieBridge,
        [ValidateSet('Network', 'Direct', 'Multiple')]
        [string]$CometFixture = 'Network'
    )

    $caseRoot = Join-Path $env:TEMP ("saf-ytdlp-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $dependencyDirectory = Join-Path $caseRoot 'internal\dependencies'
    $tempDirectory = Join-Path $caseRoot 'internal\temp'
    New-Item -ItemType Directory -Path $dependencyDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

    try {
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $caseRoot 'SaF-YTDLP.cmd')
        $configValues = [ordered]@{}
        foreach ($line in (($script:testConfigDefaults.TrimEnd() + "`n" + $Config.Trim()) -split "`r?`n")) {
            if ($line -match '^\s*([^#;=\s]+)\s*=(.*)$') {
                $configValues[$matches[1]] = $matches[2].Trim()
            }
        }
        $fixtureConfig = (($configValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`r`n") + "`r`n"
        Set-Content -LiteralPath (Join-Path $caseRoot 'config.ini') -Value $fixtureConfig -Encoding ascii

        $fakeYtdlp = Join-Path $dependencyDirectory 'yt-dlp.exe'
        $fakeDeno = Join-Path $dependencyDirectory 'deno.exe'
        $fakeFfmpeg = Join-Path $dependencyDirectory 'ffmpeg.exe'
        $fakeFfprobe = Join-Path $dependencyDirectory 'ffprobe.exe'
        $argumentLog = Join-Path $caseRoot 'arguments.log'
        $inputFile = Join-Path $caseRoot 'input.txt'

        Copy-Item -LiteralPath $fakeYtdlpFixture -Destination $fakeYtdlp
        $ytdlpHashBefore = (Get-FileHash -LiteralPath $fakeYtdlp -Algorithm SHA256).Hash
        New-Item -ItemType File -Path $fakeDeno | Out-Null
        Copy-Item -LiteralPath $fakeFfmpegFixture -Destination $fakeFfmpeg
        Copy-Item -LiteralPath $fakeFfmpegFixture -Destination $fakeFfprobe

        $ffmpegLog = Join-Path $caseRoot 'ffmpeg.log'
        $mediaPath = Join-Path (Join-Path $caseRoot 'Downloads') $MediaName
        $secondMediaPath = if ($SecondMediaName) { Join-Path (Join-Path $caseRoot 'Downloads') $SecondMediaName } else { $null }

        $oldEnvironment = @{
            SAF_ARGUMENT_LOG = $env:SAF_ARGUMENT_LOG
            SAF_FAKE_UPDATE_EXIT = $env:SAF_FAKE_UPDATE_EXIT
            SAF_FAKE_VERSION_EXIT = $env:SAF_FAKE_VERSION_EXIT
            SAF_TEST_DOWNLOAD_FAILURE = $env:SAF_TEST_DOWNLOAD_FAILURE
            SAF_FAKE_DOWNLOAD_EXIT = $env:SAF_FAKE_DOWNLOAD_EXIT
            SAF_FAKE_MEDIA_PATH = $env:SAF_FAKE_MEDIA_PATH
            SAF_FAKE_MEDIA_NAME = $env:SAF_FAKE_MEDIA_NAME
            SAF_FAKE_VIDEO_CODEC = $env:SAF_FAKE_VIDEO_CODEC
            SAF_FAKE_AUDIO_CODEC = $env:SAF_FAKE_AUDIO_CODEC
            SAF_FAKE_ACTUAL_AUDIO_CODEC = $env:SAF_FAKE_ACTUAL_AUDIO_CODEC
            SAF_FAKE_ACTUAL_AUDIO_CODECS = $env:SAF_FAKE_ACTUAL_AUDIO_CODECS
            SAF_FAKE_HARDWARE_ENCODERS = $env:SAF_FAKE_HARDWARE_ENCODERS
            SAF_FAKE_FAIL_ENCODER = $env:SAF_FAKE_FAIL_ENCODER
            SAF_FAKE_FAIL_EXIT = $env:SAF_FAKE_FAIL_EXIT
            SAF_FFMPEG_LOG = $env:SAF_FFMPEG_LOG
            SAF_FAKE_PIX_FMT = $env:SAF_FAKE_PIX_FMT
            SAF_FAKE_SECOND_MEDIA_PATH = $env:SAF_FAKE_SECOND_MEDIA_PATH
            SAF_FAKE_SECOND_MEDIA_NAME = $env:SAF_FAKE_SECOND_MEDIA_NAME
            SAF_FAKE_SECOND_VIDEO_CODEC = $env:SAF_FAKE_SECOND_VIDEO_CODEC
            SAF_FAKE_FAIL_INPUT_CONTAINS = $env:SAF_FAKE_FAIL_INPUT_CONTAINS
            SAF_FAKE_VIDEO_BITRATE = $env:SAF_FAKE_VIDEO_BITRATE
            SAF_FAKE_VIDEO_HEIGHT = $env:SAF_FAKE_VIDEO_HEIGHT
            SAF_FAKE_DURATION = $env:SAF_FAKE_DURATION
            SAF_FAKE_PACKET_SIZES = $env:SAF_FAKE_PACKET_SIZES
            SAF_FAKE_COOKIE_SUCCESS = $env:SAF_FAKE_COOKIE_SUCCESS
            SAF_FAKE_DOWNLOAD_FAIL_COOKIE = $env:SAF_FAKE_DOWNLOAD_FAIL_COOKIE
            SAF_FAKE_DOWNLOAD_FAIL_COOKIE_ITEM = $env:SAF_FAKE_DOWNLOAD_FAIL_COOKIE_ITEM
            SAF_FAKE_METADATA_JSON = $env:SAF_FAKE_METADATA_JSON
            APPDATA = $env:APPDATA
            LOCALAPPDATA = $env:LOCALAPPDATA
        }

        $env:SAF_ARGUMENT_LOG = $argumentLog
        $env:SAF_FAKE_UPDATE_EXIT = [string]$UpdateExitCode
        $env:SAF_FAKE_VERSION_EXIT = '0'
        $env:SAF_TEST_DOWNLOAD_FAILURE = $null
        $env:SAF_FAKE_DOWNLOAD_EXIT = [string]$DownloadExitCode
        $env:SAF_FAKE_MEDIA_PATH = $null
        $env:SAF_FAKE_MEDIA_NAME = if ($VideoCodec) { $MediaName } else { $null }
        $env:SAF_FAKE_VIDEO_CODEC = $VideoCodec
        $env:SAF_FAKE_AUDIO_CODEC = $AudioCodec
        $env:SAF_FAKE_ACTUAL_AUDIO_CODEC = if ($ActualAudioCodec) { $ActualAudioCodec } else { $AudioCodec }
        $env:SAF_FAKE_ACTUAL_AUDIO_CODECS = $ActualAudioCodecs
        $env:SAF_FAKE_HARDWARE_ENCODERS = $HardwareEncoders
        $env:SAF_FAKE_FAIL_ENCODER = $FailEncoder
        $env:SAF_FAKE_FAIL_EXIT = [string]$FailEncoderExit
        $env:SAF_FFMPEG_LOG = $ffmpegLog
        $env:SAF_FAKE_PIX_FMT = $PixelFormat
        $env:SAF_FAKE_SECOND_MEDIA_PATH = $null
        $env:SAF_FAKE_SECOND_MEDIA_NAME = if ($SecondMediaName) { $SecondMediaName } else { $null }
        $env:SAF_FAKE_SECOND_VIDEO_CODEC = $SecondVideoCodec
        $env:SAF_FAKE_FAIL_INPUT_CONTAINS = $FailInputContains
        $env:SAF_FAKE_VIDEO_BITRATE = [string]$VideoBitrate
        $env:SAF_FAKE_VIDEO_HEIGHT = [string]$VideoHeight
        $env:SAF_FAKE_DURATION = $VideoDuration
        $env:SAF_FAKE_PACKET_SIZES = $VideoPacketSizes
        $env:SAF_FAKE_COOKIE_SUCCESS = $CookieSuccess
        $env:SAF_FAKE_DOWNLOAD_FAIL_COOKIE = $DownloadFailCookie
        $env:SAF_FAKE_DOWNLOAD_FAIL_COOKIE_ITEM = $DownloadFailCookieItem
        if (-not $ModernFormatsJson) {
            $defaultCodec = if ($VideoCodec) { $VideoCodec } else { 'vp9' }
            $ModernFormatsJson = @{
                id = 'test-video'
                formats = @(
                    @{
                        format_id = 'v1'
                        vcodec = $defaultCodec
                        acodec = 'none'
                        width = 1920
                        height = $VideoHeight
                        fps = 30
                        tbr = 8000
                    }
                )
            } | ConvertTo-Json -Depth 5 -Compress
        }
        $env:SAF_FAKE_METADATA_JSON = $ModernFormatsJson
        if ($ObsoleteCookieBridge) {
            $bridgeDirectory = Join-Path $caseRoot '.tools\cookie-bridge'
            New-Item -ItemType Directory -Path $bridgeDirectory -Force | Out-Null
            Copy-Item -LiteralPath $fakeYtdlpFixture -Destination (Join-Path $bridgeDirectory 'SaFCookieBridge.exe') -Force
        }
        $env:APPDATA = Join-Path $caseRoot 'AppData\Roaming'
        $env:LOCALAPPDATA = Join-Path $caseRoot 'AppData\Local'
        New-Item -ItemType Directory -Path (Join-Path $env:APPDATA 'zen\Profiles') -Force | Out-Null
        $cometUserData = Join-Path $env:LOCALAPPDATA 'Perplexity\Comet\User Data'
        if ($CometFixture -eq 'Direct') {
            $cometCookieDatabase = Join-Path $cometUserData 'Default\Cookies'
            New-Item -ItemType Directory -Path (Split-Path $cometCookieDatabase -Parent) -Force | Out-Null
            New-Item -ItemType File -Path $cometCookieDatabase -Force | Out-Null
        } elseif ($CometFixture -eq 'Multiple') {
            $olderCookieDatabase = Join-Path $cometUserData 'Default\Cookies'
            $newerCookieDatabase = Join-Path $cometUserData 'Profile 2\Network\Cookies'
            $nestedDecoyDatabase = Join-Path $cometUserData 'Component Data\Default\Network\Cookies'
            New-Item -ItemType Directory -Path (Split-Path $olderCookieDatabase -Parent) -Force | Out-Null
            New-Item -ItemType File -Path $olderCookieDatabase -Force | Out-Null
            (Get-Item -LiteralPath $olderCookieDatabase).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-5)
            New-Item -ItemType Directory -Path (Split-Path $newerCookieDatabase -Parent) -Force | Out-Null
            New-Item -ItemType File -Path $newerCookieDatabase -Force | Out-Null
            (Get-Item -LiteralPath $newerCookieDatabase).LastWriteTimeUtc = [datetime]::UtcNow
            New-Item -ItemType Directory -Path (Split-Path $nestedDecoyDatabase -Parent) -Force | Out-Null
            New-Item -ItemType File -Path $nestedDecoyDatabase -Force | Out-Null
            (Get-Item -LiteralPath $nestedDecoyDatabase).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(5)
        } else {
            $cometCookieDatabase = Join-Path $cometUserData 'Default\Network\Cookies'
            New-Item -ItemType Directory -Path (Split-Path $cometCookieDatabase -Parent) -Force | Out-Null
            New-Item -ItemType File -Path $cometCookieDatabase -Force | Out-Null
        }
        Set-Content -LiteralPath $inputFile -Value $InputLines -Encoding ascii
        if ($InitialCodePage -gt 0) {
            $launcher = Join-Path $caseRoot 'launch-test.cmd'
            $launcherLines = @(
                '@echo off',
                "chcp $InitialCodePage >nul",
                ('call "{0}" < "{1}"' -f (Join-Path $caseRoot 'SaF-YTDLP.cmd'), $inputFile)
            )
            Set-Content -LiteralPath $launcher -Value $launcherLines -Encoding ascii
            $commandLine = '""{0}""' -f $launcher
        } else {
            $commandLine = '""{0}" < "{1}""' -f (Join-Path $caseRoot 'SaF-YTDLP.cmd'), $inputFile
        }
        $output = & cmd.exe /d /c $commandLine 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $arguments = if (Test-Path -LiteralPath $argumentLog) {
            Get-Content -Raw -LiteralPath $argumentLog
        } else {
            ''
        }
        $ffmpegArguments = if (Test-Path -LiteralPath $ffmpegLog) {
            Get-Content -Raw -LiteralPath $ffmpegLog -Encoding UTF8
        } else {
            ''
        }
        $publishedFiles = @{}
        $downloadsPath = Join-Path $caseRoot 'Downloads'
        if (Test-Path -LiteralPath $downloadsPath) {
            Get-ChildItem -LiteralPath $downloadsPath -File -Recurse | ForEach-Object {
                $relativePath = $_.FullName.Substring($downloadsPath.Length).TrimStart('\')
                $publishedFiles[$relativePath] = Get-Content -Raw -LiteralPath $_.FullName
            }
        }
        $savedConfig = Get-Content -Raw -LiteralPath (Join-Path $caseRoot 'config.ini')
        $ytdlpHashAfter = (Get-FileHash -LiteralPath $fakeYtdlp -Algorithm SHA256).Hash
        $ffprobeCalls = ([regex]::Matches($ffmpegArguments, '(?m)^FFPROBE\r?$')).Count
        $internalFiles = @(Get-ChildItem -LiteralPath (Join-Path $caseRoot 'internal') -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
        $tempEntries = @(Get-ChildItem -LiteralPath (Join-Path $caseRoot 'internal\temp') -Force -ErrorAction SilentlyContinue)
        $toolsPath = Join-Path $caseRoot '.tools'
        $obsoleteToolsFiles = @(Get-ChildItem -LiteralPath $toolsPath -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)

        [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
            Arguments = $arguments
            FfmpegArguments = $ffmpegArguments
            FfprobeCalls = $ffprobeCalls
            PublishedFiles = $publishedFiles
            Config = $savedConfig
            Root = $caseRoot
            InternalFiles = $internalFiles
            TempEntries = $tempEntries
            ToolsExists = Test-Path -LiteralPath $toolsPath
            ObsoleteToolsFiles = $obsoleteToolsFiles
            YtdlpHashBefore = $ytdlpHashBefore
            YtdlpHashAfter = $ytdlpHashAfter
            YtdlpNewExists = Test-Path -LiteralPath (Join-Path $dependencyDirectory 'yt-dlp.new.exe')
        }
    } finally {
        if ($oldEnvironment) {
            foreach ($entry in $oldEnvironment.GetEnumerator()) {
                Set-Item -Path ("Env:" + $entry.Key) -Value $entry.Value
            }
        }
        Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    try {
        & $Body
        $script:passed++
        Write-Host "PASS $Name" -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host "FAIL $Name" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-DependencyMap {
    param(
        [string]$Architecture,
        [string]$NativeArchitecture
    )

    $oldArchitecture = $env:PROCESSOR_ARCHITECTURE
    $oldNativeArchitecture = $env:PROCESSOR_ARCHITEW6432
    try {
        $env:PROCESSOR_ARCHITECTURE = $Architecture
        $env:PROCESSOR_ARCHITEW6432 = $NativeArchitecture
        $output = & cmd.exe /d /c ('"{0}" --internal-dependency-map' -f $scriptPath) 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally {
        $env:PROCESSOR_ARCHITECTURE = $oldArchitecture
        $env:PROCESSOR_ARCHITEW6432 = $oldNativeArchitecture
    }
}

function Invoke-InterruptedSetup {
    $caseRoot = Join-Path $env:TEMP ("saf-ytdlp-setup-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $inputFile = Join-Path $caseRoot 'input.txt'
    $oldArchitecture = $env:PROCESSOR_ARCHITECTURE
    $oldNativeArchitecture = $env:PROCESSOR_ARCHITEW6432
    $oldDownloadFailure = $env:SAF_TEST_DOWNLOAD_FAILURE

    try {
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $caseRoot 'SaF-YTDLP.cmd')
        Set-Content -LiteralPath (Join-Path $caseRoot 'config.ini') -Value $script:testConfigDefaults -Encoding ascii
        New-Item -ItemType File -Path $inputFile | Out-Null
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        $env:PROCESSOR_ARCHITEW6432 = $null
        $env:SAF_TEST_DOWNLOAD_FAILURE = 'YES'

        $commandLine = '""{0}" < "{1}""' -f (Join-Path $caseRoot 'SaF-YTDLP.cmd'), $inputFile
        $output = & cmd.exe /d /c $commandLine 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $internalPath = Join-Path $caseRoot 'internal'
        $dependencyFiles = @(Get-ChildItem -LiteralPath (Join-Path $internalPath 'dependencies') -File -Recurse -ErrorAction SilentlyContinue)
        $partialFiles = @(Get-ChildItem -LiteralPath $internalPath -Filter '*.part' -File -Recurse -ErrorAction SilentlyContinue)
        $tempEntries = @(Get-ChildItem -LiteralPath (Join-Path $internalPath 'temp') -Force -ErrorAction SilentlyContinue)

        [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
            DependencyFiles = $dependencyFiles
            PartialFiles = $partialFiles
            TempEntries = $tempEntries
        }
    } finally {
        $env:PROCESSOR_ARCHITECTURE = $oldArchitecture
        $env:PROCESSOR_ARCHITEW6432 = $oldNativeArchitecture
        $env:SAF_TEST_DOWNLOAD_FAILURE = $oldDownloadFailure
        Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Release config contains safe portable defaults and no personal browser' {
    $releaseConfig = Get-Content -Raw -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini')
    foreach ($line in @(
        'PROFILE=MODERN',
        'MAX_HEIGHT=1080',
        'DEFAULT_MODE=video',
        'TRANSCODE_VP9_TO_AV1=YES',
        'ALLOW_HARDWARE_TRANSCODING=YES',
        'STORE_OPUS_IN_MP4=YES',
        'DOWNLOAD_ALL_AUDIO_TRACKS=YES'
    )) {
        Assert-True ($releaseConfig -match ('(?m)^' + [regex]::Escape($line) + '\r?$')) "Missing release default: $line"
    }
    Assert-True ($releaseConfig -match '(?m)^COOKIE_BROWSER=\r?$') 'Release config contains a personal browser selection.'
}

Test-Case 'Windows dependency map supports x64 and ARM64' {
    $x64 = Invoke-DependencyMap -Architecture 'AMD64'
    Assert-True ($x64.ExitCode -eq 0) "x64 dependency map failed: $($x64.Output)"
    Assert-True ($x64.Output -match 'PLATFORM=windows-x64') 'x64 platform id is wrong.'
    Assert-True ($x64.Output -match 'yt-dlp\.exe') 'x64 yt-dlp asset is wrong.'
    Assert-True ($x64.Output -match 'deno-x86_64-pc-windows-msvc\.zip') 'x64 Deno asset is wrong.'
    Assert-True ($x64.Output -match 'ffmpeg-master-latest-win64-gpl\.zip') 'x64 FFmpeg asset is wrong.'

    $arm64 = Invoke-DependencyMap -Architecture 'AMD64' -NativeArchitecture 'ARM64'
    Assert-True ($arm64.ExitCode -eq 0) "ARM64 dependency map failed: $($arm64.Output)"
    Assert-True ($arm64.Output -match 'PLATFORM=windows-arm64') 'ARM64 platform id is wrong.'
    Assert-True ($arm64.Output -match 'yt-dlp_arm64\.exe') 'ARM64 yt-dlp asset is wrong.'
    Assert-True ($arm64.Output -match 'deno-aarch64-pc-windows-msvc\.zip') 'ARM64 Deno asset is wrong.'
    Assert-True ($arm64.Output -match 'ffmpeg-master-latest-winarm64-gpl\.zip') 'ARM64 FFmpeg asset is wrong.'
}

Test-Case 'Unsupported Windows architecture stops before setup' {
    $result = Invoke-DependencyMap -Architecture 'x86'
    Assert-True ($result.ExitCode -ne 0) 'Unsupported x86 architecture was accepted.'
    Assert-True ($result.Output -match 'supports Windows x86_64 and ARM64') "Missing architecture error: $($result.Output)"
}

Test-Case 'Interrupted dependency download leaves no partial installation' {
    $result = Invoke-InterruptedSetup
    Assert-True ($result.ExitCode -ne 0) 'Interrupted setup unexpectedly succeeded.'
    Assert-True ($result.Output -match 'could not download yt-dlp') "Missing interrupted-download error: $($result.Output)"
    Assert-True ($result.DependencyFiles.Count -eq 0) 'Interrupted setup installed a dependency.'
    Assert-True ($result.PartialFiles.Count -eq 0) 'Interrupted setup left a partial download.'
    Assert-True ($result.TempEntries.Count -eq 0) 'Interrupted setup left temporary files.'
}

Test-Case 'Windows dependency staging keeps executable file extensions' {
    $scriptText = Get-Content -Raw -LiteralPath $scriptPath
    foreach ($candidate in @(
        'set "YTDLP_NEW=%DEPENDENCIES%\yt-dlp.new.exe"',
        'set "DENO_NEW=%DEPENDENCIES%\deno.new.exe"',
        'set "FFMPEG_NEW=%DEPENDENCIES%\ffmpeg.new.exe"',
        'set "FFPROBE_NEW=%DEPENDENCIES%\ffprobe.new.exe"'
    )) {
        Assert-True ($scriptText.Contains($candidate)) "Missing executable staging path: $candidate"
    }
    Assert-True (-not $scriptText.Contains('2^>^&1')) 'FFmpeg validation passes CMD escape characters into PowerShell.'
}

Test-Case 'Quality prefers native AV1 over higher bitrate VP9 at equal resolution and frame rate' {
    $formats = @{
        id = 'quality-native-av1'
        formats = @(
            @{ format_id = '625'; vcodec = 'vp09.00.50.08'; acodec = 'none'; height = 2160; fps = 25; tbr = 19117 },
            @{ format_id = '401'; vcodec = 'av01.0.12M.08'; acodec = 'none'; height = 2160; fps = 25; tbr = 9024 },
            @{ format_id = '251'; vcodec = 'none'; acodec = 'opus'; language = 'en'; abr = 128 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES" -InputLines @('https://youtu.be/dQw4w9WgXcQ', '') -VideoCodec 'av01.0.12M.08' -ModernFormatsJson $formats
    Assert-True ($result.Arguments -match 'ARG=\[401\+251\]') "QUALITY selected VP9 instead of ready AV1. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch 'ARG=\[625\+251\]') "QUALITY selected the higher bitrate VP9 source. Arguments: $($result.Arguments)"
}

Test-Case 'Runtime files stay below internal and completed media stays below Downloads' {
    $result = Invoke-Scenario -Config 'PROFILE=QUALITY' -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'space %! & (name).mp4'
    Assert-True (-not $result.ToolsExists) 'The obsolete .tools directory was created.'
    Assert-True ($result.TempEntries.Count -eq 0) 'The completed job left temporary files behind.'
    Assert-True ($result.PublishedFiles.ContainsKey('space %! & (name).mp4')) 'The media filename changed while publishing.'
}

Test-Case 'Failed conversion publishes its source and leaves no permanent queue' {
    $result = Invoke-Scenario -Config 'PROFILE=MODERN' -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -FailInputContains 'failed.webm' -MediaName 'failed.webm'
    Assert-True ($result.PublishedFiles.ContainsKey('failed.webm')) 'The failed source was not preserved in Downloads.'
    $runtimeStateFiles = @($result.InternalFiles) + @($result.ObsoleteToolsFiles)
    Assert-True (-not ($runtimeStateFiles -match 'queue|failed|\.json$')) 'A permanent queue or JSON state file remained.'
}

Test-Case 'Normal post-processing inspects media with one FFprobe call' {
    $result = Invoke-Scenario -Config 'PROFILE=MODERN' -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -VideoBitrate '8000000'
    Assert-True ($result.FfprobeCalls -eq 1) "Expected one normal FFprobe call, got $($result.FfprobeCalls)."
}

Test-Case 'Missing bitrate uses exactly one packet fallback and keeps the source on malformed data' {
    $result = Invoke-Scenario -Config 'PROFILE=MODERN' -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -VideoBitrate 'N/A' -VideoPacketSizes 'invalid'
    Assert-True ($result.FfprobeCalls -eq 2) "Expected inspection plus packet fallback, got $($result.FfprobeCalls)."
    Assert-True ($result.PublishedFiles.ContainsKey('sample.webm')) 'Malformed probe data caused source loss.'
}

Test-Case 'Enter selects unlimited Modern video by default and URL is not reconfirmed' {
    $formats = @{
        id = 'h264-order'
        formats = @(
            @{ format_id = '313'; vcodec = 'vp9'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 2000 },
            @{ format_id = '401'; vcodec = 'av01.0.08M.08'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 1000 },
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/watch?v=abc&list=xyz!mark', '') -ModernFormatsJson $formats
    Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -notmatch 'Use this URL') 'The removed URL confirmation prompt was displayed.'
    Assert-True ($result.Arguments -match 'ARG=\[137\+ba\[acodec\^=mp4a\]/137\+ba/137\]') "Modern did not prefer native H264 at equal resolution and frame rate. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'https://example\.test/watch\?v=abc&list=xyz!mark') "URL containing CMD-special characters was changed. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[%\(playlist&\{\}/\|\)s%\(playlist_index&\{\} - \|\)s%\(title\)s\.%\(ext\)s\]') "Clean title-only output template was not passed. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch '%\(id\)s') "Media ID was unexpectedly included in the filename template. Arguments: $($result.Arguments)"
}

Test-Case 'Modern prefers AV1 over VP9 at equal resolution and frame rate' {
    $formats = @{
        id = 'codec-order'
        formats = @(
            @{ format_id = '313'; vcodec = 'vp9'; acodec = 'none'; width = 3840; height = 2160; fps = 30; tbr = 8477 },
            @{ format_id = '401'; vcodec = 'av01.0.12M.08'; acodec = 'none'; width = 3840; height = 2160; fps = 30; tbr = 4369 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'av01.0.12M.08' -AudioCodec 'mp4a.40.2' -VideoHeight 2160 -ModernFormatsJson $formats

    Assert-True ($result.Arguments -match 'ARG=\[401\+ba\[acodec\^=mp4a\]/401\+ba/401\]') "Modern did not select the AV1 format explicitly. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch 'ARG=\[313\+ba') "Modern selected VP9 even though equivalent AV1 was available. Arguments: $($result.Arguments)"
}

Test-Case 'Modern prefers native H265 in the standard video path' {
    $formats = @{
        id = 'modern-h265-order'
        formats = @(
            @{ format_id = 'vp9'; vcodec = 'vp09.00.51.08'; acodec = 'none'; height = 1080; fps = 30; tbr = 2500 },
            @{ format_id = 'av1'; vcodec = 'av01.0.08M.08'; acodec = 'none'; height = 1080; fps = 30; tbr = 2200 },
            @{ format_id = 'h264'; vcodec = 'avc1.640028'; acodec = 'none'; height = 1080; fps = 30; tbr = 4000 },
            @{ format_id = 'h265'; vcodec = 'hvc1.2.4.L120.B0'; acodec = 'none'; height = 1080; fps = 30; tbr = 3000 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=1080`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=NO`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'hvc1.2.4.L120.B0' -AudioCodec 'aac' -MediaName 'sample.mp4' -ModernFormatsJson $formats

    Assert-True ($result.Arguments -match 'ARG=\[h265\+ba\[acodec\^=mp4a\]/h265\+ba/h265\]') "Modern did not select native H265 first. Arguments: $($result.Arguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'libx265') "Native H265 was unnecessarily transcoded. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Modern prefers native H265 in the multitrack video path' {
    $formats = @{
        id = 'modern-h265-order'
        formats = @(
            @{ format_id = 'vp9'; vcodec = 'vp09.00.51.08'; acodec = 'none'; height = 1080; fps = 30; tbr = 2500 },
            @{ format_id = 'av1'; vcodec = 'av01.0.08M.08'; acodec = 'none'; height = 1080; fps = 30; tbr = 2200 },
            @{ format_id = 'h264'; vcodec = 'avc1.640028'; acodec = 'none'; height = 1080; fps = 30; tbr = 4000 },
            @{ format_id = 'h265'; vcodec = 'hvc1.2.4.L120.B0'; acodec = 'none'; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = 'audio-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 128 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=1080`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'hvc1.2.4.L120.B0' -AudioCodec 'aac' -MediaName 'sample.mp4' -ModernFormatsJson $formats

    Assert-True ($result.Arguments -match 'ARG=\[h265\+audio-en\]') "Modern multitrack mode did not select native H265 first. Arguments: $($result.Arguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'libx265') "Native multitrack H265 was unnecessarily transcoded. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Universal prefers native H264 in the multitrack video path' {
    $formats = @{
        id = 'universal-h264-order'
        formats = @(
            @{ format_id = 'h265'; vcodec = 'hvc1.2.4.L120.B0'; acodec = 'none'; height = 1080; fps = 30; tbr = 5000 },
            @{ format_id = 'h264'; vcodec = 'avc1.640028'; acodec = 'none'; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = 'audio-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 128 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=1080`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mp4' -ModernFormatsJson $formats

    Assert-True ($result.Arguments -match 'ARG=\[h264\+audio-en\]') "Universal multitrack mode did not select native H264 first. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch 'ARG=\[h265\+audio-en\]') "Universal multitrack mode selected H265 over equivalent H264. Arguments: $($result.Arguments)"
}

Test-Case 'Modern keeps resolution ahead of codec preference' {
    $formats = @{
        id = 'resolution-order'
        formats = @(
            @{ format_id = 'h265'; vcodec = 'hvc1.2.4.L120.B0'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '313'; vcodec = 'vp9'; acodec = 'none'; width = 3840; height = 2160; fps = 30; tbr = 8000 }
        )
    } | ConvertTo-Json -Depth 5 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -AudioCodec 'mp4a.40.2' -VideoHeight 2160 -ModernFormatsJson $formats

    Assert-True ($result.Arguments -match 'ARG=\[313\+ba\[acodec\^=mp4a\]/313\+ba/313\]') "Modern lowered the resolution to obtain a preferred codec. Arguments: $($result.Arguments)"
}

Test-Case 'Modern playlist skips entries without video and downloads valid entries' {
    $metadata = @{
        _type = 'playlist'
        entries = @(
            @{ playlist_index = 1; id = 'audio-only'; formats = @(@{ format_id = 'a1'; vcodec = 'none'; acodec = 'mp4a.40.2' }) },
            @{ playlist_index = 2; id = 'video'; formats = @(@{ format_id = '401'; vcodec = 'av01.0.12M.08'; acodec = 'none'; width = 3840; height = 2160; fps = 30; tbr = 4000 }) }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/playlist', '', '') -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match '(?s)ARG=\[--playlist-items\]\r?\nARG=\[2\].*ARG=\[401\+ba\[acodec\^=mp4a\]/401\+ba/401\]') "The valid playlist entry was not downloaded after an entry without video. Arguments: $($result.Arguments)"
    Assert-True ($result.Output -match 'Download failed') 'The skipped playlist entry was not reported as a partial failure.'
}

Test-Case 'Modern retries cached cookies per playlist entry' {
    $metadata = @{
        _type = 'playlist'
        entries = @(
            @{ playlist_index = 1; id = 'first'; formats = @(@{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 }) },
            @{ playlist_index = 2; id = 'second'; formats = @(@{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 }) }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nCOOKIE_BROWSER=chrome`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/playlist', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mp4' -CookieSuccess 'firefox' -DownloadFailCookie 'chrome' -DownloadFailCookieItem '2' -ModernFormatsJson $metadata
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    $retriedSecondItem = $calls | Where-Object { $_ -match 'ARG=\[--playlist-items\]\r?\nARG=\[2\]' -and $_ -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[firefox\]' }

    Assert-True (@($retriedSecondItem).Count -eq 1) "The second playlist entry was not retried with fresh cookies. Arguments: $($result.Arguments)"
}

Test-Case 'Universal prefers native H264 after resolution and frame rate' {
    $result = Invoke-Scenario -Config "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/video', '')
    Assert-True ($result.Arguments -match 'ARG=\[-S\]\r?\nARG=\[res,fps,vcodec:h264\]') "Universal did not prefer native H264 after resolution and frame rate. Arguments: $($result.Arguments)"
}

Test-Case 'Quality prefers native AV1 in the standard video selector' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/video', '')
    Assert-True ($result.Arguments -match 'ARG=\[-S\]\r?\nARG=\[res,fps,vcodec:av1\]') "Quality did not prefer native AV1 after resolution and frame rate. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch 'ARG=\[res,fps,vcodec:h264\]') "Quality unexpectedly enabled the H264 preference. Arguments: $($result.Arguments)"
}

Test-Case 'Disabled all-audio setting keeps the single-track video selector' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '')

    Assert-True ($result.Arguments -match 'ARG=\[bv\*\+ba/b\]') "The disabled setting changed the existing selector. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch 'ARG=\[--audio-multistreams\]') "The disabled setting enabled multiple audio streams. Arguments: $($result.Arguments)"
}

Test-Case 'All-audio video selects one best track per language' {
    $metadata = @{
        id = 'multilingual-video'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '250-en'; vcodec = 'none'; acodec = 'opus'; language = 'en'; abr = 70; tbr = 70 },
            @{ format_id = '251-en'; vcodec = 'none'; acodec = 'opus'; language = 'en'; abr = 130; tbr = 130 },
            @{ format_id = '139-ru'; vcodec = 'none'; acodec = 'mp4a.40.5'; language = 'ru'; abr = 48; tbr = 48 },
            @{ format_id = '140-ru'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'ru'; abr = 129; tbr = 129 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mp4' -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[137\+251-en\+140-ru\]') "The best English and Russian tracks were not selected once each. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch '250-en|139-ru') "Lower-quality duplicates were downloaded. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--audio-multistreams\]') "yt-dlp was not allowed to merge multiple audio streams. Arguments: $($result.Arguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-metadata:s:a:0\]\r?\nARG=\[language=eng\]') "The first output track was not tagged as English. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-metadata:s:a:1\]\r?\nARG=\[language=rus\]') "The second output track was not tagged as Russian. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-disposition:a:0\]\r?\nARG=\[default\]') "The first audio track was not marked as default. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-disposition:a:1\]\r?\nARG=\[0\]') "A secondary audio track kept the default disposition. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'All-audio metadata normalizes language codes and names every track' {
    $metadata = @{
        id = 'language-metadata-video'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '140-deu'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'deu'; abr = 128; tbr = 128 },
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en-XX'; abr = 128; tbr = 128 },
            @{ format_id = '140-pt'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'pt-BR'; abr = 128; tbr = 128 },
            @{ format_id = '140-zh'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'zh-Hans'; abr = 128; tbr = 128 },
            @{ format_id = '140-invalid'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'not_a_language'; abr = 128; tbr = 128 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mp4' -ModernFormatsJson $metadata

    Assert-True ($result.FfmpegArguments -match 'ARG=\[language=deu\]') "An existing ISO 639-2 code was changed. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[language=eng\]') "The English code with an unknown region was not normalized through its base language. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[language=por\]') "The regional Portuguese code was not normalized. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[language=zho\]') "The scripted Chinese code was not normalized. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[language=und\]') "An invalid language code did not fall back to und. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[handler_name=German\]') "The German track was not named. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[handler_name=English\]') "The English track was not named. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[handler_name=Portuguese-Brazil\]') "The regional Portuguese track was not named. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[handler_name=Chinese-Simplified\]') "The scripted Chinese track was not named. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[handler_name=Unknown\]') "The unknown track was not named. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Reference YouTube metadata selects the expected English Uzbek and Russian tracks' {
    $metadata = @{
        id = 'qHk_uw3mOpY'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '139-0'; vcodec = 'none'; acodec = 'mp4a.40.5'; language = 'en'; abr = 48.80; tbr = 48.80 },
            @{ format_id = '140-0'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129.48; tbr = 129.48 },
            @{ format_id = '251-0'; vcodec = 'none'; acodec = 'opus'; language = 'en'; abr = 130.75; tbr = 130.75 },
            @{ format_id = '140-1'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'uz'; abr = 129.48; tbr = 129.48 },
            @{ format_id = '251-1'; vcodec = 'none'; acodec = 'opus'; language = 'uz'; abr = 133.25; tbr = 133.25 },
            @{ format_id = '140-2'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'ru'; abr = 129.48; tbr = 129.48 },
            @{ format_id = '251-2'; vcodec = 'none'; acodec = 'opus'; language = 'ru'; abr = 132.89; tbr = 132.89 }
        )
    } | ConvertTo-Json -Depth 6 -Compress

    $quality = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES" -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata
    $modern = Invoke-Scenario -Config "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES" -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata

    Assert-True ($quality.Arguments -match 'ARG=\[251-0\+251-2\+251-1\]|ARG=\[251-0\+251-1\+251-2\]') "Quality did not select all three best Opus tracks. Arguments: $($quality.Arguments)"
    Assert-True ($modern.Arguments -match 'ARG=\[140-0\+140-2\+140-1\]|ARG=\[140-0\+140-1\+140-2\]') "Modern did not select all three best AAC tracks. Arguments: $($modern.Arguments)"
}

Test-Case 'All-audio playlist uses each entry own language formats' {
    $metadata = @{
        _type = 'playlist'
        entries = @(
            @{ playlist_index = 1; id = 'first'; formats = @(
                @{ format_id = 'v1'; vcodec = 'avc1'; acodec = 'none'; height = 1080; fps = 30; tbr = 3000 },
                @{ format_id = 'a1-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 128 },
                @{ format_id = 'a1-ru'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'ru'; abr = 128 }
            ) },
            @{ playlist_index = 2; id = 'second'; formats = @(
                @{ format_id = 'v2'; vcodec = 'avc1'; acodec = 'none'; height = 1080; fps = 30; tbr = 3000 },
                @{ format_id = 'a2-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 128 },
                @{ format_id = 'a2-uz'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'uz'; abr = 128 }
            ) }
        )
    } | ConvertTo-Json -Depth 7 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/playlist', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mp4' -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match '(?s)ARG=\[--playlist-items\]\r?\nARG=\[1\].*ARG=\[v1\+a1-en\+a1-ru\]') "The first playlist entry used the wrong language formats. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match '(?s)ARG=\[--playlist-items\]\r?\nARG=\[2\].*ARG=\[v2\+a2-en\+a2-uz\]') "The second playlist entry used the wrong language formats. Arguments: $($result.Arguments)"
}

Test-Case 'Modern all-audio video converts every track when any track is not AAC' {
    $metadata = @{
        id = 'mixed-codec-video'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '251-ru'; vcodec = 'none'; acodec = 'opus'; language = 'ru'; abr = 130; tbr = 130 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -ActualAudioCodecs 'aac,opus' -MediaName 'sample.mp4' -ModernFormatsJson $metadata

    Assert-True ($result.FfmpegArguments -match 'ARG=\[-map\]\r?\nARG=\[0:a\?\]') "FFmpeg did not map every audio track. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-c:a\]\r?\nARG=\[aac\]') "The non-AAC track did not trigger AAC conversion for the output. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Modern all-audio video keeps every track when all tracks are AAC' {
    $metadata = @{
        id = 'aac-video'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '140-ru'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'ru'; abr = 127; tbr = 127 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -ActualAudioCodecs 'aac,aac' -MediaName 'sample.mp4' -ModernFormatsJson $metadata

    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[-c:a\]\r?\nARG=\[aac\]') "Compatible AAC tracks were unnecessarily converted. Tools: $($result.FfmpegArguments)"
}

Test-Case 'Quality all-audio mode prefers Opus and stores audio-only output in MKA' {
    $metadata = @{
        id = 'multilingual-audio'
        formats = @(
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '251-en'; vcodec = 'none'; acodec = 'opus'; language = 'en'; abr = 130; tbr = 130 },
            @{ format_id = '251-ru'; vcodec = 'none'; acodec = 'opus'; language = 'ru'; abr = 126; tbr = 126 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nSTORE_OPUS_IN_MP4=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[251-en\+251-ru\]') "Quality did not select one best Opus track per language. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--merge-output-format\]\r?\nARG=\[mkv\]') "Quality did not use a safe multistream merge container. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--remux-video\]\r?\nARG=\[mka\]') "Quality did not produce MKA audio. Arguments: $($result.Arguments)"
}

Test-Case 'Quality all-audio mode stores multiple Opus tracks in MP4 when configured' {
    $metadata = @{
        id = 'multilingual-audio'
        formats = @(
            @{ format_id = '251-en'; vcodec = 'none'; acodec = 'opus'; language = 'en'; abr = 130; tbr = 130 },
            @{ format_id = '251-ru'; vcodec = 'none'; acodec = 'opus'; language = 'ru'; abr = 126; tbr = 126 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nSTORE_OPUS_IN_MP4=YES"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[251-en\+251-ru\]') "Quality MP4 did not keep all Opus languages. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--merge-output-format\]\r?\nARG=\[mkv\]') "Quality did not use a safe intermediate multistream container. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--remux-video\]\r?\nARG=\[mp4\]') "Quality did not force the final MP4 container. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match '(?m)^ARG=\[--embed-chapters\]\r?$') 'Quality all-audio MP4 did not request embedded chapters.'
    Assert-True ($result.Arguments -match '(?m)^ARG=\[--embed-metadata\]\r?$') 'Quality all-audio MP4 did not request embedded metadata.'
}

Test-Case 'Quality all-audio mode keeps every language from combined-only formats' {
    $metadata = @{
        id = 'combined-only'
        formats = @(
            @{ format_id = '18-en'; vcodec = 'avc1.42001E'; acodec = 'mp4a.40.2'; language = 'en'; width = 640; height = 360; fps = 30; tbr = 600 },
            @{ format_id = '18-ru'; vcodec = 'avc1.42001E'; acodec = 'mp4a.40.2'; language = 'ru'; width = 640; height = 360; fps = 30; tbr = 600 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nSTORE_OPUS_IN_MP4=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[18-en\+18-ru\]') "Combined formats for both languages were not selected. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--video-multistreams\]') "Combined multilingual formats were collapsed before merging. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'VideoRemuxer\+ffmpeg_o:-vn') "Video streams were not removed from the audio-only output. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'VideoRemuxer\+ffmpeg_o:-vn -c:a libopus') "Non-Opus languages were not converted to Opus for Quality. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'metadata:s:a:0 language=eng.*metadata:s:a:1 language=rus') "Combined audio tracks did not receive distinct language tags. Arguments: $($result.Arguments)"
}

Test-Case 'All-audio video prefers standalone audio and keeps combined-only languages' {
    $metadata = @{
        id = 'mixed-layout-video'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '18-en'; vcodec = 'avc1.42001E'; acodec = 'mp4a.40.2'; language = 'en'; width = 640; height = 360; tbr = 600 },
            @{ format_id = '18-ru'; vcodec = 'avc1.42001E'; acodec = 'mp4a.40.2'; language = 'ru'; width = 640; height = 360; tbr = 600 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mkv' -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[137\+140-en\+18-ru\]') "Standalone English and combined Russian audio were not selected together. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch '137\+140-en\+18-en') "The lower-priority combined English audio duplicated the language. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--video-multistreams\]') "The combined Russian format was not retained for postprocessing. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--merge-output-format\]\r?\nARG=\[mkv\]') "Combined video streams were not forced through the cleanup pass. Arguments: $($result.Arguments)"
}

Test-Case 'All-audio video prefers video-only over equivalent dubbed video' {
    $metadata = @{
        id = 'video-only-preference'
        formats = @(
            @{ format_id = '137'; vcodec = 'avc1.640028'; acodec = 'none'; width = 1920; height = 1080; fps = 30; quality = 9; tbr = 3000 },
            @{ format_id = '96-es'; vcodec = 'avc1.640028'; acodec = 'mp4a.40.2'; language = 'es'; language_preference = -1; width = 1920; height = 1080; fps = 30; quality = 9; tbr = 3200 },
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; language_preference = 10; abr = 128; tbr = 128 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mkv' -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[137\+140-en\+96-es\]') "Equivalent combined Spanish video displaced video-only and put Spanish first. Arguments: $($result.Arguments)"
}

Test-Case 'All-audio combined video prefers the original language' {
    $metadata = @{
        id = 'combined-language-preference'
        formats = @(
            @{ format_id = '96-en'; vcodec = 'avc1.640028'; acodec = 'mp4a.40.2'; language = 'en'; language_preference = 10; width = 1920; height = 1080; fps = 30; quality = 9; tbr = 3000 },
            @{ format_id = '96-es'; vcodec = 'avc1.640028'; acodec = 'mp4a.40.2'; language = 'es'; language_preference = -1; width = 1920; height = 1080; fps = 30; quality = 9; tbr = 3200 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mkv' -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[96-en\+96-es\]') "A dubbed combined format displaced the original-language combined video. Arguments: $($result.Arguments)"
}

Test-Case 'Combined primary video does not duplicate its language with standalone audio' {
    $metadata = @{
        id = 'combined-primary-video'
        formats = @(
            @{ format_id = '18-en'; vcodec = 'avc1.42001E'; acodec = 'mp4a.40.2'; language = 'en'; width = 1920; height = 1080; fps = 30; tbr = 3000 },
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '18-ru'; vcodec = 'avc1.42001E'; acodec = 'mp4a.40.2'; language = 'ru'; width = 640; height = 360; fps = 30; tbr = 600 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mkv' -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[18-en\+18-ru\]') "The combined primary English track and Russian dubbing were not selected exactly once. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -notmatch '18-en\+140-en') "English was duplicated by the standalone audio format. Arguments: $($result.Arguments)"
}

Test-Case 'Modern all-audio mode creates one multistream M4A' {
    $metadata = @{
        id = 'modern-multilingual-audio'
        formats = @(
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '140-ru'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'ru'; abr = 127; tbr = 127 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[140-en\+140-ru\]') "Modern did not select every language. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--audio-multistreams\]') "Modern did not enable multiple audio streams. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--recode-video\]\r?\nARG=\[m4a\]') "Modern did not create an M4A container. Arguments: $($result.Arguments)"
}

Test-Case 'Universal all-audio mode creates one multistream M4A' {
    $metadata = @{
        id = 'universal-multilingual-audio'
        formats = @(
            @{ format_id = '140-en'; vcodec = 'none'; acodec = 'mp4a.40.2'; language = 'en'; abr = 129; tbr = 129 },
            @{ format_id = '251-ru'; vcodec = 'none'; acodec = 'opus'; language = 'ru'; abr = 130; tbr = 130 }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nDOWNLOAD_ALL_AUDIO_TRACKS=YES"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio', '') -ModernFormatsJson $metadata

    Assert-True ($result.Arguments -match 'ARG=\[140-en\+251-ru\]') "Universal dropped an audio language without native AAC. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--recode-video\]\r?\nARG=\[m4a\]') "Universal did not convert the multistream result to M4A. Arguments: $($result.Arguments)"
}

Test-Case 'Fixed browser order starts with Chrome and reuses successful cookies' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'chrome'
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    Assert-True ($calls.Count -ge 2) "Expected a cookie probe and a download. Arguments: $($result.Arguments)"
    Assert-True ($calls[0] -match 'ARG=\[--simulate\]\r?\n.*ARG=\[--cookies-from-browser\]\r?\nARG=\[chrome\]') "Chrome was not probed first. Arguments: $($result.Arguments)"
    Assert-True ($calls[-1] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[chrome\]') "Selected Chrome cookies were not reused for the download. Arguments: $($result.Arguments)"
}

Test-Case 'Obsolete cookie bridge executables are ignored' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'chrome' -ObsoleteCookieBridge
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    Assert-True ($result.Arguments -notmatch 'ARG=\[--request\]') "The obsolete Chromium bridge was still launched. Arguments: $($result.Arguments)"
    Assert-True ($calls[-1] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[chrome\]') "Direct Chrome cookies were not used. Arguments: $($result.Arguments)"
}

Test-Case 'Fixed browser order falls through to Zen profiles' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/age-restricted', '3', '') -CookieSuccess 'ZEN'
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    $probes = @($calls | Where-Object { $_ -match 'ARG=\[--simulate\]' })
    $sources = @($probes | ForEach-Object { if ($_ -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[([^\]]+)\]') { $Matches[1] } })
    Assert-True (($sources -join ',') -match '^chrome,edge,firefox,opera,brave,vivaldi,chrome:.*\\Perplexity\\Comet\\User Data\\Default,firefox:.*\\AppData\\Roaming\\zen\\Profiles$') "Unexpected browser fallback order: $($sources -join ', ')"
    Assert-True ($calls[-1] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[firefox:.*\\zen\\Profiles\]') "Zen cookies were not reused for the download. Arguments: $($result.Arguments)"
}

Test-Case 'Saved browser is used directly and a stale value falls through fixed order' {
    $result = Invoke-Scenario -Config "COOKIE_BROWSER=firefox" -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -CookieSuccess 'edge' -DownloadFailCookie 'firefox'
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    $sources = [regex]::Matches($result.Arguments, 'ARG=\[--cookies-from-browser\]\r?\nARG=\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value }
    Assert-True ($calls[0] -notmatch 'ARG=\[--simulate\]') "The saved browser was probed instead of being used directly. Arguments: $($result.Arguments)"
    Assert-True ($calls[0] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[firefox\]') "The first real attempt did not use saved Firefox cookies. Arguments: $($result.Arguments)"
    Assert-True ($result.Output -match 'Saved browser session failed before (reading formats|downloading)') "A failed saved browser did not trigger fallback discovery. Output: $($result.Output)"
    Assert-True (($sources | Select-Object -First 3) -join ',' -eq 'firefox,chrome,edge') "Unexpected browser order: $($sources -join ',')"
    Assert-True ($result.Config -match '(?m)^COOKIE_BROWSER=edge\r?$') 'The successful fallback was not remembered.'
    Assert-True (([regex]::Matches($result.Config, '(?im)^COOKIE_BROWSER=')).Count -eq 1) "COOKIE_BROWSER was duplicated. Config: $($result.Config)"
}

Test-Case 'All failed browser simulations lead to one cookie-free download' {
    $result = Invoke-Scenario -Config 'COOKIE_BROWSER=chrome' -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -CookieSuccess 'never' -DownloadFailCookie 'chrome'
    Assert-True ($result.Output -match 'continuing without browser cookies') 'Cookie-free fallback was not reported.'
    Assert-True ($result.Arguments -match 'ARG=\[-f\]') 'The media download was not attempted.'
}

Test-Case 'Zen is saved by name and restored as its Firefox profile path' {
    $firstConfig = "MAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nCOOKIE_BROWSER=chrome"
    $first = Invoke-Scenario -Config $firstConfig -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'ZEN' -DownloadFailCookie 'chrome'
    Assert-True ($first.Config -match '(?m)^COOKIE_BROWSER=zen\r?$') "Zen was not saved by its portable name. Config: $($first.Config)"

    $secondConfig = "MAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nCOOKIE_BROWSER=zen"
    $second = Invoke-Scenario -Config $secondConfig -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'ZEN'
    $calls = @($second.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    $probes = @($calls | Where-Object { $_ -match 'ARG=\[--simulate\]' })
    Assert-True ($probes.Count -eq 0) "Saved Zen was probed before the download. Arguments: $($second.Arguments)"
    Assert-True ($calls[0] -match 'ARG=\[firefox:.*\\zen\\Profiles\]') "Saved Zen did not restore its Firefox profile path. Arguments: $($second.Arguments)"
}

Test-Case 'Comet profile cookies are discovered saved and restored' {
    $firstConfig = "MAX_HEIGHT=0`r`nDEFAULT_MODE=video"
    $first = Invoke-Scenario -Config $firstConfig -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'COMET'
    Assert-True ($first.Config -match '(?m)^COOKIE_BROWSER=comet\r?$') "Comet was not saved by its portable name. Config: $($first.Config)"

    $firstCalls = @($first.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    Assert-True ($firstCalls[-1] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[chrome:.*\\Perplexity\\Comet\\User Data\\Default\]') "Discovered Comet cookies were not reused for the download. Arguments: $($first.Arguments)"

    $secondConfig = "MAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nCOOKIE_BROWSER=comet"
    $second = Invoke-Scenario -Config $secondConfig -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'COMET'
    $secondCalls = @($second.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    $probes = @($secondCalls | Where-Object { $_ -match 'ARG=\[--simulate\]' })
    Assert-True ($probes.Count -eq 0) "Saved Comet was probed before the download. Arguments: $($second.Arguments)"
    Assert-True ($secondCalls[0] -match 'ARG=\[chrome:.*\\Perplexity\\Comet\\User Data\\Default\]') "Saved Comet did not restore its Chromium profile path. Arguments: $($second.Arguments)"
}

Test-Case 'Comet selects the newest profile across Chromium cookie layouts' {
    $config = "MAX_HEIGHT=0`r`nDEFAULT_MODE=video"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'COMET_PROFILE2' -CometFixture 'Multiple'
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })
    $probes = @($calls | Where-Object { $_ -match 'ARG=\[--simulate\]' })

    Assert-True ($probes[-1] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[chrome:.*\\Perplexity\\Comet\\User Data\\Profile 2\]') "The newest Comet profile was not selected. Arguments: $($result.Arguments)"
    Assert-True ($result.Config -match '(?m)^COOKIE_BROWSER=comet\r?$') "The working Comet browser was not remembered. Config: $($result.Config)"
}

Test-Case 'Comet supports a Cookies database directly inside the profile' {
    $config = "MAX_HEIGHT=0`r`nDEFAULT_MODE=video"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/private', '3', '') -CookieSuccess 'COMET' -CometFixture 'Direct'
    $calls = @($result.Arguments -split '(?m)^CALL\r?$' | Where-Object { $_ -match '\S' })

    Assert-True ($calls[-1] -match 'ARG=\[--cookies-from-browser\]\r?\nARG=\[chrome:.*\\Perplexity\\Comet\\User Data\\Default\]') "The direct Comet cookie layout resolved to the wrong profile. Arguments: $($result.Arguments)"
}

Test-Case 'Video resolution limit applies to both format branches' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=1080`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/video', '')
    Assert-True ($result.Arguments -match 'ARG=\[bv\*\[height\^*<=1080\]\+ba/b\[height\^*<=1080\]\]') "Height-limited selector was not passed. Arguments: $($result.Arguments)"
}

Test-Case 'Video downloads embed chapters and metadata' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=1080`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'sample.mp4'
    Assert-True ($result.Arguments -match '(?m)^ARG=\[--embed-chapters\]\r?$') 'Video download did not request embedded chapters.'
    Assert-True ($result.Arguments -match '(?m)^ARG=\[--embed-metadata\]\r?$') 'Video download did not request embedded metadata.'
}

Test-Case 'Audio downloads embed chapters and metadata' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio" -InputLines @('https://example.test/audio', '')
    Assert-True ($result.Arguments -match '(?m)^ARG=\[--embed-chapters\]\r?$') 'Audio download did not request embedded chapters.'
    Assert-True ($result.Arguments -match '(?m)^ARG=\[--embed-metadata\]\r?$') 'Audio download did not request embedded metadata.'
}

Test-Case 'Quality audio falls back to combined media and keeps the source audio codec' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/audio', '2')
    Assert-True ($result.Arguments -match 'ARG=\[ba/b\]') "Combined-media fallback was not added to the Quality audio selector. Output: $($result.Output) Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--extract-audio\]') 'Quality mode cannot extract audio from its combined-media fallback.'
    Assert-True ($result.Arguments -match 'ARG=\[--audio-format\]\r?\nARG=\[best\]') 'Quality mode did not preserve the source audio codec.'
    Assert-True ($result.Arguments -match 'ARG=\[--embed-thumbnail\]') "Audio cover embedding was not enabled. Arguments: $($result.Arguments)"
}

Test-Case 'Quality Opus audio stays in an Opus container by default' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio" -InputLines @('https://example.test/audio', '')
    Assert-True ($result.Arguments -match 'ARG=\[--audio-format\]\r?\nARG=\[best\]') 'Quality mode did not preserve the Opus codec.'
    Assert-True ($result.Arguments -notmatch 'ARG=\[--remux-video\]') "Quality Opus audio was unexpectedly remuxed. Arguments: $($result.Arguments)"
}

Test-Case 'Quality Opus audio is stored in MP4 when configured' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nSTORE_OPUS_IN_MP4=YES"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio', '')
    Assert-True ($result.Arguments -match 'ARG=\[--audio-format\]\r?\nARG=\[best\]') 'Quality mode did not preserve the Opus codec.'
    Assert-True ($result.Arguments -match 'ARG=\[--remux-video\]\r?\nARG=\[opus>mp4\]') "Quality Opus audio was not remuxed to an MP4 container. Arguments: $($result.Arguments)"
}

Test-Case 'Modern audio falls back to combined AAC or any combined media' {
    $result = Invoke-Scenario -Config "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio" -InputLines @('https://example.test/audio', '')
    Assert-True ($result.Arguments -match 'ARG=\[ba\[acodec\^=mp4a\]/ba/b\[acodec\^=mp4a\]/b\]') "Modern audio selector lacks the combined-media fallbacks. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--extract-audio\]') 'Modern mode cannot extract audio from combined media.'
}

Test-Case 'Universal audio falls back to combined media before MP3 conversion' {
    $result = Invoke-Scenario -Config "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio" -InputLines @('https://example.test/audio', '')
    Assert-True ($result.Arguments -match 'ARG=\[ba/b\]') "Universal audio selector lacks the combined-media fallback. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'ARG=\[--extract-audio\]') 'Universal mode cannot extract audio from combined media.'
}

Test-Case 'Thumbnail mode skips media download' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/thumb', '3')
    Assert-True ($result.Arguments -match '--skip-download') "Thumbnail mode did not skip the media download. Output: $($result.Output) Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match '--write-thumbnail') 'Thumbnail mode did not request a thumbnail.'
}

Test-Case 'Configured audio mode is selected by Enter' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=audio" -InputLines @('https://example.test/default-audio', '')
    Assert-True ($result.Arguments -match 'ARG=\[ba/b\]') "Configured default audio mode was not used. Arguments: $($result.Arguments)"
}

Test-Case 'Invalid configuration stops before downloading' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=banana`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/video')
    Assert-True ($result.ExitCode -ne 0) 'Invalid MAX_HEIGHT unexpectedly succeeded.'
    Assert-True ($result.Output -match 'Invalid MAX_HEIGHT') "Helpful configuration error was missing. Output: $($result.Output)"
    Assert-True ([string]::IsNullOrWhiteSpace($result.Arguments)) 'Download started despite invalid configuration.'
}

Test-Case 'Invalid STORE_OPUS_IN_MP4 stops before downloading' {
    $config = "MAX_HEIGHT=0`r`nDEFAULT_MODE=audio`r`nSTORE_OPUS_IN_MP4=MAYBE"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/audio')
    Assert-True ($result.ExitCode -ne 0) 'Invalid STORE_OPUS_IN_MP4 unexpectedly succeeded.'
    Assert-True ($result.Output -match 'Invalid STORE_OPUS_IN_MP4') "Helpful STORE_OPUS_IN_MP4 error was missing. Output: $($result.Output)"
    Assert-True ([string]::IsNullOrWhiteSpace($result.Arguments)) 'Download started despite invalid STORE_OPUS_IN_MP4.'
}

Test-Case 'Invalid DOWNLOAD_ALL_AUDIO_TRACKS stops before downloading' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nDOWNLOAD_ALL_AUDIO_TRACKS=MAYBE"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video')

    Assert-True ($result.ExitCode -ne 0) 'Invalid DOWNLOAD_ALL_AUDIO_TRACKS unexpectedly succeeded.'
    Assert-True ($result.Output -match 'Invalid DOWNLOAD_ALL_AUDIO_TRACKS') "Helpful all-audio validation error was missing. Output: $($result.Output)"
    Assert-True ([string]::IsNullOrWhiteSpace($result.Arguments)) 'Download started despite invalid DOWNLOAD_ALL_AUDIO_TRACKS.'
}

Test-Case 'Failed update warns and continues with installed yt-dlp' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/video', '') -UpdateExitCode 1
    Assert-True ($result.ExitCode -eq 0) "Update failure stopped the download. Output: $($result.Output)"
    Assert-True ($result.Output -match 'update failed') "Update warning was missing. Output: $($result.Output)"
    Assert-True ($result.Arguments -match 'https://example\.test/video') 'Download did not continue after update failure.'
    Assert-True ($result.YtdlpHashAfter -eq $result.YtdlpHashBefore) 'Failed update changed the working yt-dlp executable.'
    Assert-True (-not $result.YtdlpNewExists) 'Failed update left the staged yt-dlp executable behind.'
}

Test-Case 'Failed download returns to the URL prompt and exits on blank input' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @('https://example.test/broken', '', '') -DownloadExitCode 1
    Assert-True ($result.ExitCode -eq 0) "The wrapper did not exit cleanly after the retry prompt. Output: $($result.Output)"
    Assert-True ($result.Output -match 'Download failed') "Download failure message was missing. Output: $($result.Output)"
    $promptCount = ([regex]::Matches($result.Output, 'Paste video or playlist URL')).Count
    Assert-True ($promptCount -eq 2) "Expected the URL prompt twice, got $promptCount. Output: $($result.Output)"
}

Test-Case 'Successful downloads return to the URL prompt until blank input' {
    $result = Invoke-Scenario -Config "MAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @(
        'https://example.test/first', '3',
        'https://example.test/second', '3',
        ''
    )
    Assert-True ($result.ExitCode -eq 0) "The repeated download loop did not exit cleanly. Output: $($result.Output)"
    Assert-True ($result.Arguments -match 'https://example\.test/first') "The first URL was not downloaded. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match 'https://example\.test/second') "The second URL was not downloaded. Arguments: $($result.Arguments)"
    $promptCount = ([regex]::Matches($result.Output, 'Paste video or playlist URL')).Count
    Assert-True ($promptCount -eq 3) "Expected the URL prompt three times, got $promptCount. Output: $($result.Output)"
}

Test-Case 'Repeated downloads keep the original and add a numbered duplicate' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @(
        'https://example.test/first', '',
        'https://example.test/second', '',
        ''
    ) -VideoCodec 'av01.0.08M.08' -AudioCodec 'opus' -MediaName 'Same title.mp4'
    Assert-True ($result.PublishedFiles.Count -eq 2) "Expected two published files, got $($result.PublishedFiles.Count): $($result.PublishedFiles.Keys -join ', ')"
    Assert-True ($result.PublishedFiles['Same title.mp4'] -eq 'https://example.test/first') 'The first download was overwritten or renamed.'
    Assert-True ($result.PublishedFiles['Same title (1).mp4'] -eq 'https://example.test/second') 'The repeated download did not receive the (1) suffix.'
}

Test-Case 'Invalid choice after a failed download does not reuse the old mode' {
    $result = Invoke-Scenario -Config "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video" -InputLines @(
        'https://example.test/first', '2',
        'https://example.test/second', '9', '3',
        ''
    ) -DownloadExitCode 1 -CookieSuccess 'never'
    $audioSelections = ([regex]::Matches($result.Arguments, 'ARG=\[ba/b\]')).Count
    Assert-True ($audioSelections -eq 1) "The previous audio mode was reused after an invalid choice. Arguments: $($result.Arguments)"
    Assert-True ($result.Arguments -match '--write-thumbnail') "The corrected thumbnail choice was not used. Arguments: $($result.Arguments)"
    Assert-True ($result.Output -match 'Invalid choice') "Invalid menu choice was not reported. Output: $($result.Output)"
}

Test-Case 'Quality profile converts VP9 to AV1 on the CPU' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9'
    Assert-True ($result.ExitCode -eq 0) "Quality conversion failed. Output: $($result.Output)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libsvtav1\]') "VP9 was not converted with libsvtav1. yt-dlp: $($result.Arguments) FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[7920k\]') "1080p VP9 to AV1 did not use 90% plus the 10% transcode margin. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-pass\]\r?\nARG=\[1\]') "The software analysis pass was not run. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-pass\]\r?\nARG=\[2\]') "The software output pass was not run. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[-maxrate\]|ARG=\[-bufsize\]') "SVT-AV1 ABR was given CRF-only peak-rate options. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Quality profile uses the stronger AV1 saving for 4K VP9' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -VideoBitrate 8000000 -VideoHeight 2160
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[7040k\]') "4K VP9 to AV1 did not use 80% plus the 10% transcode margin. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Missing WebM stream bitrate is calculated from video packets only' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -VideoBitrate 'N/A' -VideoHeight 1080 -VideoDuration '10' -VideoPacketSizes '5000000,5000000'
    Assert-True ($result.ExitCode -eq 0) "Packet-based bitrate fallback failed. Output: $($result.Output)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[7920k\]') "Packet-based 8 Mbps source bitrate was not converted to the expected AV1 target. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Quality profile remuxes VP9 to MP4 when AV1 conversion is disabled' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=NO`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[copy\]') "VP9 was not remuxed without re-encoding. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[libsvtav1\]') "VP9 was unexpectedly converted to AV1. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'sample\.saf-transcoding\.mp4') "Quality output was not written as MP4. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Quality profile remuxes AV1 and Opus from WebM to MP4' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'av01.0.08M.08' -AudioCodec 'opus'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[copy\]') "AV1 and Opus were not remuxed without re-encoding. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'sample\.saf-transcoding\.mp4') "Quality AV1 output was not written as MP4. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Modern profile converts VP9 to H265 on the CPU' {
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -AudioCodec 'mp4a.40.2'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libx265\]') "VP9 was not converted with libx265. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[8800k\]') "VP9 to H265 did not preserve bitrate plus the 10% transcode margin. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Video transcodes replace the inherited Google handler name with the source codec' {
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'av01.0.08M.08' -AudioCodec 'mp4a.40.2'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libx265\]') "AV1 was not converted with libx265. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-metadata:s:v:0\]\r?\nARG=\[handler_name=Transcoded from AV1 by SaF yt-dlp Wrapper\]') "The transcode did not replace the video handler name with a normalized source codec. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Modern profile remuxes native H264 and AAC into MP4' {
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=1080`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[copy\]') "Native H264/AAC in a non-MP4 container was not remuxed. Tools: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[libx265\]') "Native H264 was unnecessarily transcoded. Tools: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[handler_name=Transcoded from ') "A remux was incorrectly labeled as a transcode. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Modern format fallback always keeps a video stream' {
    $config = "PROFILE=MODERN`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '')
    Assert-True ($result.Arguments -match 'ARG=\[v1\+ba\[acodec\^=mp4a\]/v1\+ba/v1\]') "Modern fallback could select audio without video. Output: $($result.Output) Arguments: $($result.Arguments)"
}

Test-Case 'Universal profile converts AV1 to H264 and non-AAC audio to AAC' {
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'av01.0.08M.08' -AudioCodec 'opus'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libx264\]') "AV1 was not converted to H264. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[aac\]') "Non-AAC audio was not converted to AAC. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[yuv420p\]') "Universal pixel format was not enforced. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[14696k\]') "1080p AV1 to H264 did not use the inverse efficiency coefficient plus transcode margin. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Universal profile trusts the actual merged audio codec over yt-dlp metadata' {
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'mp4a.40.2' -ActualAudioCodec 'opus' -MediaName 'sample.mp4'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[aac\]') "Actual Opus audio was copied because yt-dlp reported AAC. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:a\]\r?\nARG=\[192k\]') "Universal did not encode actual Opus audio at 192 kbps. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Universal profile remuxes compatible H264 and AAC into MP4' {
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'avc1.640028' -AudioCodec 'mp4a.40.2'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[copy\]') "Compatible streams in WebM were not remuxed to MP4. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[libx264\]') "Compatible H264 was unnecessarily transcoded. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Universal profile normalizes incompatible H264 pixel formats' {
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -PixelFormat 'yuv444p'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libx264\]') "Incompatible H264 pixel format was not normalized. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[yuv420p\]') "Universal output was not forced to yuv420p. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Hardware AV1 is used when enabled and available' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=YES"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -HardwareEncoders 'av1_nvenc'
    Assert-True ($result.FfmpegArguments -match 'ARG=\[av1_nvenc\]') "Available NVENC AV1 was not selected. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[p6\]') "NVENC quality preset was not applied. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[8712k\]') "Hardware AV1 did not receive its additional 10% bitrate margin. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[-cq\]|ARG=\[-global_quality\]|ARG=\[-qvbr_quality_level\]') "Hardware encoding still used constant-quality rate control. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Failed hardware encoding retries with the CPU encoder' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=YES"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -HardwareEncoders 'av1_nvenc' -FailEncoder 'av1_nvenc' -FailEncoderExit -22
    Assert-True ($result.Output -match 'Falling back to CPU') "CPU fallback was not reported. Output: $($result.Output)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libsvtav1\]') "CPU AV1 retry was not attempted. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[8712k\]') "The failed hardware attempt did not use the hardware bitrate margin. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-b:v\]\r?\nARG=\[7920k\]') "CPU fallback did not return to the software bitrate target. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Completed playlist entries are processed after a partial yt-dlp failure' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/playlist', '', '') -VideoCodec 'vp9' -DownloadExitCode 1
    Assert-True ($result.FfmpegArguments -match 'ARG=\[libsvtav1\]') "A completed playlist entry was not processed after yt-dlp returned an error. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.Output -match 'Download failed') "The partial yt-dlp failure was not reported. Output: $($result.Output)"
}

Test-Case 'Queued filenames are not expanded as CMD variables' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -MediaName '100%USERNAME%.webm'
    Assert-True ($result.FfmpegArguments -match [regex]::Escape('100%USERNAME%.webm')) "Percent signs in the downloaded filename were expanded by CMD. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Universal pixel-format probing preserves percent signs in filenames' {
    $config = "PROFILE=UNIVERSAL`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -PixelFormat 'yuv420p' -MediaName '100%USERNAME%.mp4'
    Assert-True ($result.FfmpegArguments -match [regex]::Escape('100%USERNAME%.mp4')) "Percent signs were expanded before ffprobe. Tools: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -notmatch 'ARG=\[libx264\]') "Compatible H264 was unnecessarily transcoded. Tools: $($result.FfmpegArguments)"
}

Test-Case 'UTF-8 queue preserves Japanese filenames on an OEM console' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $mediaName = 'HoYoHoYo' + [char]0x306B + [char]0x3057 + [char]0x3066 + [char]0x3042 + [char]0x3052 + [char]0x308B + '.webm'
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -MediaName $mediaName -InitialCodePage 866
    Assert-True ($result.FfmpegArguments -match [regex]::Escape($mediaName)) "The UTF-8 queue corrupted the Japanese filename. Tools: $($result.FfmpegArguments)"
}

Test-Case 'One failed playlist conversion does not stop later entries' {
    $config = "PROFILE=QUALITY`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/playlist', '', '') -VideoCodec 'vp9' -MediaName 'first.webm' -SecondMediaName 'second.webm' -SecondVideoCodec 'vp9' -FailInputContains 'first.webm'
    Assert-True ($result.FfmpegArguments -match 'first\.webm') "The failing first playlist file never reached FFmpeg. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'second\.webm') "The second playlist file never reached FFmpeg. FFmpeg: $($result.FfmpegArguments)"
    Assert-True ($result.FfmpegArguments -match 'ARG=\[-pass\]\r?\nARG=\[2\]') "The second playlist file did not complete its output pass. FFmpeg: $($result.FfmpegArguments)"
}

Test-Case 'Release archives use clean defaults without changing the working config' {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $builder = Join-Path $repoRoot 'build-release.cmd'
    Assert-True (Test-Path -LiteralPath $builder -PathType Leaf) 'Standalone CMD release builder is missing.'
    $caseRoot = Join-Path $env:TEMP ("saf-release-builder-test-" + [guid]::NewGuid().ToString('N'))
    $sourceRoot = Join-Path $caseRoot 'source'
    $outputRoot = Join-Path $caseRoot 'dist'
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    try {
        foreach ($name in @('build-release.cmd', 'SaF-YTDLP.cmd', 'SaF-YTDLP.sh', 'README.md', 'LICENSE')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination (Join-Path $sourceRoot $name)
        }
        $personalConfig = "PROFILE=QUALITY`r`nCOOKIE_BROWSER=zen`r`n"
        [IO.File]::WriteAllText((Join-Path $sourceRoot 'config.ini'), $personalConfig, [Text.Encoding]::ASCII)

        $oldPath = $env:PATH
        $oldProgramFiles = $env:ProgramFiles
        $oldProgramFilesX86 = ${env:ProgramFiles(x86)}
        $oldErrorActionPreference = $ErrorActionPreference
        try {
            $env:PATH = Join-Path $env:SystemRoot 'System32'
            $env:ProgramFiles = Join-Path $caseRoot 'missing-program-files'
            ${env:ProgramFiles(x86)} = Join-Path $caseRoot 'missing-program-files-x86'
            $ErrorActionPreference = 'Continue'
            $missingTarOutput = (& cmd.exe /d /c call (Join-Path $sourceRoot 'build-release.cmd') $sourceRoot $outputRoot 2>&1 | Out-String)
            $missingTarExitCode = $LASTEXITCODE
        } finally {
            $env:PATH = $oldPath
            $env:ProgramFiles = $oldProgramFiles
            ${env:ProgramFiles(x86)} = $oldProgramFilesX86
            $ErrorActionPreference = $oldErrorActionPreference
        }
        Assert-True ($missingTarExitCode -eq 1) "Missing GNU tar did not produce a controlled failure. Output: $missingTarOutput"
        Assert-True ($missingTarOutput -match 'GNU tar is required') "Missing GNU tar error was not helpful. Output: $missingTarOutput"

        & cmd.exe /d /c call (Join-Path $sourceRoot 'build-release.cmd') $sourceRoot $outputRoot $fakeGnuTarFixture
        Assert-True ($LASTEXITCODE -eq 0) 'Release builder failed.'
        Assert-True (([IO.File]::ReadAllText((Join-Path $sourceRoot 'config.ini'), [Text.Encoding]::ASCII)) -eq $personalConfig) 'Working config.ini was changed.'

        $windowsArchive = Join-Path $outputRoot 'SaF-yt-dlp-Wrapper-Windows.zip'
        $unixArchive = Join-Path $outputRoot 'SaF-yt-dlp-Wrapper-Unix.tar.gz'
        Assert-True (Test-Path -LiteralPath $windowsArchive) 'Windows release archive is missing.'
        Assert-True (Test-Path -LiteralPath $unixArchive) 'Unix release archive is missing.'

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($windowsArchive)
        try {
            $zipNames = @($zip.Entries | ForEach-Object FullName | Sort-Object)
            Assert-True (($zipNames -join ',') -eq 'config.ini,LICENSE,README.md,SaF-YTDLP.cmd') "Unexpected Windows archive entries: $($zipNames -join ', ')"
            $configEntry = $zip.Entries | Where-Object FullName -eq 'config.ini'
            $reader = New-Object IO.StreamReader($configEntry.Open())
            try { $windowsConfig = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally {
            $zip.Dispose()
        }
        $tarNames = @(& tar -tzf $unixArchive | ForEach-Object { $_.TrimStart('./') } | Sort-Object)
        Assert-True (($tarNames -join ',') -eq 'config.ini,LICENSE,README.md,SaF-YTDLP.sh') "Unexpected Unix archive entries: $($tarNames -join ', ')"
        $tarDetails = (& tar -tzvf $unixArchive | Out-String)
        Assert-True ($tarDetails -match '(?m)^-rwx[^\r\n]*SaF-YTDLP\.sh\r?$') 'Unix launcher is not executable in the release archive.'
        $unixConfig = (& tar -xOf $unixArchive config.ini | Out-String)
        $unixExtractRoot = Join-Path $caseRoot 'unix-extracted'
        New-Item -ItemType Directory -Path $unixExtractRoot | Out-Null
        & tar -xzf $unixArchive -C $unixExtractRoot config.ini
        Assert-True ($LASTEXITCODE -eq 0) 'Could not extract the Unix release configuration.'
        $unixConfigBytes = [IO.File]::ReadAllBytes((Join-Path $unixExtractRoot 'config.ini'))
        Assert-True (-not ($unixConfigBytes -contains 13)) 'Unix release config.ini uses CRLF instead of LF line endings.'
        foreach ($archivedConfig in @($windowsConfig, $unixConfig)) {
            Assert-True ($archivedConfig -match '(?m)^PROFILE=MODERN\r?$') 'Release PROFILE default is not MODERN.'
            Assert-True ($archivedConfig -match '(?m)^MAX_HEIGHT=1080\r?$') 'Release height default is not 1080p.'
            Assert-True ($archivedConfig -match '(?m)^ALLOW_HARDWARE_TRANSCODING=YES\r?$') 'Release hardware transcoding is disabled.'
            Assert-True ($archivedConfig -match '(?m)^DOWNLOAD_ALL_AUDIO_TRACKS=YES\r?$') 'Release multitrack downloading is disabled.'
            Assert-True ($archivedConfig -match '(?m)^COOKIE_BROWSER=\r?$') 'Release contains a saved browser.'
            Assert-True ($archivedConfig -notmatch 'COOKIE_BROWSER=zen') 'Release contains the working browser selection.'
        }
    } finally {
        Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Invalid profile stops before downloading' {
    $config = "PROFILE=FASTEST`r`nMAX_HEIGHT=0`r`nDEFAULT_MODE=video`r`nTRANSCODE_VP9_TO_AV1=YES`r`nALLOW_HARDWARE_TRANSCODING=NO"
    $result = Invoke-Scenario -Config $config -InputLines @('https://example.test/video')
    Assert-True ($result.ExitCode -ne 0) 'Invalid PROFILE unexpectedly succeeded.'
    Assert-True ($result.Output -match 'Invalid PROFILE') "Helpful profile error was missing. Output: $($result.Output)"
    Assert-True ([string]::IsNullOrWhiteSpace($result.Arguments)) 'Download started despite invalid profile.'
}

Write-Host ""
Write-Host "$($script:passed) passed, $($script:failed) failed"
Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failed -gt 0) {
    exit 1
}

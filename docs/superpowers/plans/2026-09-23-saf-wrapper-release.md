# Simple and Flexible yt-dlp Wrapper Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean and simplify the Windows wrapper, add Windows ARM64 support, reproduce the completed behavior in one Bash script for Linux and macOS on x86_64 and ARM64, and produce a release-ready repository.

**Architecture:** Keep the product as two self-contained launchers, `SaF-YTDLP.cmd` and `SaF-YTDLP.sh`, which share `config.ini` and the same user-visible behavior but use platform-native commands internally. Runtime dependencies live directly in `internal/dependencies/`; each run uses an isolated directory below `internal/temp/`, and completed media is published collision-safely to `Downloads/`. Finish and verify Windows first, then use its tests and behavior as the contract for Bash.

**Tech Stack:** Windows CMD, PowerShell 5.1, Bash 3.2+, yt-dlp, Deno, FFmpeg/FFprobe, C# test doubles compiled by the Windows PowerShell harness, shell test doubles for Linux/macOS, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-23-saf-wrapper-release-design.md`

## Global Constraints

- The product name is **Simple and Flexible yt-dlp Wrapper**, shortened to **SaF yt-dlp Wrapper**.
- Keep the Windows implementation in one `SaF-YTDLP.cmd` file and the Unix implementation in one `SaF-YTDLP.sh` file.
- Do not begin Bash implementation until the cleaned Windows implementation passes its complete automated suite and Windows smoke checks.
- The supported targets are Windows 10/11 x86_64 and ARM64, Linux x86_64 and ARM64, and macOS Intel x86_64 and Apple Silicon ARM64.
- The wrapper is designed and tested for YouTube videos and playlists; other URLs may pass through to yt-dlp but are unsupported.
- Runtime files may exist only below `internal/dependencies/` and `internal/temp/`; completed media may exist only below `Downloads/`.
- Keep dependency executables directly in `internal/dependencies/`; do not add `bin`, `state`, `work`, or per-tool runtime subdirectories.
- Do not add a helper PowerShell script, Python runtime, Node runtime, persistent log, state JSON, or failed-processing journal.
- Temporary metadata JSON is allowed only inside the active job directory and must be removed with that job.
- Preserve source media after any download, publishing, or conversion failure, and never overwrite an existing file in `Downloads/`.
- `MODERN` source preference at equal resolution and frame rate is `H.265 > H.264 > AV1 > VP9 > other`; resolution and frame rate remain higher priorities.
- `DOWNLOAD_ALL_AUDIO_TRACKS=YES` retains one best audio stream for every language exposed by YouTube in every media-download mode.
- Release defaults are exactly `PROFILE=MODERN`, `MAX_HEIGHT=1080`, `DEFAULT_MODE=video`, `TRANSCODE_VP9_TO_AV1=YES`, `ALLOW_HARDWARE_TRANSCODING=YES`, `STORE_OPUS_IN_MP4=YES`, `DOWNLOAD_ALL_AUDIO_TRACKS=YES`, and an empty `COOKIE_BROWSER`.
- Credit the project as `Code by ChatGPT 5.6 Sol (High). Project management by the project author.`
- Preserve every existing user file under `Downloads/` during development and cleanup.
- Make changes test-first, run focused tests after each implementation step, run the entire applicable suite before each task commit, and keep unrelated working-tree changes out of each commit.

## Review Focus

- A repository path, media filename, or playlist title containing spaces, Unicode, `%`, `!`, `&`, parentheses, or leading dashes must reach yt-dlp, FFprobe, FFmpeg, and `Downloads/` unchanged; Tasks 2, 5, and 10 add explicit tests.
- An interrupted or invalid dependency download must leave the previous executable untouched and remove the `.part` file; Tasks 6 and 8 add replacement-failure tests.
- A corrupt, incomplete, or bitrate-less FFprobe response must not cause arithmetic on empty values or delete source media; Tasks 5 and 10 add malformed-probe and packet-fallback tests.
- A stale saved browser, a locked browser database, or a failed cookie simulation must continue through the fixed browser list and finally run cookie-free without corrupting `config.ini`; Tasks 3 and 9 add these tests.
- A partial playlist failure or failed conversion must not block later entries, overwrite an earlier output, or leave a permanent queue; Tasks 2 and 10 add mixed-success playlist tests.

---

## File Map

- `SaF-YTDLP.cmd`: complete Windows product, including setup, selection, download, post-processing, publishing, and cleanup.
- `SaF-YTDLP.sh`: complete Linux/macOS product with behavior matching the finished CMD.
- `config.ini`: shared release configuration with platform-neutral defaults.
- `README.md`: user-facing installation, usage, profiles, configuration, supported systems, cookies, troubleshooting, development credit, and license.
- `build-release.ps1`: creates both release archives with a generated default configuration while leaving the working `config.ini` untouched.
- `.gitignore`: ignores `internal/`, `Downloads/`, and `dist/`.
- `.gitattributes`: enforces CRLF for CMD/PowerShell and LF for Bash, Markdown, INI, C#, and YAML.
- `tests/run-tests.ps1`: Windows integration harness and release-config assertions.
- `tests/FakeYtdlp.cs`: deterministic yt-dlp double used by Windows integration tests.
- `tests/FakeFfmpeg.cs`: deterministic FFmpeg and FFprobe double used by Windows integration tests.
- `tests/FakeYtdlp.sh`: deterministic yt-dlp double used by Bash integration tests.
- `tests/FakeFfmpeg.sh`: deterministic FFmpeg and FFprobe double used by Bash integration tests.
- `tests/run-bash-tests.sh`: Linux/macOS integration harness and Windows/Bash parity cases.
- `.github/workflows/test.yml`: Windows, Ubuntu, and macOS automated test matrix.
- `dist/SaF-yt-dlp-Wrapper-Windows.zip`: generated Windows release archive, ignored by Git.
- `dist/SaF-yt-dlp-Wrapper-Unix.tar.gz`: generated Linux/macOS release archive, ignored by Git.

### Task 1: Pin the test baseline and release configuration

**Files:**
- Modify: `tests/run-tests.ps1`
- Modify: `config.ini`
- Modify: `SaF-YTDLP.cmd`

**Interfaces:**
- Consumes: partial per-scenario INI text supplied to `Invoke-Scenario`.
- Produces: `$script:testConfigDefaults`, a complete single-track test baseline; exact assertions for the root release `config.ini`.

- [ ] **Step 1: Add a complete test-only baseline without changing existing scenario intent**

Insert this before `Invoke-Scenario` and write the combined value to each fixture config so existing tests that intentionally exercise single-track behavior do not inherit the new release default:

```powershell
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

$fixtureConfig = $script:testConfigDefaults.TrimEnd() + "`r`n" + $Config.Trim() + "`r`n"
Set-Content -LiteralPath (Join-Path $caseRoot 'config.ini') -Value $fixtureConfig -Encoding ascii
```

- [ ] **Step 2: Add failing tests for the exact release defaults and native AV1 preference**

Add this case before scenario tests:

```powershell
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
        Assert-True ($releaseConfig -match ('(?m)^' + [regex]::Escape($line) + '$')) "Missing release default: $line"
    }
    Assert-True ($releaseConfig -match '(?m)^COOKIE_BROWSER=$') 'Release config contains a personal browser selection.'
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
```

- [ ] **Step 3: Run the Windows suite and verify only the release-default test fails**

Run:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
```

Expected: the existing 70 cases remain green; the release-default test fails on `PROFILE`, `MAX_HEIGHT`, or `COOKIE_BROWSER`, and the QUALITY regression selects format `625` instead of `401`.

- [ ] **Step 4: Replace `config.ini` defaults and make QUALITY prefer ready AV1**

The effective settings must be exactly:

```ini
PROFILE=MODERN
MAX_HEIGHT=1080
DEFAULT_MODE=video
TRANSCODE_VP9_TO_AV1=YES
ALLOW_HARDWARE_TRANSCODING=YES
STORE_OPUS_IN_MP4=YES
DOWNLOAD_ALL_AUDIO_TRACKS=YES
COOKIE_BROWSER=
```

For the normal QUALITY path, pass `-S res,fps,vcodec:av1` before the existing format selector. In the multilingual metadata selector, rank AV1 above other codecs for QUALITY before quality and bitrate tie-breakers. Do not lower resolution or frame rate to obtain AV1; do not change the remaining non-AV1 ordering.

- [ ] **Step 5: Run the full Windows suite**

Run the command from Step 3.

Expected: `72 passed, 0 failed`; the Rick Astley metadata fixture selects native AV1 and never selects the equivalent VP9 format.

- [ ] **Step 6: Commit the baseline and defaults**

```powershell
git add -- config.ini SaF-YTDLP.cmd tests/run-tests.ps1
git commit -m "fix: prefer native AV1 in Quality profile"
```

### Task 2: Move Windows runtime data under `internal/` and simplify failure cleanup

**Files:**
- Modify: `SaF-YTDLP.cmd`
- Modify: `tests/run-tests.ps1`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: repository root and one URL per interactive cycle.
- Produces: `INTERNAL`, `DEPENDENCIES`, `TEMP_ROOT`, and unique `JOB_ROOT`; successful output in `Downloads/`; no persistent queue.

- [ ] **Step 1: Change fixture paths and add failing layout assertions**

Replace fixture dependency paths with:

```powershell
$dependencyDirectory = Join-Path $caseRoot 'internal\dependencies'
$tempDirectory = Join-Path $caseRoot 'internal\temp'
New-Item -ItemType Directory -Path $dependencyDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null
$fakeYtdlp = Join-Path $dependencyDirectory 'yt-dlp.exe'
$fakeDeno = Join-Path $dependencyDirectory 'deno.exe'
$fakeFfmpeg = Join-Path $dependencyDirectory 'ffmpeg.exe'
$fakeFfprobe = Join-Path $dependencyDirectory 'ffprobe.exe'
```

Return these fields from `Invoke-Scenario` before fixture deletion:

```powershell
InternalFiles = @(Get-ChildItem -LiteralPath (Join-Path $caseRoot 'internal') -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
TempEntries = @(Get-ChildItem -LiteralPath (Join-Path $caseRoot 'internal\temp') -Force -ErrorAction SilentlyContinue)
ToolsExists = Test-Path -LiteralPath (Join-Path $caseRoot '.tools')
```

Add these tests:

```powershell
Test-Case 'Runtime files stay below internal and completed media stays below Downloads' {
    $result = Invoke-Scenario -Config 'PROFILE=QUALITY' -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -MediaName 'space %! & (name).mp4'
    Assert-True (-not $result.ToolsExists) 'The obsolete .tools directory was created.'
    Assert-True ($result.TempEntries.Count -eq 0) 'The completed job left temporary files behind.'
    Assert-True ($result.PublishedFiles.ContainsKey('space %! & (name).mp4')) 'The media filename changed while publishing.'
}

Test-Case 'Failed conversion publishes its source and leaves no permanent queue' {
    $result = Invoke-Scenario -Config 'PROFILE=MODERN' -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -FailInputContains 'failed.webm' -MediaName 'failed.webm'
    Assert-True ($result.PublishedFiles.ContainsKey('failed.webm')) 'The failed source was not preserved in Downloads.'
    Assert-True (-not ($result.InternalFiles -match 'queue|failed|\.json$')) 'A permanent queue or JSON state file remained.'
}
```

- [ ] **Step 2: Run the two new cases and verify they fail on `.tools` paths or missing source publication**

Run the full PowerShell suite and confirm the failure messages match the assertions above.

- [ ] **Step 3: Replace global runtime paths and create one isolated job directory per URL**

Use these root variables near the start of `SaF-YTDLP.cmd`:

```bat
set "ROOT=%CD%"
set "INTERNAL=%ROOT%\internal"
set "DEPENDENCIES=%INTERNAL%\dependencies"
set "TEMP_ROOT=%INTERNAL%\temp"
set "DOWNLOADS=%ROOT%\Downloads"
set "CONFIG=%ROOT%\config.ini"
set "YTDLP=%DEPENDENCIES%\yt-dlp.exe"
set "DENO=%DEPENDENCIES%\deno.exe"
set "FFMPEG=%DEPENDENCIES%\ffmpeg.exe"
set "FFPROBE=%DEPENDENCIES%\ffprobe.exe"
```

At startup, create the three directories and clean only `%TEMP_ROOT%`. In `:prepare_download_job`, create `%TEMP_ROOT%\job-<GUID>`, then place downloads, metadata, selections, the per-job file list, probe output, FFmpeg outputs, and pass logs below that directory.

- [ ] **Step 4: Replace the persistent failed queue with direct source publication**

Keep the per-job UTF-8 file list needed for safe Batch filenames. If `:process_download` fails, call the same collision-safe publisher with the untouched input path, print `Conversion failed; the downloaded source was kept.`, continue later playlist entries, and never create `postprocess.failed.queue`.

- [ ] **Step 5: Make job cleanup explicit on success, failure, and blank exit**

Add one `:cleanup_job` label that removes only the resolved `%JOB_ROOT%` below `%TEMP_ROOT%`. Call it after publication and before returning to `:ask_url`. Stale directories below `%TEMP_ROOT%` are removed on the next normal startup.

- [ ] **Step 6: Replace `.gitignore` contents**

```gitignore
internal/
Downloads/
dist/
```

- [ ] **Step 7: Run the full Windows suite**

Expected: all existing cases plus the two new layout/failure cases pass; no fixture creates `.tools`, permanent JSON, or a failed queue.

- [ ] **Step 8: Commit the runtime layout**

```powershell
git add -- .gitignore SaF-YTDLP.cmd tests/run-tests.ps1
git commit -m "refactor: contain Windows runtime files"
```

### Task 3: Simplify Windows browser-cookie discovery

**Files:**
- Modify: `SaF-YTDLP.cmd`
- Modify: `tests/run-tests.ps1`

**Interfaces:**
- Consumes: optional `COOKIE_BROWSER` and platform browser profiles.
- Produces: `COOKIE_SOURCE` after successful simulation, an atomically updated `COOKIE_BROWSER`, or an empty source for a cookie-free download.

- [ ] **Step 1: Replace default-browser tests with fixed-order tests**

Delete the fake `reg.cmd`, `DefaultBrowserProgId`, and smart/default-browser assertions. Add tests with these expectations:

```powershell
Test-Case 'Saved browser is simulated first and a stale value falls through fixed order' {
    $result = Invoke-Scenario -Config "COOKIE_BROWSER=firefox" -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -CookieSuccess 'edge'
    $sources = [regex]::Matches($result.Arguments, 'ARG=\[--cookies-from-browser\]\r?\nARG=\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value }
    Assert-True (($sources | Select-Object -First 3) -join ',' -eq 'firefox,chrome,edge') "Unexpected browser order: $($sources -join ',')"
    Assert-True ($result.Config -match '(?m)^COOKIE_BROWSER=edge$') 'The successful fallback was not remembered.'
}

Test-Case 'All failed browser simulations lead to one cookie-free download' {
    $result = Invoke-Scenario -Config 'COOKIE_BROWSER=chrome' -InputLines @('https://example.test/video', '') -VideoCodec 'h264' -AudioCodec 'aac' -CookieSuccess 'never'
    Assert-True ($result.Output -match 'continuing without browser cookies') 'Cookie-free fallback was not reported.'
    Assert-True ($result.Arguments -match 'ARG=\[-f\]') 'The media download was not attempted.'
}
```

Retain focused Comet tests for `Default\Cookies`, `Default\Network\Cookies`, multiple profiles, and newest valid profile, plus the Zen profile-path test.

- [ ] **Step 2: Run the focused cookie cases and confirm they fail because default-browser detection still changes the order**

Run:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
```

- [ ] **Step 3: Delete `:detect_default_browser` and all `SMART_BROWSER_*` variables**

Use this candidate order inside `:select_cookie_source`:

```text
saved browser, chrome, edge, firefox, opera, brave, vivaldi, discovered Comet profile, Zen profile
```

Every candidate, including the saved browser, goes through `:probe_cookie_source`; the `COOKIE_TRIED_*` flags prevent duplicate probes.

- [ ] **Step 4: Keep only two custom profile resolvers**

Keep `:resolve_comet_cookie_source` for its newest-profile discovery. Map Zen directly to `firefox:%APPDATA%\zen\Profiles`. Remove Windows registry access entirely.

- [ ] **Step 5: Keep config persistence atomic**

Write `config.ini.saf-new`, replace only the `COOKIE_BROWSER=` line, then move the temporary file over `config.ini`. On any write failure, retain the original config and continue the current download with the already selected cookie source.

- [ ] **Step 6: Run the complete Windows suite**

Expected: all cookie-order, Comet, Zen, stale-value, cookie-free, and existing download cases pass; the CMD contains no `reg query` or `SMART_BROWSER` reference.

- [ ] **Step 7: Commit cookie simplification**

```powershell
git add -- SaF-YTDLP.cmd tests/run-tests.ps1
git commit -m "refactor: simplify browser cookie selection"
```

### Task 4: Implement H.265-first Modern selection and normalize codecs once

**Files:**
- Modify: `SaF-YTDLP.cmd`
- Modify: `tests/run-tests.ps1`

**Interfaces:**
- Consumes: yt-dlp codec strings and FFprobe codec names.
- Produces: normalized `H264`, `H265`, `VP9`, `AV1`, or `OTHER`; Modern ordering `H265=4`, `H264=3`, `AV1=2`, `VP9=1`, `OTHER=0`.

- [ ] **Step 1: Add failing source-order tests for both Modern paths**

Add a normal Modern case and a multitrack Modern case using this metadata:

```powershell
$formats = @{
    id = 'modern-h265-order'
    formats = @(
        @{ format_id = 'vp9'; vcodec = 'vp09.00.51.08'; acodec = 'none'; height = 1080; fps = 30; tbr = 2500 },
        @{ format_id = 'av1'; vcodec = 'av01.0.08M.08'; acodec = 'none'; height = 1080; fps = 30; tbr = 2200 },
        @{ format_id = 'h264'; vcodec = 'avc1.640028'; acodec = 'none'; height = 1080; fps = 30; tbr = 4000 },
        @{ format_id = 'h265'; vcodec = 'hvc1.2.4.L120.B0'; acodec = 'none'; height = 1080; fps = 30; tbr = 3000 }
    )
} | ConvertTo-Json -Depth 5 -Compress
```

Assert `h265+...` is selected, no `libx265` call occurs for native H.265, H.264 wins when the H.265 entry is removed, and a 2160p VP9 format still wins over a 1080p H.265 format.

- [ ] **Step 2: Run the new tests and confirm current Modern selection chooses H.264**

Run the full PowerShell suite.

- [ ] **Step 3: Add one codec-normalization label for post-processing**

Define:

```bat
:normalize_codec
set "%~2=OTHER"
echo(%~1| findstr /i /r "^avc1 ^h264" >nul
if not errorlevel 1 (set "%~2=H264" & exit /b 0)
echo(%~1| findstr /i /r "^hev1 ^hvc1 ^hevc ^h265" >nul
if not errorlevel 1 (set "%~2=H265" & exit /b 0)
echo(%~1| findstr /i /r "^vp09 ^vp9" >nul
if not errorlevel 1 (set "%~2=VP9" & exit /b 0)
echo(%~1| findstr /i /r "^av01 ^av1" >nul
if not errorlevel 1 (set "%~2=AV1" & exit /b 0)
exit /b 0
```

Call it once for the source video codec and once for each decision input; profile-selection labels compare normalized values only.

- [ ] **Step 4: Update both PowerShell metadata selectors**

Use the same ranking expression in normal Modern and multitrack selection:

```powershell
$codec = [string]$_.vcodec
if ($codec -match '^(hev1|hvc1|hevc|h265)') { 4 }
elseif ($codec -match '^(avc1|h264)') { 3 }
elseif ($codec -match '^(av01|av1)') { 2 }
elseif ($codec -match '^(vp09|vp9)') { 1 }
else { 0 }
```

- [ ] **Step 5: Make Modern post-processing keep native H.265 and compatible H.264**

`H265` selects stream copy. `H264` selects stream copy after the existing compatibility/pixel-format check. `AV1`, `VP9`, and `OTHER` target H.265. Leave QUALITY and UNIVERSAL policies unchanged.

- [ ] **Step 6: Run the entire Windows suite**

Expected: both selectors choose H.265 first, H.264 second, resolution and FPS still win first, and existing QUALITY/UNIVERSAL cases remain green.

- [ ] **Step 7: Commit the codec policy**

```powershell
git add -- SaF-YTDLP.cmd tests/run-tests.ps1
git commit -m "feat: prefer native H265 in Modern profile"
```

### Task 5: Consolidate media inspection and duplicated audio arguments

**Files:**
- Modify: `SaF-YTDLP.cmd`
- Modify: `tests/FakeFfmpeg.cs`
- Modify: `tests/run-tests.ps1`

**Interfaces:**
- Consumes: one downloaded media path.
- Produces: `SOURCE_VIDEO_CODEC`, `SOURCE_VIDEO_BITRATE`, `SOURCE_VIDEO_HEIGHT`, `SOURCE_PIXEL_FORMAT`, `SOURCE_AUDIO_CODECS`, and shared audio-download arguments.

- [ ] **Step 1: Teach the fake FFprobe to return one JSON media description**

When arguments contain `-show_entries stream=index,codec_type,codec_name,pix_fmt,height,bit_rate:format=duration -of json`, emit:

```csharp
Console.WriteLine("{\"streams\":[{\"index\":0,\"codec_type\":\"video\",\"codec_name\":\""
    + (Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_CODEC") ?? "vp9")
    + "\",\"pix_fmt\":\"" + (Environment.GetEnvironmentVariable("SAF_FAKE_PIX_FMT") ?? "yuv420p")
    + "\",\"height\":" + (Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_HEIGHT") ?? "1080")
    + ",\"bit_rate\":\"" + (Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_BITRATE") ?? "8000000")
    + "\"},{\"index\":1,\"codec_type\":\"audio\",\"codec_name\":\""
    + (Environment.GetEnvironmentVariable("SAF_FAKE_ACTUAL_AUDIO_CODEC") ?? "opus")
    + "\"}],\"format\":{\"duration\":\"" + (Environment.GetEnvironmentVariable("SAF_FAKE_DURATION") ?? "10") + "\"}}");
```

Preserve the packet-size response for the bitrate fallback.

- [ ] **Step 2: Add failing probe-count and malformed-probe tests**

Return `FfprobeCalls` by counting `FFPROBE` headers in the fake-tool log. Add:

```powershell
Test-Case 'Normal post-processing inspects media with one FFprobe call' {
    $result = Invoke-Scenario -Config 'PROFILE=MODERN' -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -VideoBitrate '8000000'
    Assert-True ($result.FfprobeCalls -eq 1) "Expected one normal FFprobe call, got $($result.FfprobeCalls)."
}

Test-Case 'Missing bitrate uses exactly one packet fallback and keeps the source on malformed data' {
    $result = Invoke-Scenario -Config 'PROFILE=MODERN' -InputLines @('https://example.test/video', '') -VideoCodec 'vp9' -VideoBitrate '' -VideoPacketSizes 'invalid'
    Assert-True ($result.FfprobeCalls -eq 2) "Expected inspection plus packet fallback, got $($result.FfprobeCalls)."
    Assert-True ($result.PublishedFiles.ContainsKey('sample.webm')) 'Malformed probe data caused source loss.'
}
```

- [ ] **Step 3: Run the new cases and confirm repeated FFprobe calls fail the count**

Run the full PowerShell suite.

- [ ] **Step 4: Replace individual probe labels with `:inspect_media`**

Run FFprobe once into `%JOB_ROOT%\probe.json`, then use one PowerShell parse to write a tab-separated `%JOB_ROOT%\probe.txt` containing video codec, height, bit rate, pixel format, duration, and comma-separated audio codecs. Parse that one line into the six interface variables. Only call `:estimate_video_bitrate` when the parsed stream bit rate is empty or non-positive.

- [ ] **Step 5: Collapse audio-only profile branches into one argument builder**

Define `:set_audio_download_arguments` with these exact outputs:

```text
QUALITY + STORE_OPUS_IN_MP4=NO -> selector ba/b, format best, no remux override
QUALITY + STORE_OPUS_IN_MP4=YES -> selector ba/b, format best, remux opus>mp4
MODERN -> selector ba[acodec^=mp4a]/ba/b[acodec^=mp4a]/b, format m4a, quality 0
UNIVERSAL -> selector ba/b, format mp3, quality 0
```

Use the resulting variables in both single-track and multitrack audio-only code instead of maintaining separate profile command trees.

- [ ] **Step 6: Reorder the CMD into the eight approved sections without changing public behavior**

Add short `rem === ... ===` separators for startup/configuration, dependencies, cookies, menus/downloads, format/audio selection, inspection/post-processing, publishing/cleanup, and utilities. Keep the bitrate table, encoder-specific options, metadata selection, and per-entry CMD relaunch explicit.

- [ ] **Step 7: Run focused special-character cases and the full Windows suite**

Run the full suite and specifically verify the `%USERNAME%`, Japanese UTF-8, `space %! & (name).mp4`, packet fallback, multitrack, and CPU/hardware fallback cases.

- [ ] **Step 8: Commit the Windows cleanup**

```powershell
git add -- SaF-YTDLP.cmd tests/FakeFfmpeg.cs tests/run-tests.ps1
git commit -m "refactor: simplify Windows media processing"
```

### Task 6: Add Windows ARM64 dependency selection and atomic installation

**Files:**
- Modify: `SaF-YTDLP.cmd`
- Modify: `tests/FakeYtdlp.cs`
- Modify: `tests/run-tests.ps1`

**Interfaces:**
- Consumes: effective Windows architecture from `PROCESSOR_ARCHITECTURE`/`PROCESSOR_ARCHITEW6432`.
- Produces: `PLATFORM_ID=windows-x64` or `windows-arm64` and exact yt-dlp, Deno, and FFmpeg URLs; validated executables in `internal/dependencies/`.

- [ ] **Step 1: Add an internal dependency-map probe used only by tests**

Support `SaF-YTDLP.cmd --internal-dependency-map` before normal setup. It calls architecture detection and prints exactly:

```text
PLATFORM=<platform id>
YTDLP_URL=<url>
DENO_URL=<url>
FFMPEG_URL=<url>
```

It must not create directories, download files, update yt-dlp, or read `config.ini`.

- [ ] **Step 2: Add failing x64, ARM64, and unsupported-architecture tests**

Launch the internal probe with temporary environment values and assert these mappings:

```text
windows-x64:
  yt-dlp.exe
  deno-x86_64-pc-windows-msvc.zip
  ffmpeg-master-latest-win64-gpl.zip
windows-arm64:
  yt-dlp_arm64.exe
  deno-aarch64-pc-windows-msvc.zip
  ffmpeg-master-latest-winarm64-gpl.zip
```

Assert `x86` exits nonzero with `supports Windows x86_64 and ARM64` before any download attempt.

- [ ] **Step 3: Run the dependency-map cases and confirm ARM64 fails**

Run the full PowerShell suite.

- [ ] **Step 4: Implement `:select_windows_dependencies`**

Use these URL bases and asset names:

```text
https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/
https://github.com/denoland/deno/releases/latest/download/
https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/
```

Recognize `AMD64` and `ARM64`, including native architecture reported through `PROCESSOR_ARCHITEW6432`; reject every other value.

- [ ] **Step 5: Make every dependency installation and yt-dlp update atomic**

Download to `%JOB_SETUP%\<asset>.part`, extract archives below `%JOB_SETUP%`, copy candidate executables to sibling `.new` paths, run each candidate with `--version`, and only then move it over the final dependency path. If download, extraction, or validation fails, delete the setup job and leave existing executables untouched.

Validate FFprobe with `ffprobe -version`. Validate FFmpeg with `ffmpeg -hide_banner -encoders` and require the software encoders `libx264`, `libx265`, and `libsvtav1`; hardware encoders remain optional and are probed only when processing media.

For the normal yt-dlp update, copy the current executable to `yt-dlp.exe.new`, run `yt-dlp.exe.new --update-to nightly`, validate `yt-dlp.exe.new --version`, and replace `yt-dlp.exe` only after both commands succeed. An update failure prints the existing warning and continues with the untouched executable.

- [ ] **Step 6: Add failed-update and interrupted-download tests**

Extend `FakeYtdlp.cs` so `--version` returns `SAF_FAKE_VERSION_EXIT`. Seed a working `yt-dlp.exe`, set `SAF_FAKE_UPDATE_EXIT=1`, and assert its original hash is unchanged, `yt-dlp.exe.new` is absent, and the interactive loop still starts. Add the internal test variable `SAF_TEST_DOWNLOAD_FAILURE=YES` to make `:download_file` fail after creating its `.part` target; assert the final dependency is absent, the `.part` file is removed, and setup exits nonzero.

- [ ] **Step 7: Run the complete Windows suite**

Expected: x64 and ARM64 mappings pass, unsupported architectures stop early, atomic failure preserves the old binary, and all download/profile behavior remains green.

- [ ] **Step 8: Commit Windows platform support**

```powershell
git add -- SaF-YTDLP.cmd tests/FakeYtdlp.cs tests/run-tests.ps1
git commit -m "feat: support Windows ARM64 dependencies"
```

### Task 7: Complete and verify the Windows implementation gate

**Files:**
- Modify if verification exposes a defect: `SaF-YTDLP.cmd`
- Modify if a regression needs coverage: `tests/run-tests.ps1`, `tests/FakeYtdlp.cs`, `tests/FakeFfmpeg.cs`

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: the frozen Windows behavioral contract that Bash must duplicate.

- [ ] **Step 1: Run static repository checks**

Run:

```powershell
rg -n "\.tools|postprocess\.failed|reg query|SMART_BROWSER|Windows x64 only" -- SaF-YTDLP.cmd config.ini .gitignore
git diff --check
```

Expected: no obsolete runtime path, persistent queue, registry browser detection, smart-browser state, or x64-only message; no whitespace errors.

- [ ] **Step 2: Run the full Windows integration suite twice**

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
```

Expected: identical pass totals and `0 failed` both times, proving no stale temp state leaks between runs.

- [ ] **Step 3: Run an isolated first-start smoke test**

Copy `SaF-YTDLP.cmd` and `config.ini` to a fresh temporary directory, start it, allow it to download x64 dependencies, submit a blank URL, and verify:

```text
internal/dependencies/yt-dlp.exe
internal/dependencies/deno.exe
internal/dependencies/ffmpeg.exe
internal/dependencies/ffprobe.exe
internal/temp/ is empty
Downloads/ exists
```

- [ ] **Step 4: Run real YouTube video smoke cases in the isolated directory**

Use `https://www.youtube.com/watch?v=BaW_jenozKc`. Verify thumbnail mode, default 1080p Modern video, audio-only mode, multitrack selection when languages are available, native H.264 stream copy, one forced CPU conversion, and one available hardware conversion. If the host exposes no compatible hardware encoder, record the successful probe failures and CPU fallback rather than treating absent hardware as a product failure.

- [ ] **Step 5: Run playlist behavior through the deterministic suite and one small real playlist**

The fake integration suite must cover completed-entry processing after partial failure, skipped video-less entries, multilingual per-entry selection, collision suffixes, and continued processing after conversion failure. For the live check, submit `https://www.youtube.com/playlist?list=PLwiyx1dc3P2JR9N8gQaQN_BCvlSlap7re` in thumbnail mode inside the isolated smoke directory; verify playlist extraction, ordered names, publication, and cleanup without downloading video streams.

- [ ] **Step 6: Inspect Windows changes for unnecessary complexity**

Count lines, labels, and embedded PowerShell calls; verify every remaining PowerShell block is used for archive handling, JSON parsing, atomic config updates, or Unicode-safe file operations. Remove any duplicate branch that has no distinct tested behavior.

- [ ] **Step 7: Commit any verification fixes, then freeze the Windows checkpoint**

```powershell
git add -- SaF-YTDLP.cmd tests/run-tests.ps1 tests/FakeYtdlp.cs tests/FakeFfmpeg.cs
git commit -m "fix: complete Windows release verification"
```

If Step 6 requires no edits, do not create an empty commit. Record the passing commit hash before Task 8. **Tasks 8-11 must not begin until every step in Task 7 passes.**

### Task 8: Add Bash startup, configuration, dependency installation, and tests

**Files:**
- Create: `SaF-YTDLP.sh`
- Create: `tests/FakeYtdlp.sh`
- Create: `tests/FakeFfmpeg.sh`
- Create: `tests/run-bash-tests.sh`
- Modify: `.gitattributes`

**Interfaces:**
- Consumes: the frozen Windows contract, `config.ini`, `uname -s`, and `uname -m`.
- Produces: the same directory layout and configuration validation; dependency maps for Linux/macOS x86_64/ARM64.

- [ ] **Step 1: Create a Bash test runner with isolated fixtures**

Start `tests/run-bash-tests.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail

passed=0
failed=0
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

run_test() {
  local name=$1
  shift
  if "$@"; then
    printf 'PASS %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s\n' "$name" >&2
    failed=$((failed + 1))
  fi
}
```

`run_scenario` must create a fresh directory with `internal/dependencies`, copy the launcher and config, install the two shell fakes as `yt-dlp`, `deno`, `ffmpeg`, and `ffprobe`, feed input through stdin, capture output/arguments, and remove the fixture through `trap`.

- [ ] **Step 2: Create executable shell fakes with the Windows environment contract**

`tests/FakeYtdlp.sh` must handle `--update-to`, `--version`, `--simulate`, `--dump-single-json`, `--playlist-items`, `--print-to-file`, media creation, cookie-specific failures, second playlist media, and configurable exit codes using the existing `SAF_FAKE_*` names.

`tests/FakeFfmpeg.sh` must distinguish its basename, emit the same JSON inspection and packet sizes as the C# fake, log every argument one per line, probe `lavfi` hardware encoders, fail a selected encoder/input, and create the final output file on success.

- [ ] **Step 3: Add failing Bash tests for config validation and all four Unix dependency maps**

Assert these exact assets:

```text
linux-x64:
  yt-dlp_linux
  deno-x86_64-unknown-linux-gnu.zip
  ffmpeg-master-latest-linux64-gpl.tar.xz
linux-arm64:
  yt-dlp_linux_aarch64
  deno-aarch64-unknown-linux-gnu.zip
  ffmpeg-master-latest-linuxarm64-gpl.tar.xz
macos-x64:
  yt-dlp_macos
  deno-x86_64-apple-darwin.zip
  ffmpeg-darwin-x64.gz and ffprobe-darwin-x64.gz
macos-arm64:
  yt-dlp_macos
  deno-aarch64-apple-darwin.zip
  ffmpeg-darwin-arm64.gz and ffprobe-darwin-arm64.gz
```

Also assert unsupported OS/architecture combinations fail before creating runtime files.

- [ ] **Step 4: Run the Bash tests and confirm the missing launcher fails**

On Windows use the bundled Git Bash executable; on Unix use `bash`:

```powershell
& 'C:\Users\aspirata\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\usr\bin\bash.exe' tests/run-bash-tests.sh
```

Expected: tests fail because `SaF-YTDLP.sh` does not exist.

- [ ] **Step 5: Implement Bash startup, config parsing, and internal dependency-map mode**

Use Bash 3.2-compatible syntax, `set -u`, quoted arrays, and `case`. Validate the same eight settings and accepted values as CMD. `--internal-dependency-map` prints the same four keys as Windows without creating files.

- [ ] **Step 6: Implement atomic Unix dependency installation**

Use `curl -fL --retry 3`, `.part` files, per-setup temp directories, `unzip` for Deno, `tar -xJf` for Linux FFmpeg, and `gzip -dc` for the two macOS binaries. Apply `chmod +x`, validate each candidate with `--version`, then `mv` it over the final dependency. Preserve a working executable on every failure.

Validate FFprobe with `ffprobe -version`. Validate FFmpeg by parsing `ffmpeg -hide_banner -encoders` and requiring `libx264`, `libx265`, and `libsvtav1` on Linux and macOS. Do not require VideoToolbox, NVENC, QSV, VAAPI, or AMF because hardware encoding is opportunistic.

Update yt-dlp by copying the current executable to `yt-dlp.new`, running `yt-dlp.new --update-to nightly`, validating `yt-dlp.new --version`, and atomically replacing `yt-dlp` only after both commands succeed. Add a Bash failure test that compares the original hash and confirms `yt-dlp.new` and every `.part` file are removed.

Use these sources:

```text
yt-dlp: https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/
Deno: https://github.com/denoland/deno/releases/latest/download/
Linux FFmpeg: https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/
macOS FFmpeg/FFprobe: https://github.com/eugeneware/ffmpeg-static/releases/latest/download/
```

- [ ] **Step 7: Set line endings and executable mode**

Write `.gitattributes` as:

```gitattributes
*.cmd text eol=crlf
*.ps1 text eol=crlf
*.sh text eol=lf
*.md text eol=lf
*.ini text eol=lf
*.cs text eol=lf
*.yml text eol=lf
```

Then run:

```powershell
git update-index --add --chmod=+x SaF-YTDLP.sh tests/FakeYtdlp.sh tests/FakeFfmpeg.sh tests/run-bash-tests.sh
```

- [ ] **Step 8: Run Windows and Bash suites**

Expected: all Windows tests remain green; Bash startup, validation, directory, atomic-install, and six-platform mapping cases pass.

- [ ] **Step 9: Commit the Bash foundation**

```powershell
git add -- .gitattributes SaF-YTDLP.sh tests/FakeYtdlp.sh tests/FakeFfmpeg.sh tests/run-bash-tests.sh
git commit -m "feat: add portable Bash foundation"
```

### Task 9: Port cookies, interaction, selection, and downloads to Bash

**Files:**
- Modify: `SaF-YTDLP.sh`
- Modify: `tests/FakeYtdlp.sh`
- Modify: `tests/run-bash-tests.sh`

**Interfaces:**
- Consumes: validated configuration, URL, mode, browser profiles, and yt-dlp metadata JSON.
- Produces: the same yt-dlp selectors, cookie behavior, metadata selections, and per-job file list as Windows.

- [ ] **Step 1: Add Bash parity tests for interaction and modes**

Port the Windows assertions for blank exit, Enter selecting `DEFAULT_MODE`, invalid menu retry, video, audio-only, thumbnail-only, repeated interactive URLs, update failure continuation, failed-download return to prompt, collision suffixes, and URL characters `&` and `!`.

- [ ] **Step 2: Add Bash cookie tests for Linux and macOS profile roots**

Cover saved-first fixed ordering, all-failed cookie-free fallback, atomic `COOKIE_BROWSER` persistence, Chrome/Chromium, Firefox, Edge, Brave, Opera, Vivaldi, Comet discovery where present, and Zen's Firefox-compatible profile path. Override `HOME`, `XDG_CONFIG_HOME`, and platform ID inside fixtures; do not read the developer machine's real browser data.

- [ ] **Step 3: Add Bash format-selection tests**

Port the Windows metadata fixtures for:

```text
resolution before FPS before codec
H.265 > H.264 > AV1 > VP9 > other
1080p maximum filtering
playlist entries without video
one best audio stream per language
standalone audio before combined audio
combined-only language retention
language metadata normalization
```

- [ ] **Step 4: Run Bash tests and verify the missing behavior fails**

Run `bash tests/run-bash-tests.sh` and retain the Windows green baseline.

- [ ] **Step 5: Implement the interactive loop and cookie discovery**

Use `IFS= read -r` for URL and mode. Use arrays for yt-dlp arguments. Probe the saved browser first, then the platform's fixed list, then discovered Comet and Zen paths; remember the first simulated success by atomically replacing only `COOKIE_BROWSER=`. If all probes fail, call yt-dlp without `--cookies-from-browser`.

- [ ] **Step 6: Implement metadata selection using the already downloaded Deno**

Use `"$DENO" eval --quiet` with the metadata path and selection output path as explicit arguments. Duplicate the completed Windows rules in JavaScript inside `SaF-YTDLP.sh`; write tab-separated selections in UTF-8. Do not require `jq`, Python, Node, or a helper `.js` file.

- [ ] **Step 7: Implement all download modes and per-entry continuation**

Build quoted Bash arrays for every yt-dlp call. Write completed paths and codec/language fields to the per-job list. Continue processing completed playlist entries after a partial yt-dlp failure and return to the URL prompt after reporting the failure.

- [ ] **Step 8: Run both complete suites**

Expected: the Bash interaction, cookie, H.265 ordering, max-height, multilingual, playlist, and collision tests pass; Windows totals remain unchanged.

- [ ] **Step 9: Commit Bash download behavior**

```powershell
git add -- SaF-YTDLP.sh tests/FakeYtdlp.sh tests/run-bash-tests.sh
git commit -m "feat: port SaF download behavior to Bash"
```

### Task 10: Port post-processing, hardware fallback, and publishing to Bash

**Files:**
- Modify: `SaF-YTDLP.sh`
- Modify: `tests/FakeFfmpeg.sh`
- Modify: `tests/run-bash-tests.sh`

**Interfaces:**
- Consumes: the Bash per-job file list and FFprobe inspection JSON.
- Produces: profile-compliant final media, collision-safe publication, CPU fallback, source preservation, and empty temp storage.

- [ ] **Step 1: Add parity tests for all profile decisions and bitrate rows**

Port the Windows assertions for QUALITY VP9-to-AV1, optional VP9 remux, Modern VP9/AV1-to-H.265, native H.265 copy, native compatible H.264 copy, Universal H.264/AAC output, incompatible H.264 pixel format conversion, multitrack AAC/Opus decisions, all bitrate coefficients, 10% generation margin, hardware 10% margin, and two-pass CPU versus one-pass hardware behavior.

- [ ] **Step 2: Add Unix hardware-candidate tests**

Assert candidate order and fallback:

```text
Linux: NVIDIA NVENC, Intel QSV, then VAAPI when /dev/dri/renderD128 is available
macOS: VideoToolbox for H.264/H.265; CPU for AV1 when no working AV1 hardware encoder exists
all platforms: failed hardware output is discarded and retried once with the matching CPU encoder
```

- [ ] **Step 3: Add path, probe, and playlist failure tests**

Use filenames `space %! & (日本語).webm` and `-leading-dash.webm`. Assert one normal FFprobe call, one extra packet scan only when bitrate is absent, unchanged source publication after malformed probe data, numbered collision output, later playlist-entry completion after an earlier conversion failure, and no remaining temp file list or JSON.

- [ ] **Step 4: Run Bash tests and verify post-processing cases fail**

Run `bash tests/run-bash-tests.sh`.

- [ ] **Step 5: Implement one media-inspection path**

Write FFprobe JSON to the job, parse it with inline Deno, and emit the same six normalized fields as Windows. Run the packet-size fallback only for missing/non-positive video bitrate. Treat malformed required fields as a per-file conversion failure and publish the source.

- [ ] **Step 6: Implement the profile and bitrate tables literally**

Copy the approved coefficient rows and margins as a Bash `case` table. Keep software encoder arguments, hardware encoder arguments, metadata replacement, multitrack language metadata, pass-log paths, and CPU fallback explicit. Do not compress them into generated `eval` strings.

- [ ] **Step 7: Implement collision-safe publishing and job cleanup**

Use quoted paths and `mv --` on Linux; on macOS, avoid GNU-only options by prefixing leading-dash source paths with their absolute job directory. Select `name.ext`, then `name (1).ext`, `name (2).ext`, and later suffixes without overwriting. Install a Bash `trap` that removes only the active job directory.

- [ ] **Step 8: Run Windows and Bash suites twice**

Expected: both suites report `0 failed` on two consecutive runs, all parity cases pass, and no fixture retains temp files.

- [ ] **Step 9: Commit complete Bash parity**

```powershell
git add -- SaF-YTDLP.sh tests/FakeFfmpeg.sh tests/run-bash-tests.sh
git commit -m "feat: complete Bash media processing"
```

### Task 11: Finish documentation, CI, cleanup, and release archives

**Files:**
- Modify: `README.md`
- Create: `build-release.ps1`
- Create: `.github/workflows/test.yml`
- Delete: `SaF YT-DLP Wrapper.zip`
- Local-only migration: `.tools/` to `internal/dependencies/`
- Generate: `dist/SaF-yt-dlp-Wrapper-Windows.zip`
- Generate: `dist/SaF-yt-dlp-Wrapper-Unix.tar.gz`

**Interfaces:**
- Consumes: fully verified CMD/Bash implementations and shared config.
- Produces: understandable documentation, automated platform checks, a clean worktree, and two verified release artifacts.

- [ ] **Step 1: Rewrite README against observed final behavior**

Use these sections in order:

```text
Simple and Flexible yt-dlp Wrapper
What it does
Supported systems
Quick start (Windows)
Quick start (Linux and macOS)
Profiles
Configuration
Multiple audio tracks
Browser cookies
Files and folders
Troubleshooting
Development
License
```

State YouTube-only support, first-run dependency downloads, the exact six platform/architecture targets, default 1080p Modern behavior, H.265/H.264 no-reencode behavior, hardware fallback, all-audio behavior, `internal/dependencies`, `internal/temp`, `Downloads`, unsupported simultaneous runs, and this exact credit:

```text
Code by ChatGPT 5.6 Sol (High). Project management by the project author.
```

- [ ] **Step 2: Add a three-OS CI workflow**

Use this job structure in `.github/workflows/test.yml`:

```yaml
name: test
on:
  push:
  pull_request:

jobs:
  windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - run: powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1

  unix:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/run-bash-tests.sh
```

- [ ] **Step 3: Run documentation and repository checks**

```powershell
rg -n "SaF YT-DLP|\.tools|Windows x64 only|DOWNLOAD_ALL_AUDIO_TRACKS=NO|MAX_HEIGHT=0|prefers native H\.264, then" -- README.md config.ini SaF-YTDLP.cmd SaF-YTDLP.sh .gitignore
git diff --check
```

Expected: no obsolete product wording, path, platform limitation, default, or codec order remains.

- [ ] **Step 4: Migrate reusable local dependencies safely**

Resolve and compare the absolute paths for `.tools` and `internal/dependencies`. Move only validated `yt-dlp`, `deno`, `ffmpeg`, and `ffprobe` executables into `internal/dependencies`, flattening their names to the product layout. Run each with `--version`. Inspect any old failed-queue paths and confirm their source media already exists under `Downloads/`; do not move or delete anything in `Downloads/`.

- [ ] **Step 5: Remove obsolete generated debris**

After Step 4 succeeds, remove the exact resolved `.tools` directory and the exact root file `SaF YT-DLP Wrapper.zip`. Report that these generated artifacts are not recoverable through Git; dependencies can be downloaded again and the release ZIP is regenerated in Step 8.

- [ ] **Step 6: Run all automated and local smoke verification**

Run the Windows suite, Bash suite through Git Bash, `bash -n SaF-YTDLP.sh`, a fresh Windows setup, a Linux x64 setup in an available Linux environment, and macOS x64/ARM64 CI or physical-host smoke runs when those hosts are available. Treat architecture-map tests as mapping verification, not proof that unexecuted ARM64 binaries run.

- [ ] **Step 7: Commit the release repository**

```powershell
git add -- README.md build-release.ps1 .github/workflows/test.yml SaF-YTDLP.cmd SaF-YTDLP.sh config.ini .gitignore .gitattributes tests LICENSE
git commit -m "release: prepare Simple and Flexible yt-dlp Wrapper"
```

- [ ] **Step 8: Add and run the clean release builder**

`build-release.ps1` creates a temporary staging directory, writes the eight approved release defaults directly to each staged `config.ini`, copies the appropriate launcher, README, and license, builds both archives, and removes staging in `finally`. It must never read, overwrite, or package the working `config.ini`; add a test that writes `COOKIE_BROWSER=zen` to a fixture working config, runs the builder, and confirms the file is unchanged while both archived configs contain `COOKIE_BROWSER=`.

The builder packages only:

```text
Windows ZIP: SaF-YTDLP.cmd, config.ini, README.md, LICENSE
Unix tar.gz: SaF-YTDLP.sh, config.ini, README.md, LICENSE
```

Use `Compress-Archive` for the ZIP and `tar -czf` for the Unix archive. Do not include `internal`, `Downloads`, tests, docs, `.git`, `.github`, or personal cookie selection.

- [ ] **Step 9: Verify both archives from fresh extraction directories**

List archive entries and assert exactly four files in each. Extract each to a new temporary directory, inject the matching fake dependencies under `internal/dependencies`, launch with a blank URL, and verify successful exit, config loading, executable permission on `SaF-YTDLP.sh`, empty `internal/temp`, and no file outside the extracted root.

- [ ] **Step 10: Perform final branch review and report evidence**

Review `git diff` from the pre-release base through HEAD, run both full suites one final time, record test totals, record the Windows checkpoint hash and final release hash, list archive names and sizes, and explicitly distinguish tested native platforms from architecture mappings verified only with fakes.

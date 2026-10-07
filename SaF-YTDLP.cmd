@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SaF yt-dlp Wrapper
cd /d "%~dp0"

rem === Startup and configuration ===

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
set "YTDLP_NEW=%DEPENDENCIES%\yt-dlp.new.exe"
set "DENO_NEW=%DEPENDENCIES%\deno.new.exe"
set "FFMPEG_NEW=%DEPENDENCIES%\ffmpeg.new.exe"
set "FFPROBE_NEW=%DEPENDENCIES%\ffprobe.new.exe"

set "MAX_HEIGHT=1080"
set "DEFAULT_MODE=video"
set "PROFILE=MODERN"
set "TRANSCODE_VP9_TO_AV1=YES"
set "ALLOW_HARDWARE_TRANSCODING=NO"
set "STORE_OPUS_IN_MP4=NO"
set "DOWNLOAD_ALL_AUDIO_TRACKS=YES"
set "COOKIE_BROWSER="

if /i "%~1"=="--internal-dependency-map" goto :internal_dependency_map
if /i "%~1"=="--process-entry" goto :internal_process_entry

call :select_windows_dependencies || goto :fatal
call :load_config || goto :fatal

if not exist "%DEPENDENCIES%" mkdir "%DEPENDENCIES%" >nul 2>&1
if not exist "%TEMP_ROOT%" mkdir "%TEMP_ROOT%" >nul 2>&1
if not exist "%DOWNLOADS%" mkdir "%DOWNLOADS%" >nul 2>&1
if errorlevel 1 goto :fatal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Get-ChildItem -LiteralPath $env:TEMP_ROOT -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force" >nul 2>&1
if errorlevel 1 goto :fatal

if not exist "%YTDLP%" call :install_ytdlp || goto :fatal
if not exist "%DENO%" call :install_deno || goto :fatal
if not exist "%FFMPEG%" call :install_ffmpeg || goto :fatal
if not exist "%FFPROBE%" call :install_ffmpeg || goto :fatal

for %%I in ("%FFMPEG%") do set "FFMPEG_DIR=%%~dpI"
if "!FFMPEG_DIR:~-1!"=="\" set "FFMPEG_DIR=!FFMPEG_DIR:~0,-1!"

echo Updating yt-dlp nightly...
call :update_ytdlp
if errorlevel 1 echo Warning: yt-dlp update failed. Using the installed version.

rem === Menus and downloads ===

:ask_url
echo.
set "URL="
set "JOB_ROOT="
set "JOB_DOWNLOADS="
set "COOKIE_SELECTION_DONE=NO"
set "COOKIE_SOURCE="
set "COOKIE_SOURCE_LABEL="
set "COOKIE_FALLBACK_AVAILABLE=NO"
set "MEDIA_METADATA_ARGS="
set /p "URL=Paste video or playlist URL (blank to exit): "
if not defined URL goto :success_exit
call :prepare_download_job
if errorlevel 1 goto :download_result

echo.
echo Download:
echo   1. Video
echo   2. Audio only
echo   3. Thumbnail only

if /i "%DEFAULT_MODE%"=="video" set "DEFAULT_LABEL=Video"
if /i "%DEFAULT_MODE%"=="audio" set "DEFAULT_LABEL=Audio only"
if /i "%DEFAULT_MODE%"=="thumbnail" set "DEFAULT_LABEL=Thumbnail only"

:ask_mode
set "CHOICE="
set "MODE="
set /p "CHOICE=Select [!DEFAULT_LABEL!]: "
if not defined CHOICE set "MODE=%DEFAULT_MODE%"
if "!CHOICE!"=="1" set "MODE=video"
if "!CHOICE!"=="2" set "MODE=audio"
if "!CHOICE!"=="3" set "MODE=thumbnail"

if /i "!MODE!"=="video" goto :download_video
if /i "!MODE!"=="audio" goto :download_audio
if /i "!MODE!"=="thumbnail" goto :download_thumbnail

echo Invalid choice. Enter 1, 2, or 3.
goto :ask_mode

:download_video
set "MEDIA_METADATA_ARGS=--embed-chapters --embed-metadata"
del /q "%POSTPROCESS_QUEUE%" >nul 2>&1
if /i "%DOWNLOAD_ALL_AUDIO_TRACKS%"=="YES" (
    call :download_all_audio_video
    goto :download_result
)
if /i "%PROFILE%"=="MODERN" (
    call :download_modern_video
    goto :download_result
)
set "FORMAT_SORT="
if /i "%PROFILE%"=="UNIVERSAL" set "FORMAT_SORT=-S res,fps,vcodec:h264"
if /i "%PROFILE%"=="QUALITY" set "FORMAT_SORT=-S res,fps,vcodec:av1"
if /i "%PROFILE%"=="QUALITY" (
    if "%MAX_HEIGHT%"=="0" (
        set "FORMAT=bv*+ba/b"
    ) else (
        set "FORMAT=bv*[height<=%MAX_HEIGHT%]+ba/b[height<=%MAX_HEIGHT%]"
    )
) else if "%MAX_HEIGHT%"=="0" (
    set "FORMAT=bv*+ba[acodec^=mp4a]/bv*+ba/b"
) else if %MAX_HEIGHT% LEQ 1080 (
    set "FORMAT=bv*[height<=%MAX_HEIGHT%][vcodec^=avc1]+ba[acodec^=mp4a]/bv*[height<=%MAX_HEIGHT%][vcodec^=avc1]+ba/bv*[height<=%MAX_HEIGHT%][vcodec^=h264]+ba[acodec^=mp4a]/bv*[height<=%MAX_HEIGHT%][vcodec^=h264]+ba/bv*[height<=%MAX_HEIGHT%]+ba[acodec^=mp4a]/bv*[height<=%MAX_HEIGHT%]+ba/b[height<=%MAX_HEIGHT%]"
) else (
    set "FORMAT=bv*[height<=%MAX_HEIGHT%]+ba[acodec^=mp4a]/bv*[height<=%MAX_HEIGHT%]+ba/b[height<=%MAX_HEIGHT%]"
)
call :run_ytdlp !FORMAT_SORT! -f "!FORMAT!" --print-to-file "after_move:%%%%(filepath)s	%%%%(vcodec)s	%%%%(acodec)s" "%POSTPROCESS_QUEUE%"
set "YTDLP_RESULT=!errorlevel!"
call :process_postprocess_queue
set "POSTPROCESS_RESULT=!errorlevel!"
if not "!YTDLP_RESULT!"=="0" (
    call :set_errorlevel !YTDLP_RESULT!
    goto :download_result
)
call :set_errorlevel !POSTPROCESS_RESULT!
goto :download_result

:download_modern_video
call :prepare_modern_selections
if errorlevel 1 (
    del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
    exit /b 1
)

set "YTDLP_RESULT=0"
for /f "usebackq tokens=1,* delims=	" %%A in ("%MODERN_SELECTIONS%") do (
    if /i "%%A"=="ERROR" (
        echo Warning: playlist entry %%B has no usable video format.
        set "YTDLP_RESULT=1"
    ) else (
        set "MODERN_PLAYLIST_ARGS="
        if not "%%A"=="0" set "MODERN_PLAYLIST_ARGS=--playlist-items %%A"
        set "FORMAT=%%B+ba[acodec^=mp4a]/%%B+ba/%%B"
        call :run_ytdlp !MODERN_PLAYLIST_ARGS! -f "!FORMAT!" --print-to-file "after_move:%%%%(filepath)s	%%%%(vcodec)s	%%%%(acodec)s" "%POSTPROCESS_QUEUE%"
        if errorlevel 1 set "YTDLP_RESULT=1"
    )
)

call :process_postprocess_queue
set "POSTPROCESS_RESULT=%errorlevel%"
del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
if not "%YTDLP_RESULT%"=="0" exit /b %YTDLP_RESULT%
exit /b %POSTPROCESS_RESULT%

rem === Format and audio selection ===

:prepare_modern_selections
set "MODERN_METADATA=%JOB_ROOT%\metadata.json"
set "MODERN_SELECTIONS=%JOB_ROOT%\selections.txt"
del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
call :write_modern_metadata
if errorlevel 1 exit /b 1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $root=Get-Content -Raw -LiteralPath $env:MODERN_METADATA|ConvertFrom-Json; $isPlaylist=$root._type -eq 'playlist'; $entries=if($isPlaylist){@($root.entries|Where-Object {$_})}else{@($root)}; $lines=New-Object 'Collections.Generic.List[string]'; $position=0; foreach($entry in $entries){$position++; $item=if($isPlaylist){if($entry.playlist_index){[string]$entry.playlist_index}else{[string]$position}}else{'0'}; $formats=@($entry.formats|Where-Object {$_.format_id -and $_.vcodec -and $_.vcodec -ne 'none' -and ($env:MAX_HEIGHT -eq '0' -or -not $_.height -or [int]$_.height -le [int]$env:MAX_HEIGHT)}); if($formats.Count -eq 0){$lines.Add('ERROR'+[char]9+$item); continue}; $sort=@(@{Expression={if($_.height){[int]$_.height}else{0}};Descending=$true},@{Expression={if($_.fps){[double]$_.fps}else{0}};Descending=$true},@{Expression={$codec=[string]$_.vcodec; if($codec -match '^(hev1|hvc1|hevc|h265)'){4}elseif($codec -match '^(avc1|h264)'){3}elseif($codec -match '^(av01|av1)'){2}elseif($codec -match '^(vp09|vp9)'){1}else{0}};Descending=$true},@{Expression={if($_.quality){[double]$_.quality}else{0}};Descending=$true},@{Expression={if($_.tbr){[double]$_.tbr}else{0}};Descending=$true}); $chosen=$formats|Sort-Object -Property $sort|Select-Object -First 1; $lines.Add($item+[char]9+[string]$chosen.format_id)}; if($lines.Count -eq 0){throw 'No video entries'}; [IO.File]::WriteAllLines($env:MODERN_SELECTIONS,$lines,(New-Object Text.UTF8Encoding($false)))" >nul 2>&1
if errorlevel 1 (
    echo Error: could not select Modern video formats.
    exit /b 1
)
exit /b 0

:write_modern_metadata
if /i "%COOKIE_SELECTION_DONE%"=="NO" call :select_cookie_source
:write_modern_metadata_attempt
if defined COOKIE_SOURCE (
    "%YTDLP%" --ignore-config --cookies-from-browser "!COOKIE_SOURCE!" --js-runtimes "deno:%DENO%" --ffmpeg-location "%FFMPEG_DIR%" --dump-single-json --skip-download "!URL!" >"%MODERN_METADATA%"
) else (
    "%YTDLP%" --ignore-config --js-runtimes "deno:%DENO%" --ffmpeg-location "%FFMPEG_DIR%" --dump-single-json --skip-download "!URL!" >"%MODERN_METADATA%"
)
set "YTDLP_ATTEMPT_RESULT=%errorlevel%"
if "%YTDLP_ATTEMPT_RESULT%"=="0" exit /b 0
if /i not "%COOKIE_FALLBACK_AVAILABLE%"=="YES" exit /b %YTDLP_ATTEMPT_RESULT%

echo Saved browser session failed before reading formats. Checking other browsers...
set "SKIP_SAVED_COOKIE=YES"
set "COOKIE_SELECTION_DONE=NO"
call :select_cookie_source
set "SKIP_SAVED_COOKIE="
set "COOKIE_FALLBACK_AVAILABLE=NO"
goto :write_modern_metadata_attempt

:download_audio
set "MEDIA_METADATA_ARGS=--embed-chapters --embed-metadata"
if /i "%DOWNLOAD_ALL_AUDIO_TRACKS%"=="YES" (
    call :download_all_audio_only
    goto :download_result
)
call :set_audio_download_arguments
if defined AUDIO_REMUX_FORMAT (
    call :run_ytdlp -f "!AUDIO_SELECTOR!" --extract-audio --audio-format "!AUDIO_FORMAT!" !AUDIO_QUALITY_ARGS! --remux-video "opus>mp4" --embed-thumbnail
) else (
    call :run_ytdlp -f "!AUDIO_SELECTOR!" --extract-audio --audio-format "!AUDIO_FORMAT!" !AUDIO_QUALITY_ARGS! --embed-thumbnail
)
goto :download_result

:download_all_audio_video
call :prepare_all_audio_selections video
if errorlevel 1 (
    del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
    exit /b 1
)

set "YTDLP_RESULT=0"
for /f "usebackq tokens=1,2,3,4,5,6 delims=	" %%A in ("%MODERN_SELECTIONS%") do (
    if /i "%%A"=="ERROR" (
        echo Warning: playlist entry %%B has no usable video format.
        set "YTDLP_RESULT=1"
    ) else (
        set "MULTITRACK_PLAYLIST_ARGS="
        if not "%%A"=="0" set "MULTITRACK_PLAYLIST_ARGS=--playlist-items %%A"
        set "MULTITRACK_AUDIO=%%C"
        if /i "!MULTITRACK_AUDIO!"=="NONE" set "MULTITRACK_AUDIO="
        if defined MULTITRACK_AUDIO (set "FORMAT=%%B+!MULTITRACK_AUDIO!") else set "FORMAT=%%B"
        set "MULTITRACK_VIDEO_ARGS="
        if /i "%%D"=="YES" set "MULTITRACK_VIDEO_ARGS=--video-multistreams --merge-output-format mkv"
        call :run_ytdlp !MULTITRACK_PLAYLIST_ARGS! !MULTITRACK_VIDEO_ARGS! --audio-multistreams -f "!FORMAT!" --print-to-file "after_move:%%%%(filepath)s	%%%%(vcodec)s	%%%%(acodec)s	%%F" "%POSTPROCESS_QUEUE%"
        if errorlevel 1 set "YTDLP_RESULT=1"
    )
)

call :process_postprocess_queue
set "POSTPROCESS_RESULT=%errorlevel%"
del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
if not "%YTDLP_RESULT%"=="0" exit /b %YTDLP_RESULT%
exit /b %POSTPROCESS_RESULT%

:download_all_audio_only
call :prepare_all_audio_selections audio
if errorlevel 1 (
    del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
    exit /b 1
)

set "YTDLP_RESULT=0"
for /f "usebackq tokens=1,2,3,4,5,6 delims=	" %%A in ("%MODERN_SELECTIONS%") do (
    set "MULTITRACK_PLAYLIST_ARGS="
    if not "%%A"=="0" set "MULTITRACK_PLAYLIST_ARGS=--playlist-items %%A"
    set "FORMAT=%%C"
    if /i "!FORMAT!"=="NONE" set "FORMAT="
    if not defined FORMAT (
        call :set_audio_download_arguments
        if defined AUDIO_REMUX_FORMAT (
            call :run_ytdlp !MULTITRACK_PLAYLIST_ARGS! -f "!AUDIO_SELECTOR!" --extract-audio --audio-format "!AUDIO_FORMAT!" !AUDIO_QUALITY_ARGS! --remux-video "opus>mp4" --embed-thumbnail
        ) else (
            call :run_ytdlp !MULTITRACK_PLAYLIST_ARGS! -f "!AUDIO_SELECTOR!" --extract-audio --audio-format "!AUDIO_FORMAT!" !AUDIO_QUALITY_ARGS! --embed-thumbnail
        )
    ) else (
        call :set_audio_metadata_arguments "%%F"
        if /i "%PROFILE%"=="QUALITY" (
            set "QUALITY_AUDIO_CONTAINER=mka"
            if /i "%STORE_OPUS_IN_MP4%"=="YES" set "QUALITY_AUDIO_CONTAINER=mp4"
            set "QUALITY_AUDIO_PP=VideoRemuxer+ffmpeg_o:-vn!AUDIO_METADATA_ARGS!"
            if /i "%%E"=="YES" set "QUALITY_AUDIO_PP=VideoRemuxer+ffmpeg_o:-vn -c:a libopus!AUDIO_METADATA_ARGS!"
            set "MULTITRACK_COMBINED_ARGS="
            if /i "%%D"=="YES" set "MULTITRACK_COMBINED_ARGS=--video-multistreams"
            call :run_ytdlp !MULTITRACK_PLAYLIST_ARGS! !MULTITRACK_COMBINED_ARGS! --audio-multistreams -f "!FORMAT!" --merge-output-format mkv --remux-video !QUALITY_AUDIO_CONTAINER! --postprocessor-args "!QUALITY_AUDIO_PP!" --embed-thumbnail
        ) else (
            set "MULTITRACK_COMBINED_ARGS="
            if /i "%%D"=="YES" set "MULTITRACK_COMBINED_ARGS=--video-multistreams"
            call :run_ytdlp !MULTITRACK_PLAYLIST_ARGS! !MULTITRACK_COMBINED_ARGS! --audio-multistreams -f "!FORMAT!" --merge-output-format mkv --recode-video m4a --postprocessor-args "VideoConvertor+ffmpeg_o:-vn!AUDIO_METADATA_ARGS!" --embed-thumbnail
        )
    )
    if errorlevel 1 set "YTDLP_RESULT=1"
)
del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
exit /b %YTDLP_RESULT%

:set_audio_download_arguments
set "AUDIO_SELECTOR=ba/b"
set "AUDIO_FORMAT=best"
set "AUDIO_QUALITY_ARGS="
set "AUDIO_REMUX_FORMAT="
if /i "%PROFILE%"=="QUALITY" if /i "%STORE_OPUS_IN_MP4%"=="YES" set "AUDIO_REMUX_FORMAT=opus-to-mp4"
if /i "%PROFILE%"=="MODERN" (
    set "AUDIO_SELECTOR=ba[acodec^=mp4a]/ba/b[acodec^=mp4a]/b"
    set "AUDIO_FORMAT=m4a"
    set "AUDIO_QUALITY_ARGS=--audio-quality 0"
)
if /i "%PROFILE%"=="UNIVERSAL" (
    set "AUDIO_FORMAT=mp3"
    set "AUDIO_QUALITY_ARGS=--audio-quality 0"
)
exit /b 0

:prepare_all_audio_selections
set "MODERN_METADATA=%JOB_ROOT%\metadata.json"
set "MODERN_SELECTIONS=%JOB_ROOT%\selections.txt"
set "ALL_AUDIO_MODE=%~1"
del /q "%MODERN_METADATA%" "%MODERN_SELECTIONS%" >nul 2>&1
call :write_modern_metadata
if errorlevel 1 exit /b 1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $root=Get-Content -Raw -LiteralPath $env:MODERN_METADATA|ConvertFrom-Json; $isPlaylist=$root._type -eq 'playlist'; $entries=if($isPlaylist){@($root.entries|Where-Object {$_})}else{@($root)}; $lines=New-Object 'Collections.Generic.List[string]'; $position=0; foreach($entry in $entries){$position++; $item=if($isPlaylist){if($entry.playlist_index){[string]$entry.playlist_index}else{[string]$position}}else{'0'}; $allFormats=@($entry.formats|Where-Object {$_.format_id}); $audioFormats=@($allFormats|Where-Object {$_.acodec -and $_.acodec -ne 'none'}); $chosenAudio=@(); foreach($group in @($audioFormats|Group-Object {if($_.language){[string]$_.language}else{'und'}})){ $sort=@(@{Expression={if($env:PROFILE -eq 'QUALITY'){if(([string]$_.acodec) -match '^opus'){2}else{1}}else{if(([string]$_.acodec) -match '^(mp4a|aac)'){2}else{1}}};Descending=$true},@{Expression={if($_.vcodec -eq 'none'){2}else{1}};Descending=$true},@{Expression={if($_.quality){[double]$_.quality}else{0}};Descending=$true},@{Expression={if($_.abr){[double]$_.abr}else{0}};Descending=$true},@{Expression={if($_.tbr){[double]$_.tbr}else{0}};Descending=$true}); $chosenAudio+=@($group.Group|Sort-Object -Property $sort|Select-Object -First 1) }; $chosenAudio=@($chosenAudio|Sort-Object @{Expression={if($_.language_preference){[double]$_.language_preference}else{0}};Descending=$true},@{Expression={if($_.language){[string]$_.language}else{'und'}}}); $videoId='AUTO'; $videoFormat=$null; if($env:ALL_AUDIO_MODE -eq 'video'){ $videos=@($allFormats|Where-Object {$_.vcodec -and $_.vcodec -ne 'none' -and ($env:MAX_HEIGHT -eq '0' -or -not $_.height -or [int]$_.height -le [int]$env:MAX_HEIGHT)}); if($videos.Count -eq 0){$lines.Add('ERROR'+[char]9+$item); continue}; $videoSort=@(@{Expression={if($_.height){[int]$_.height}else{0}};Descending=$true},@{Expression={if($_.fps){[double]$_.fps}else{0}};Descending=$true},@{Expression={$codec=[string]$_.vcodec; if($env:PROFILE -eq 'QUALITY'){if($codec -match '^(av01|av1)'){1}else{0}}elseif($env:PROFILE -eq 'UNIVERSAL'){if($codec -match '^(avc1|h264)'){4}elseif($codec -match '^(hev1|hvc1|hevc|h265)'){3}elseif($codec -match '^(av01|av1)'){2}elseif($codec -match '^(vp09|vp9)'){1}else{0}}else{if($codec -match '^(hev1|hvc1|hevc|h265)'){4}elseif($codec -match '^(avc1|h264)'){3}elseif($codec -match '^(av01|av1)'){2}elseif($codec -match '^(vp09|vp9)'){1}else{0}}};Descending=$true},@{Expression={if($_.quality){[double]$_.quality}else{0}};Descending=$true},@{Expression={if(-not $_.acodec -or $_.acodec -eq 'none'){2}else{1}};Descending=$true},@{Expression={if($_.language_preference){[double]$_.language_preference}else{0}};Descending=$true},@{Expression={if($_.tbr){[double]$_.tbr}else{0}};Descending=$true}); $videoFormat=$videos|Sort-Object -Property $videoSort|Select-Object -First 1; $videoId=[string]$videoFormat.format_id }; $videoHasAudio=[bool]($videoFormat -and $videoFormat.acodec -and $videoFormat.acodec -ne 'none'); $videoLanguage=if($videoHasAudio){[string]$videoFormat.language}else{''}; $selectedAudio=@($chosenAudio|Where-Object {[string]$_.format_id -ne $videoId -and (-not $videoHasAudio -or [string]$_.language -ne $videoLanguage)}); $audioIds=($selectedAudio|ForEach-Object {[string]$_.format_id}) -join '+'; if(-not $audioIds){$audioIds='NONE'}; $needsOpus=if(@($chosenAudio|Where-Object {([string]$_.acodec) -notmatch '^opus'}).Count -gt 0){'YES'}else{'NO'}; $finalAudio=@(); if($videoHasAudio){$finalAudio+=@($videoFormat)}; $finalAudio+=@($selectedAudio); $hasCombined=if(@($finalAudio|Where-Object {$_.vcodec -and $_.vcodec -ne 'none'}).Count -gt 0){'YES'}else{'NO'}; $audioLanguages=($finalAudio|ForEach-Object {$lang=[string]$_.language; if(-not $lang -or $lang -notmatch '^[A-Za-z0-9-]+$'){'und'}else{$lang}}) -join '+'; if(-not $audioLanguages){$audioLanguages='NONE'}; $lines.Add($item+[char]9+$videoId+[char]9+$audioIds+[char]9+$hasCombined+[char]9+$needsOpus+[char]9+$audioLanguages) }; if($lines.Count -eq 0){throw 'No entries'}; [IO.File]::WriteAllLines($env:MODERN_SELECTIONS,$lines,(New-Object Text.UTF8Encoding($false)))" >nul 2>&1
if errorlevel 1 (
    echo Error: could not select multilingual audio formats.
    exit /b 1
)
exit /b 0

:download_thumbnail
call :run_ytdlp --skip-download --write-thumbnail
goto :download_result

:download_result
set "DOWNLOAD_RESULT=!errorlevel!"
call :publish_download_job
set "PUBLISH_RESULT=!errorlevel!"
if "!PUBLISH_RESULT!"=="0" call :cleanup_job
if not "!DOWNLOAD_RESULT!"=="0" (
    echo.
    echo Download failed. Check the URL and the message above.
    goto :ask_url
)
if not "!PUBLISH_RESULT!"=="0" (
    echo.
    echo Download failed. Finished files could not be moved to the Downloads folder.
    goto :ask_url
)

echo.
echo Download complete.
goto :ask_url

:run_ytdlp
if /i "!COOKIE_SELECTION_DONE!"=="NO" call :select_cookie_source
:run_ytdlp_attempt
call :count_job_files
set "JOB_FILES_BEFORE=!JOB_FILE_COUNT!"
if defined COOKIE_SOURCE (
    "%YTDLP%" --ignore-config --cookies-from-browser "!COOKIE_SOURCE!" --js-runtimes "deno:%DENO%" --ffmpeg-location "%FFMPEG_DIR%" !MEDIA_METADATA_ARGS! -P "%JOB_DOWNLOADS%" -o "%%(playlist&{}/|)s%%(playlist_index&{} - |)s%%(title)s.%%(ext)s" %* "!URL!"
) else (
    "%YTDLP%" --ignore-config --js-runtimes "deno:%DENO%" --ffmpeg-location "%FFMPEG_DIR%" !MEDIA_METADATA_ARGS! -P "%JOB_DOWNLOADS%" -o "%%(playlist&{}/|)s%%(playlist_index&{} - |)s%%(title)s.%%(ext)s" %* "!URL!"
)
set "YTDLP_ATTEMPT_RESULT=!errorlevel!"
if "!YTDLP_ATTEMPT_RESULT!"=="0" exit /b 0
if /i not "!COOKIE_FALLBACK_AVAILABLE!"=="YES" exit /b !YTDLP_ATTEMPT_RESULT!
call :count_job_files
if !JOB_FILE_COUNT! GTR !JOB_FILES_BEFORE! exit /b !YTDLP_ATTEMPT_RESULT!

echo Saved browser session failed before downloading. Checking other browsers...
set "SKIP_SAVED_COOKIE=YES"
set "COOKIE_SELECTION_DONE=NO"
call :select_cookie_source
set "SKIP_SAVED_COOKIE="
set "COOKIE_FALLBACK_AVAILABLE=NO"
goto :run_ytdlp_attempt

rem === Browser cookies ===

:select_cookie_source
set "COOKIE_SELECTION_DONE=YES"
set "COOKIE_SOURCE="
set "COOKIE_SOURCE_LABEL="
set "COOKIE_FALLBACK_AVAILABLE=NO"
set "COOKIE_TRIED_CHROME="
set "COOKIE_TRIED_EDGE="
set "COOKIE_TRIED_FIREFOX="
set "COOKIE_TRIED_BRAVE="
set "COOKIE_TRIED_OPERA="
set "COOKIE_TRIED_VIVALDI="
set "COOKIE_TRIED_COMET="
set "COOKIE_TRIED_ZEN="

call :resolve_saved_cookie_source
if defined SAVED_COOKIE_SOURCE if /i not "!SKIP_SAVED_COOKIE!"=="YES" (
    set "COOKIE_SOURCE=!SAVED_COOKIE_SOURCE!"
    set "COOKIE_SOURCE_LABEL=!SAVED_COOKIE_LABEL!"
    set "COOKIE_FALLBACK_AVAILABLE=YES"
    echo Using cookies from !SAVED_COOKIE_LABEL!.
    exit /b 0
)
if defined SAVED_COOKIE_KEY if /i "!SKIP_SAVED_COOKIE!"=="YES" set "COOKIE_TRIED_!SAVED_COOKIE_KEY!=YES"
echo.
echo Checking browser sessions for usable cookies...
call :probe_cookie_source "CHROME" "chrome" "Chrome"
if defined COOKIE_SOURCE exit /b 0
call :probe_cookie_source "EDGE" "edge" "Edge"
if defined COOKIE_SOURCE exit /b 0
call :probe_cookie_source "FIREFOX" "firefox" "Firefox"
if defined COOKIE_SOURCE exit /b 0
call :probe_cookie_source "OPERA" "opera" "Opera"
if defined COOKIE_SOURCE exit /b 0
call :probe_cookie_source "BRAVE" "brave" "Brave"
if defined COOKIE_SOURCE exit /b 0
call :probe_cookie_source "VIVALDI" "vivaldi" "Vivaldi"
if defined COOKIE_SOURCE exit /b 0
call :resolve_comet_cookie_source
if defined COMET_COOKIE_SOURCE call :probe_cookie_source "COMET" "!COMET_COOKIE_SOURCE!" "Comet"
if defined COOKIE_SOURCE exit /b 0
call :probe_cookie_source "ZEN" "firefox:%APPDATA%\zen\Profiles" "Zen"
if defined COOKIE_SOURCE exit /b 0

echo No usable browser session was found; continuing without browser cookies.
exit /b 0

:resolve_saved_cookie_source
set "SAVED_COOKIE_KEY="
set "SAVED_COOKIE_SOURCE="
set "SAVED_COOKIE_LABEL="
if /i "!COOKIE_BROWSER!"=="chrome" (
    set "SAVED_COOKIE_KEY=CHROME"
    set "SAVED_COOKIE_SOURCE=chrome"
    set "SAVED_COOKIE_LABEL=Chrome"
)
if /i "!COOKIE_BROWSER!"=="edge" (
    set "SAVED_COOKIE_KEY=EDGE"
    set "SAVED_COOKIE_SOURCE=edge"
    set "SAVED_COOKIE_LABEL=Edge"
)
if /i "!COOKIE_BROWSER!"=="firefox" (
    set "SAVED_COOKIE_KEY=FIREFOX"
    set "SAVED_COOKIE_SOURCE=firefox"
    set "SAVED_COOKIE_LABEL=Firefox"
)
if /i "!COOKIE_BROWSER!"=="opera" (
    set "SAVED_COOKIE_KEY=OPERA"
    set "SAVED_COOKIE_SOURCE=opera"
    set "SAVED_COOKIE_LABEL=Opera"
)
if /i "!COOKIE_BROWSER!"=="brave" (
    set "SAVED_COOKIE_KEY=BRAVE"
    set "SAVED_COOKIE_SOURCE=brave"
    set "SAVED_COOKIE_LABEL=Brave"
)
if /i "!COOKIE_BROWSER!"=="vivaldi" (
    set "SAVED_COOKIE_KEY=VIVALDI"
    set "SAVED_COOKIE_SOURCE=vivaldi"
    set "SAVED_COOKIE_LABEL=Vivaldi"
)
if /i "!COOKIE_BROWSER!"=="comet" (
    call :resolve_comet_cookie_source
    if defined COMET_COOKIE_SOURCE (
        set "SAVED_COOKIE_KEY=COMET"
        set "SAVED_COOKIE_SOURCE=!COMET_COOKIE_SOURCE!"
        set "SAVED_COOKIE_LABEL=Comet"
    )
)
if /i "!COOKIE_BROWSER!"=="zen" (
    set "SAVED_COOKIE_KEY=ZEN"
    set "SAVED_COOKIE_SOURCE=firefox:%APPDATA%\zen\Profiles"
    set "SAVED_COOKIE_LABEL=Zen"
)
exit /b 0

:resolve_comet_cookie_source
set "COMET_COOKIE_SOURCE="
set "COMET_PROFILE_PATH="
set "COMET_USER_DATA=%LOCALAPPDATA%\Perplexity\Comet\User Data"
if not exist "!COMET_USER_DATA!" exit /b 0
for /f "usebackq delims=" %%I in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$root=$env:COMET_USER_DATA; $rootPath=[IO.Path]::GetFullPath($root).TrimEnd('\'); $cookie=Get-ChildItem -LiteralPath $root -Filter Cookies -File -Recurse -ErrorAction SilentlyContinue | Where-Object {$directory=$_.Directory; $profile=if($directory.Name -ieq 'Network'){$directory.Parent}else{$directory}; $parentPath=if($profile -and $profile.Parent){[IO.Path]::GetFullPath($profile.Parent.FullName).TrimEnd('\')}else{''}; $profile -and $parentPath -ieq $rootPath -and ($profile.Name -eq 'Default' -or $profile.Name -match '^Profile [0-9]+$')} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1; if($cookie){$directory=$cookie.Directory; $profile=if($directory.Name -ieq 'Network'){$directory.Parent}else{$directory}; [Console]::Write($profile.FullName)}" 2^>nul`) do if not defined COMET_PROFILE_PATH set "COMET_PROFILE_PATH=%%I"
if defined COMET_PROFILE_PATH set "COMET_COOKIE_SOURCE=chrome:!COMET_PROFILE_PATH!"
exit /b 0

:probe_cookie_source
if defined COOKIE_TRIED_%~1 exit /b 1
set "COOKIE_TRIED_%~1=YES"
"%YTDLP%" --ignore-config --js-runtimes "deno:%DENO%" --ffmpeg-location "%FFMPEG_DIR%" --no-playlist --simulate --cookies-from-browser "%~2" "!URL!" >nul 2>&1
if errorlevel 1 exit /b 1
set "COOKIE_SOURCE=%~2"
set "COOKIE_SOURCE_LABEL=%~3"
set "COOKIE_FALLBACK_AVAILABLE=YES"
echo Using cookies from %~3.
call :remember_cookie_browser "%~1"
exit /b 0

:remember_cookie_browser
set "COOKIE_BROWSER_NEW="
if /i "%~1"=="CHROME" set "COOKIE_BROWSER_NEW=chrome"
if /i "%~1"=="EDGE" set "COOKIE_BROWSER_NEW=edge"
if /i "%~1"=="FIREFOX" set "COOKIE_BROWSER_NEW=firefox"
if /i "%~1"=="OPERA" set "COOKIE_BROWSER_NEW=opera"
if /i "%~1"=="BRAVE" set "COOKIE_BROWSER_NEW=brave"
if /i "%~1"=="VIVALDI" set "COOKIE_BROWSER_NEW=vivaldi"
if /i "%~1"=="COMET" set "COOKIE_BROWSER_NEW=comet"
if /i "%~1"=="ZEN" set "COOKIE_BROWSER_NEW=zen"
if not defined COOKIE_BROWSER_NEW exit /b 0
if /i "!COOKIE_BROWSER!"=="!COOKIE_BROWSER_NEW!" exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $path=$env:CONFIG; $value=$env:COOKIE_BROWSER_NEW; $text=[IO.File]::ReadAllText($path); $pattern='(?im)^[ \t]*COOKIE_BROWSER[ \t]*=.*$'; if([regex]::IsMatch($text,$pattern)){$text=[regex]::Replace($text,$pattern,'COOKIE_BROWSER='+$value)}else{if($text.Length -gt 0 -and -not $text.EndsWith([Environment]::NewLine)){$text+=[Environment]::NewLine}; $text+='COOKIE_BROWSER='+$value+[Environment]::NewLine}; $temporary=$path+'.saf-new'; [IO.File]::WriteAllText($temporary,$text,(New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $temporary -Destination $path -Force" >nul 2>&1
if errorlevel 1 (
    echo Warning: could not remember the working browser in config.ini.
    exit /b 0
)
set "COOKIE_BROWSER=!COOKIE_BROWSER_NEW!"
echo Remembered %~1 in config.ini.
exit /b 0

rem === Publishing and cleanup ===

:count_job_files
set /a JOB_FILE_COUNT=0
for /f "delims=" %%F in ('dir /b /s /a-d "!JOB_DOWNLOADS!" 2^>nul') do set /a JOB_FILE_COUNT+=1
exit /b 0

:prepare_download_job
:choose_download_job
set "JOB_ROOT=%TEMP_ROOT%\job-!RANDOM!-!RANDOM!"
if exist "!JOB_ROOT!" goto :choose_download_job
set "JOB_DOWNLOADS=!JOB_ROOT!\downloads"
set "POSTPROCESS_QUEUE=!JOB_ROOT!\postprocess.txt"
set "PROBE_JSON=!JOB_ROOT!\probe.json"
set "PROBE_TEXT=!JOB_ROOT!\probe.txt"
set "FFPROBE_OUTPUT=!JOB_ROOT!\bitrate.txt"
mkdir "!JOB_DOWNLOADS!" >nul 2>&1
if errorlevel 1 (
    echo Error: could not create the temporary download folder.
    exit /b 1
)
exit /b 0

:publish_download_job
if not defined JOB_DOWNLOADS exit /b 0
if not exist "%JOB_DOWNLOADS%" exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $source=[IO.Path]::GetFullPath($env:JOB_DOWNLOADS).TrimEnd([IO.Path]::DirectorySeparatorChar); $destination=[IO.Path]::GetFullPath($env:DOWNLOADS).TrimEnd([IO.Path]::DirectorySeparatorChar); foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse){ $relative=$file.FullName.Substring($source.Length).TrimStart([IO.Path]::DirectorySeparatorChar); $target=Join-Path $destination $relative; $targetDirectory=Split-Path -Parent $target; if(-not (Test-Path -LiteralPath $targetDirectory)){New-Item -ItemType Directory -Path $targetDirectory -Force|Out-Null}; $extension=[IO.Path]::GetExtension($target); $stem=[IO.Path]::GetFileNameWithoutExtension($target); $candidate=$target; $number=1; while(Test-Path -LiteralPath $candidate){$candidate=Join-Path $targetDirectory ($stem+' ('+$number+')'+$extension); $number++}; Move-Item -LiteralPath $file.FullName -Destination $candidate }"
exit /b %errorlevel%

:cleanup_job
if not defined JOB_ROOT exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $temp=[IO.Path]::GetFullPath($env:TEMP_ROOT).TrimEnd([IO.Path]::DirectorySeparatorChar); $job=[IO.Path]::GetFullPath($env:JOB_ROOT).TrimEnd([IO.Path]::DirectorySeparatorChar); if(-not $job.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe job path'}; if(Test-Path -LiteralPath $job){Remove-Item -LiteralPath $job -Recurse -Force}" >nul 2>&1
set "CLEANUP_RESULT=%errorlevel%"
set "JOB_ROOT="
set "JOB_DOWNLOADS="
set "POSTPROCESS_QUEUE="
set "PROBE_JSON="
set "PROBE_TEXT="
set "FFPROBE_OUTPUT="
exit /b %CLEANUP_RESULT%

:process_postprocess_queue
if not exist "%POSTPROCESS_QUEUE%" exit /b 0
set "SAF_SCRIPT=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $failed=$false; foreach($line in [IO.File]::ReadLines($env:POSTPROCESS_QUEUE,[Text.Encoding]::UTF8)){ if([string]::IsNullOrWhiteSpace($line)){continue}; $parts=$line.Split([char]9,4); if($parts.Length -lt 3 -or $parts.Length -gt 4){$failed=$true; continue}; $env:SAF_QUEUED_INPUT=$parts[0]; $env:SAF_QUEUED_VIDEO_CODEC=$parts[1]; $env:SAF_QUEUED_AUDIO_CODEC=$parts[2]; $env:SAF_QUEUED_AUDIO_LANGUAGES=if($parts.Length -eq 4){$parts[3]}else{''}; & $env:SAF_SCRIPT '--process-entry'; if($LASTEXITCODE -ne 0){$failed=$true} }; if($failed){exit 1}"
set "QUEUE_FAILURE=%errorlevel%"
del /q "%POSTPROCESS_QUEUE%" >nul 2>&1
if not "%QUEUE_FAILURE%"=="0" (
    echo Conversion failed; the downloaded source was kept.
    exit /b 1
)
exit /b 0

rem === Inspection and post-processing ===

:process_download
setlocal DisableDelayedExpansion
set "INPUT_FILE=%QUEUED_INPUT%"
set "VIDEO_CODEC=%QUEUED_VIDEO_CODEC%"
set "AUDIO_CODEC=%QUEUED_AUDIO_CODEC%"
set "AUDIO_LANGUAGES=%QUEUED_AUDIO_LANGUAGES%"
set "TARGET_CODEC=NONE"
set "AUDIO_ACTION=COPY"
set "NEEDS_REMUX=NO"
set "AUDIO_METADATA_ARGS="
call :inspect_media || (endlocal & exit /b 1)
call :normalize_codec "%SOURCE_VIDEO_CODEC%" SOURCE_CODEC
if /i "%AUDIO_LANGUAGES%"=="NONE" set "AUDIO_LANGUAGES="
if defined AUDIO_LANGUAGES call :set_audio_metadata_arguments "%AUDIO_LANGUAGES%"

if /i "%PROFILE%"=="QUALITY" (
    if /i "%TRANSCODE_VP9_TO_AV1%"=="YES" call :select_quality_target
)
if /i "%PROFILE%"=="MODERN" call :select_modern_target
if /i "%PROFILE%"=="UNIVERSAL" call :select_universal_target
for %%I in ("%INPUT_FILE%") do set "INPUT_EXTENSION=%%~xI"
if /i "%PROFILE%"=="QUALITY" if /i not "%INPUT_EXTENSION%"==".mp4" set "NEEDS_REMUX=YES"
if /i "%PROFILE%"=="MODERN" if /i not "%INPUT_EXTENSION%"==".mp4" set "NEEDS_REMUX=YES"
if /i "%PROFILE%"=="UNIVERSAL" if /i not "%INPUT_EXTENSION%"==".mp4" set "NEEDS_REMUX=YES"
if /i "%DOWNLOAD_ALL_AUDIO_TRACKS%"=="YES" set "NEEDS_REMUX=YES"

if /i "%TARGET_CODEC%"=="NONE" if /i "%AUDIO_ACTION%"=="COPY" if /i "%NEEDS_REMUX%"=="NO" (
    endlocal
    exit /b 0
)

call :transcode_media
set "TRANSCODE_RESULT=%errorlevel%"
endlocal & exit /b %TRANSCODE_RESULT%

:select_quality_target
if /i "%SOURCE_CODEC%"=="VP9" set "TARGET_CODEC=AV1"
exit /b 0

:select_modern_target
set "TARGET_CODEC=H265"
if /i "%SOURCE_CODEC%"=="H265" set "TARGET_CODEC=NONE"
if /i "%SOURCE_CODEC%"=="H264" call :keep_compatible_h264
call :select_aac_action
exit /b 0

:select_universal_target
set "TARGET_CODEC=H264"
if /i "%SOURCE_CODEC%"=="H264" call :keep_compatible_h264
call :read_audio_codec
call :select_aac_action
exit /b 0

:inspect_media
set "SOURCE_VIDEO_CODEC="
set "SOURCE_VIDEO_HEIGHT="
set "SOURCE_VIDEO_BITRATE="
set "SOURCE_PIXEL_FORMAT="
set "SOURCE_DURATION="
set "SOURCE_AUDIO_CODECS="
del /q "%PROBE_JSON%" "%PROBE_TEXT%" >nul 2>&1
"%FFPROBE%" -v error -show_entries stream=index,codec_type,codec_name,pix_fmt,height,bit_rate:format=duration -of json "%INPUT_FILE%" >"%PROBE_JSON%" 2>nul
if errorlevel 1 exit /b 1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $data=Get-Content -Raw -LiteralPath $env:PROBE_JSON|ConvertFrom-Json; $video=@($data.streams|Where-Object {$_.codec_type -eq 'video'})|Select-Object -First 1; if(-not $video){throw 'Video stream not found'}; $audio=(@($data.streams|Where-Object {$_.codec_type -eq 'audio'}|ForEach-Object {[string]$_.codec_name}) -join ','); $values=@([string]$video.codec_name,[string]$video.height,[string]$video.bit_rate,[string]$video.pix_fmt,[string]$data.format.duration,[string]$audio)|ForEach-Object {if([string]::IsNullOrEmpty($_)){'NONE'}else{$_}}; [IO.File]::WriteAllText($env:PROBE_TEXT,($values -join [char]9),(New-Object Text.UTF8Encoding($false)))" >nul 2>&1
if errorlevel 1 exit /b 1
for /f "usebackq tokens=1-6 delims=	" %%A in ("%PROBE_TEXT%") do (
    set "SOURCE_VIDEO_CODEC=%%A"
    set "SOURCE_VIDEO_HEIGHT=%%B"
    set "SOURCE_VIDEO_BITRATE=%%C"
    set "SOURCE_PIXEL_FORMAT=%%D"
    set "SOURCE_DURATION=%%E"
    set "SOURCE_AUDIO_CODECS=%%F"
)
if /i "%SOURCE_VIDEO_CODEC%"=="NONE" set "SOURCE_VIDEO_CODEC="
if /i "%SOURCE_VIDEO_HEIGHT%"=="NONE" set "SOURCE_VIDEO_HEIGHT="
if /i "%SOURCE_VIDEO_BITRATE%"=="NONE" set "SOURCE_VIDEO_BITRATE="
if /i "%SOURCE_PIXEL_FORMAT%"=="NONE" set "SOURCE_PIXEL_FORMAT="
if /i "%SOURCE_DURATION%"=="NONE" set "SOURCE_DURATION="
if /i "%SOURCE_AUDIO_CODECS%"=="NONE" set "SOURCE_AUDIO_CODECS="
if not defined SOURCE_VIDEO_CODEC exit /b 1
exit /b 0

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

:keep_compatible_h264
if /i "%SOURCE_PIXEL_FORMAT%"=="yuv420p" set "TARGET_CODEC=NONE"
if /i "%SOURCE_PIXEL_FORMAT%"=="yuvj420p" set "TARGET_CODEC=NONE"
exit /b 0

:read_audio_codec
set "AUDIO_CODEC=none"
for /f "tokens=1 delims=," %%A in ("%SOURCE_AUDIO_CODECS%") do set "AUDIO_CODEC=%%A"
exit /b 0

:select_aac_action
set "AUDIO_ACTION=AAC"
if /i "%DOWNLOAD_ALL_AUDIO_TRACKS%"=="YES" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$codecs=@($env:SOURCE_AUDIO_CODECS -split ','|Where-Object {$_}); if(@($codecs|Where-Object {$_ -notmatch '^(aac|mp4a)'}).Count -gt 0){exit 1}" >nul 2>&1
    if not errorlevel 1 set "AUDIO_ACTION=COPY"
    exit /b 0
)
if /i "%AUDIO_CODEC:~0,4%"=="mp4a" set "AUDIO_ACTION=COPY"
if /i "%AUDIO_CODEC:~0,3%"=="aac" set "AUDIO_ACTION=COPY"
if /i "%AUDIO_CODEC%"=="none" set "AUDIO_ACTION=COPY"
exit /b 0

:transcode_media
for %%I in ("%INPUT_FILE%") do (
    set "OUTPUT_FILE=%%~dpnI.mp4"
    set "TEMP_OUTPUT=%%~dpnI.saf-transcoding.mp4"
    set "PASSLOG_FILE=%%~dpnI.saf-passlog"
)
del /q "%TEMP_OUTPUT%" >nul 2>&1
del /q "%PASSLOG_FILE%*" >nul 2>&1

if /i not "%TARGET_CODEC%"=="NONE" call :calculate_video_bitrate || exit /b 1
call :choose_encoder "%TARGET_CODEC%"
call :set_encoding_arguments "%SELECTED_ENCODER%"
call :set_audio_arguments

echo.
echo Transcoding with %SELECTED_ENCODER%...
call :run_ffmpeg_transcode
if errorlevel 1 if /i "%USING_HARDWARE%"=="YES" (
    echo Hardware encoding failed. Falling back to CPU...
    del /q "%TEMP_OUTPUT%" >nul 2>&1
    set "SELECTED_ENCODER=%SOFTWARE_ENCODER%"
    set "USING_HARDWARE=NO"
    call :set_encoding_arguments "%SOFTWARE_ENCODER%"
    call :run_ffmpeg_transcode
)
if errorlevel 1 (
    echo Error: transcoding failed. The downloaded source file was kept.
    del /q "%TEMP_OUTPUT%" >nul 2>&1
    del /q "%PASSLOG_FILE%*" >nul 2>&1
    exit /b 1
)
if not exist "%TEMP_OUTPUT%" (
    echo Error: FFmpeg did not create the converted file.
    exit /b 1
)

if /i not "%INPUT_FILE%"=="%OUTPUT_FILE%" if exist "%OUTPUT_FILE%" (
    echo Error: "%OUTPUT_FILE%" already exists. The downloaded source file was kept.
    del /q "%TEMP_OUTPUT%" >nul 2>&1
    exit /b 1
)

move /y "%TEMP_OUTPUT%" "%OUTPUT_FILE%" >nul
if errorlevel 1 (
    echo Error: could not save the converted file. The downloaded source file was kept.
    exit /b 1
)
if /i not "%INPUT_FILE%"=="%OUTPUT_FILE%" del /q "%INPUT_FILE%" >nul 2>&1
exit /b 0

:calculate_video_bitrate
if not defined SOURCE_VIDEO_BITRATE goto :estimate_video_bitrate
for /f "delims=0123456789" %%A in ("%SOURCE_VIDEO_BITRATE%") do goto :estimate_video_bitrate
if %SOURCE_VIDEO_BITRATE% LEQ 0 goto :estimate_video_bitrate
:calculate_video_bitrate_ready
call :validate_video_height || exit /b 1
call :select_bitrate_coefficient
set /a SOURCE_VIDEO_KBPS=SOURCE_VIDEO_BITRATE / 1000
set /a TARGET_VIDEO_BITRATE=SOURCE_VIDEO_KBPS * BITRATE_COEFFICIENT / 100
set /a TARGET_VIDEO_BITRATE=TARGET_VIDEO_BITRATE * 110 / 100
if %TARGET_VIDEO_BITRATE% LSS 1 set "TARGET_VIDEO_BITRATE=1"
set /a MAX_VIDEO_BITRATE=TARGET_VIDEO_BITRATE * 3 / 2
set /a VIDEO_BUFFER_SIZE=TARGET_VIDEO_BITRATE * 2
exit /b 0

:estimate_video_bitrate
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $culture=[Globalization.CultureInfo]::InvariantCulture; $duration=0.0; if(-not [double]::TryParse($env:SOURCE_DURATION,[Globalization.NumberStyles]::Float,$culture,[ref]$duration) -or $duration -le 0){throw 'Invalid duration'}; $bytes=0L; & $env:FFPROBE -v error -select_streams v:0 -show_entries packet=size -of csv=p=0 $env:INPUT_FILE | ForEach-Object { $size=0L; if([long]::TryParse($_,[ref]$size)){$bytes+=$size} }; if($bytes -le 0){throw 'No video packets'}; [IO.File]::WriteAllText($env:FFPROBE_OUTPUT,[string][math]::Round($bytes*8/$duration),[Text.Encoding]::ASCII)" >nul 2>&1
if errorlevel 1 (
    echo Error: could not determine the source video bitrate.
    exit /b 1
)
if exist "%FFPROBE_OUTPUT%" set /p "SOURCE_VIDEO_BITRATE="<"%FFPROBE_OUTPUT%"
del /q "%FFPROBE_OUTPUT%" >nul 2>&1
goto :calculate_video_bitrate_ready

:validate_video_height
if not defined SOURCE_VIDEO_HEIGHT (
    echo Error: could not determine the source video height.
    exit /b 1
)
for /f "delims=0123456789" %%A in ("%SOURCE_VIDEO_HEIGHT%") do (
    echo Error: could not determine the source video height.
    exit /b 1
)
exit /b 0

:select_bitrate_coefficient
set "SOURCE_CODEC_FAMILY=%SOURCE_CODEC%"

set "RESOLUTION_BAND=LOW"
if %SOURCE_VIDEO_HEIGHT% GTR 720 set "RESOLUTION_BAND=HD"
if %SOURCE_VIDEO_HEIGHT% GTR 1080 set "RESOLUTION_BAND=UHD"
set "BITRATE_COEFFICIENT=100"

if /i "%SOURCE_CODEC_FAMILY%"=="H264" if /i "%TARGET_CODEC%"=="H265" set "BITRATE_COEFFICIENT=80"
if /i "%SOURCE_CODEC_FAMILY%"=="H264" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=70"
if /i "%SOURCE_CODEC_FAMILY%"=="VP9" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=95"
if /i "%SOURCE_CODEC_FAMILY%"=="H265" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=90"
if /i "%SOURCE_CODEC_FAMILY%"=="VP9" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=125"
if /i "%SOURCE_CODEC_FAMILY%"=="H265" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=125"
if /i "%SOURCE_CODEC_FAMILY%"=="AV1" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=143"
if /i "%SOURCE_CODEC_FAMILY%"=="AV1" if /i "%TARGET_CODEC%"=="H265" set "BITRATE_COEFFICIENT=111"

if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="H264" if /i "%TARGET_CODEC%"=="H265" set "BITRATE_COEFFICIENT=70"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="H264" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=60"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="VP9" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=90"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="H265" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=85"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="VP9" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=143"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="H265" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=143"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="AV1" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=167"
if /i "%RESOLUTION_BAND%"=="HD" if /i "%SOURCE_CODEC_FAMILY%"=="AV1" if /i "%TARGET_CODEC%"=="H265" set "BITRATE_COEFFICIENT=118"

if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="H264" if /i "%TARGET_CODEC%"=="H265" set "BITRATE_COEFFICIENT=60"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="H264" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=50"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="VP9" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=80"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="H265" if /i "%TARGET_CODEC%"=="AV1" set "BITRATE_COEFFICIENT=85"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="VP9" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=167"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="H265" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=167"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="AV1" if /i "%TARGET_CODEC%"=="H264" set "BITRATE_COEFFICIENT=200"
if /i "%RESOLUTION_BAND%"=="UHD" if /i "%SOURCE_CODEC_FAMILY%"=="AV1" if /i "%TARGET_CODEC%"=="H265" set "BITRATE_COEFFICIENT=118"
exit /b 0

:choose_encoder
set "USING_HARDWARE=NO"
if /i "%~1"=="NONE" (
    set "SOFTWARE_ENCODER=copy"
    set "SELECTED_ENCODER=copy"
    exit /b 0
)
if /i "%~1"=="AV1" set "SOFTWARE_ENCODER=libsvtav1"
if /i "%~1"=="H265" set "SOFTWARE_ENCODER=libx265"
if /i "%~1"=="H264" set "SOFTWARE_ENCODER=libx264"
set "SELECTED_ENCODER=%SOFTWARE_ENCODER%"
if /i not "%ALLOW_HARDWARE_TRANSCODING%"=="YES" exit /b 0

if /i "%~1"=="AV1" call :try_hardware_encoder av1_nvenc av1_qsv av1_amf
if /i "%~1"=="H265" call :try_hardware_encoder hevc_nvenc hevc_qsv hevc_amf
if /i "%~1"=="H264" call :try_hardware_encoder h264_nvenc h264_qsv h264_amf
exit /b 0

:try_hardware_encoder
call :probe_hardware_encoder "%~1"
if not errorlevel 1 (
    set "SELECTED_ENCODER=%~1"
    set "USING_HARDWARE=YES"
    exit /b 0
)
call :probe_hardware_encoder "%~2"
if not errorlevel 1 (
    set "SELECTED_ENCODER=%~2"
    set "USING_HARDWARE=YES"
    exit /b 0
)
call :probe_hardware_encoder "%~3"
if not errorlevel 1 (
    set "SELECTED_ENCODER=%~3"
    set "USING_HARDWARE=YES"
)
exit /b 0

:probe_hardware_encoder
"%FFMPEG%" -hide_banner -loglevel error -f lavfi -i "color=c=black:s=256x144:r=30:d=0.1" -frames:v 1 -an -c:v "%~1" -f null NUL >nul 2>&1
exit /b %errorlevel%

:set_encoding_arguments
set "VIDEO_ARGS=-c:v %~1"
set "METADATA_ARGS="
if /i "%~1"=="copy" exit /b 0
set "METADATA_ARGS=-metadata:s:v:0 "handler_name=Transcoded from %SOURCE_CODEC_FAMILY% by SaF yt-dlp Wrapper""
set "ENCODE_VIDEO_BITRATE=%TARGET_VIDEO_BITRATE%"
if /i "%USING_HARDWARE%"=="YES" set /a ENCODE_VIDEO_BITRATE=TARGET_VIDEO_BITRATE * 110 / 100
set /a ENCODE_MAX_BITRATE=ENCODE_VIDEO_BITRATE * 3 / 2
set /a ENCODE_BUFFER_SIZE=ENCODE_VIDEO_BITRATE * 2
if /i "%~1"=="libsvtav1" set "VIDEO_ARGS=-c:v libsvtav1 -preset 6 -b:v %ENCODE_VIDEO_BITRATE%k"
if /i "%~1"=="libx265" set "VIDEO_ARGS=-c:v libx265 -preset medium -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -tag:v hvc1"
if /i "%~1"=="libx264" set "VIDEO_ARGS=-c:v libx264 -preset medium -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -pix_fmt yuv420p"
if /i "%~1"=="av1_nvenc" set "VIDEO_ARGS=-c:v av1_nvenc -preset p6 -tune hq -rc vbr -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32"
if /i "%~1"=="hevc_nvenc" set "VIDEO_ARGS=-c:v hevc_nvenc -preset p6 -tune hq -rc vbr -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32 -tag:v hvc1"
if /i "%~1"=="h264_nvenc" set "VIDEO_ARGS=-c:v h264_nvenc -preset p6 -tune hq -rc vbr -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32 -pix_fmt yuv420p"
if /i "%~1"=="av1_qsv" set "VIDEO_ARGS=-c:v av1_qsv -preset slow -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k"
if /i "%~1"=="hevc_qsv" set "VIDEO_ARGS=-c:v hevc_qsv -preset slow -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -tag:v hvc1"
if /i "%~1"=="h264_qsv" set "VIDEO_ARGS=-c:v h264_qsv -preset slow -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -pix_fmt yuv420p"
if /i "%~1"=="av1_amf" set "VIDEO_ARGS=-c:v av1_amf -usage high_quality -quality high_quality -rc vbr_peak -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k"
if /i "%~1"=="hevc_amf" set "VIDEO_ARGS=-c:v hevc_amf -usage high_quality -quality high_quality -rc vbr_peak -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -tag:v hvc1"
if /i "%~1"=="h264_amf" set "VIDEO_ARGS=-c:v h264_amf -usage high_quality -quality high_quality -rc vbr_peak -b:v %ENCODE_VIDEO_BITRATE%k -maxrate %ENCODE_MAX_BITRATE%k -bufsize %ENCODE_BUFFER_SIZE%k -pix_fmt yuv420p"
exit /b 0

:set_audio_arguments
set "AUDIO_ARGS=-c:a copy"
if /i "%AUDIO_ACTION%"=="AAC" set "AUDIO_ARGS=-c:a aac -b:a 192k"
exit /b 0

:run_ffmpeg_transcode
if /i "%SELECTED_ENCODER%"=="copy" goto :run_single_pass_transcode
if /i "%USING_HARDWARE%"=="YES" goto :run_single_pass_transcode
"%FFMPEG%" -y -hide_banner -i "%INPUT_FILE%" -map 0:v:0 -an -sn -dn %VIDEO_ARGS% -pass 1 -passlogfile "%PASSLOG_FILE%" -f null NUL
set "FFMPEG_RESULT=%errorlevel%"
if not "%FFMPEG_RESULT%"=="0" (
    del /q "%PASSLOG_FILE%*" >nul 2>&1
    exit /b 1
)
"%FFMPEG%" -y -hide_banner -i "%INPUT_FILE%" -map 0:v:0 -map 0:a? -map_metadata 0 -map_chapters 0 %METADATA_ARGS% %AUDIO_METADATA_ARGS% %VIDEO_ARGS% -pass 2 -passlogfile "%PASSLOG_FILE%" %AUDIO_ARGS% -movflags +faststart "%TEMP_OUTPUT%"
set "FFMPEG_RESULT=%errorlevel%"
del /q "%PASSLOG_FILE%*" >nul 2>&1
if not "%FFMPEG_RESULT%"=="0" exit /b 1
exit /b 0

:run_single_pass_transcode
"%FFMPEG%" -y -hide_banner -i "%INPUT_FILE%" -map 0:v:0 -map 0:a? -map_metadata 0 -map_chapters 0 %METADATA_ARGS% %AUDIO_METADATA_ARGS% %VIDEO_ARGS% %AUDIO_ARGS% -movflags +faststart "%TEMP_OUTPUT%"
set "FFMPEG_RESULT=%errorlevel%"
if not "%FFMPEG_RESULT%"=="0" exit /b 1
exit /b 0

:set_audio_metadata_arguments
set "AUDIO_METADATA_ARGS="
set "SAF_AUDIO_LANGUAGE_INPUT=%~1"
set "AUDIO_LANGUAGE_REMAINDER="
for /f "usebackq delims=" %%L in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$items=@($env:SAF_AUDIO_LANGUAGE_INPUT -split '\+' ); $metadata=New-Object 'Collections.Generic.List[string]'; $cultures=[Globalization.CultureInfo]::GetCultures([Globalization.CultureTypes]::AllCultures); foreach($item in $items){$raw=([string]$item).Trim(); $iso='und'; $name='Unknown'; if($raw -and $raw -notmatch '^(?i:und)$' -and $raw -match '^[A-Za-z0-9-]+$'){ $primary=($raw -split '-',2)[0]; $culture=$null; try{$culture=[Globalization.CultureInfo]::GetCultureInfo($raw)}catch{}; if($culture -and ([string]$culture.EnglishName) -match '^Unknown (Language|Locale)'){$culture=$null}; if(-not $culture -and $primary -ne $raw){try{$culture=[Globalization.CultureInfo]::GetCultureInfo($primary)}catch{}; if($culture -and ([string]$culture.EnglishName) -match '^Unknown (Language|Locale)'){$culture=$null}}; if(-not $culture -and $primary -match '^[A-Za-z]{3}$'){foreach($candidate in $cultures){if(([string]$candidate.ThreeLetterISOLanguageName) -ieq $primary){$culture=$candidate; if($candidate.IsNeutralCulture){break}}}}; if($culture -and ([string]$culture.ThreeLetterISOLanguageName) -match '^[A-Za-z]{3}$' -and $culture.ThreeLetterISOLanguageName -ne 'ivl'){ $iso=$culture.ThreeLetterISOLanguageName.ToLowerInvariant(); $name=[string]$culture.EnglishName } elseif($primary -match '^[A-Za-z]{3}$'){ $iso=$primary.ToLowerInvariant(); $name=$primary.ToUpperInvariant() } }; $safeName=(([string]$name -replace '[^A-Za-z0-9]+','-').Trim('-')); if(-not $safeName){$safeName='Unknown'}; $metadata.Add($iso+'='+$safeName) }; [Console]::Write(($metadata -join '+'))"`) do set "AUDIO_LANGUAGE_REMAINDER=%%L"
set "SAF_AUDIO_LANGUAGE_INPUT="
set /a AUDIO_METADATA_INDEX=0
:set_audio_metadata_arguments_loop
if not defined AUDIO_LANGUAGE_REMAINDER exit /b 0
for /f "tokens=1,* delims=+" %%A in ("%AUDIO_LANGUAGE_REMAINDER%") do (
    set "AUDIO_METADATA_ITEM=%%A"
    set "AUDIO_LANGUAGE_REMAINDER=%%B"
)
for /f "tokens=1,* delims==" %%A in ("%AUDIO_METADATA_ITEM%") do (
    set "AUDIO_METADATA_LANGUAGE=%%A"
    set "AUDIO_METADATA_NAME=%%B"
)
call set "AUDIO_METADATA_ARGS=%%AUDIO_METADATA_ARGS%% -metadata:s:a:%AUDIO_METADATA_INDEX% language=%AUDIO_METADATA_LANGUAGE%"
call set "AUDIO_METADATA_ARGS=%%AUDIO_METADATA_ARGS%% -metadata:s:a:%AUDIO_METADATA_INDEX% handler_name=%AUDIO_METADATA_NAME%"
if "%AUDIO_METADATA_INDEX%"=="0" (
    call set "AUDIO_METADATA_ARGS=%%AUDIO_METADATA_ARGS%% -disposition:a:%AUDIO_METADATA_INDEX% default"
) else (
    call set "AUDIO_METADATA_ARGS=%%AUDIO_METADATA_ARGS%% -disposition:a:%AUDIO_METADATA_INDEX% 0"
)
set /a AUDIO_METADATA_INDEX+=1
goto :set_audio_metadata_arguments_loop

rem === Utilities ===

:set_errorlevel
exit /b %~1

:select_windows_dependencies
set "WINDOWS_ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "WINDOWS_ARCH=%PROCESSOR_ARCHITEW6432%"
set "PLATFORM_ID="
set "YTDLP_ASSET="
set "DENO_ASSET="
set "FFMPEG_ASSET="
if /i "%WINDOWS_ARCH%"=="AMD64" (
    set "PLATFORM_ID=windows-x64"
    set "YTDLP_ASSET=yt-dlp.exe"
    set "DENO_ASSET=deno-x86_64-pc-windows-msvc.zip"
    set "FFMPEG_ASSET=ffmpeg-master-latest-win64-gpl.zip"
)
if /i "%WINDOWS_ARCH%"=="ARM64" (
    set "PLATFORM_ID=windows-arm64"
    set "YTDLP_ASSET=yt-dlp_arm64.exe"
    set "DENO_ASSET=deno-aarch64-pc-windows-msvc.zip"
    set "FFMPEG_ASSET=ffmpeg-master-latest-winarm64-gpl.zip"
)
if not defined PLATFORM_ID (
    echo Error: this wrapper supports Windows x86_64 and ARM64.
    exit /b 1
)
set "YTDLP_URL=https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/%YTDLP_ASSET%"
set "DENO_URL=https://github.com/denoland/deno/releases/latest/download/%DENO_ASSET%"
set "FFMPEG_URL=https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/%FFMPEG_ASSET%"
exit /b 0

:load_config
if not exist "%CONFIG%" (
    echo Error: config.ini was not found next to the script.
    exit /b 1
)

for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if /i "%%A"=="MAX_HEIGHT" set "MAX_HEIGHT=%%B"
    if /i "%%A"=="DEFAULT_MODE" set "DEFAULT_MODE=%%B"
    if /i "%%A"=="PROFILE" set "PROFILE=%%B"
    if /i "%%A"=="TRANSCODE_VP9_TO_AV1" set "TRANSCODE_VP9_TO_AV1=%%B"
    if /i "%%A"=="ALLOW_HARDWARE_TRANSCODING" set "ALLOW_HARDWARE_TRANSCODING=%%B"
    if /i "%%A"=="STORE_OPUS_IN_MP4" set "STORE_OPUS_IN_MP4=%%B"
    if /i "%%A"=="DOWNLOAD_ALL_AUDIO_TRACKS" set "DOWNLOAD_ALL_AUDIO_TRACKS=%%B"
    if /i "%%A"=="COOKIE_BROWSER" set "COOKIE_BROWSER=%%B"
)

if not defined MAX_HEIGHT (
    echo Error: Invalid MAX_HEIGHT. Use 0 or a positive integer.
    exit /b 1
)
for /f "delims=0123456789" %%A in ("%MAX_HEIGHT%") do (
    echo Error: Invalid MAX_HEIGHT. Use 0 or a positive integer.
    exit /b 1
)

set "VALID_DEFAULT_MODE=NO"
if /i "%DEFAULT_MODE%"=="video" set "VALID_DEFAULT_MODE=YES"
if /i "%DEFAULT_MODE%"=="audio" set "VALID_DEFAULT_MODE=YES"
if /i "%DEFAULT_MODE%"=="thumbnail" set "VALID_DEFAULT_MODE=YES"
if /i "%VALID_DEFAULT_MODE%"=="NO" (
    echo Error: Invalid DEFAULT_MODE. Use video, audio, or thumbnail.
    exit /b 1
)

set "VALID_PROFILE=NO"
if /i "%PROFILE%"=="QUALITY" set "VALID_PROFILE=YES"
if /i "%PROFILE%"=="MODERN" set "VALID_PROFILE=YES"
if /i "%PROFILE%"=="UNIVERSAL" set "VALID_PROFILE=YES"
if /i "%VALID_PROFILE%"=="NO" (
    echo Error: Invalid PROFILE. Use QUALITY, MODERN, or UNIVERSAL.
    exit /b 1
)

call :validate_yes_no "TRANSCODE_VP9_TO_AV1" "%TRANSCODE_VP9_TO_AV1%" || exit /b 1
call :validate_yes_no "ALLOW_HARDWARE_TRANSCODING" "%ALLOW_HARDWARE_TRANSCODING%" || exit /b 1
call :validate_yes_no "STORE_OPUS_IN_MP4" "%STORE_OPUS_IN_MP4%" || exit /b 1
call :validate_yes_no "DOWNLOAD_ALL_AUDIO_TRACKS" "%DOWNLOAD_ALL_AUDIO_TRACKS%" || exit /b 1
if defined COOKIE_BROWSER (
    set "VALID_COOKIE_BROWSER=NO"
    if /i "%COOKIE_BROWSER%"=="chrome" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="edge" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="firefox" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="opera" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="brave" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="vivaldi" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="comet" set "VALID_COOKIE_BROWSER=YES"
    if /i "%COOKIE_BROWSER%"=="zen" set "VALID_COOKIE_BROWSER=YES"
    if /i "!VALID_COOKIE_BROWSER!"=="NO" (
        echo Error: Invalid COOKIE_BROWSER. Use chrome, edge, firefox, opera, brave, vivaldi, comet, or zen.
        exit /b 1
    )
)
exit /b 0

:validate_yes_no
if /i "%~2"=="YES" exit /b 0
if /i "%~2"=="NO" exit /b 0
echo Error: Invalid %~1. Use YES or NO.
exit /b 1

rem === Dependencies ===

:update_ytdlp
del /q "%YTDLP_NEW%" >nul 2>&1
copy /y "%YTDLP%" "%YTDLP_NEW%" >nul || exit /b 1
call "%YTDLP_NEW%" --update-to nightly
if errorlevel 1 (
    del /q "%YTDLP_NEW%" >nul 2>&1
    exit /b 1
)
call "%YTDLP_NEW%" --version >nul 2>&1
if errorlevel 1 (
    del /q "%YTDLP_NEW%" >nul 2>&1
    exit /b 1
)
move /y "%YTDLP_NEW%" "%YTDLP%" >nul
exit /b %errorlevel%

:prepare_setup_job
:choose_setup_job
set "JOB_SETUP=%TEMP_ROOT%\setup-!RANDOM!-!RANDOM!"
if exist "!JOB_SETUP!" goto :choose_setup_job
mkdir "!JOB_SETUP!" >nul 2>&1
exit /b %errorlevel%

:cleanup_setup_job
if defined JOB_SETUP if exist "%JOB_SETUP%" rmdir /s /q "%JOB_SETUP%" >nul 2>&1
set "JOB_SETUP="
exit /b 0

:install_ytdlp
echo Downloading yt-dlp nightly...
call :prepare_setup_job || exit /b 1
set "SAF_DOWNLOAD_URL=%YTDLP_URL%"
set "SAF_DOWNLOAD_FILE=%JOB_SETUP%\%YTDLP_ASSET%.part"
call :download_file
if errorlevel 1 (
    call :cleanup_setup_job
    echo Error: could not download yt-dlp.
    exit /b 1
)
copy /y "%SAF_DOWNLOAD_FILE%" "%YTDLP_NEW%" >nul
call "%YTDLP_NEW%" --version >nul 2>&1
if errorlevel 1 (
    del /q "%YTDLP_NEW%" >nul 2>&1
    call :cleanup_setup_job
    echo Error: downloaded yt-dlp did not run.
    exit /b 1
)
move /y "%YTDLP_NEW%" "%YTDLP%" >nul
set "INSTALL_RESULT=%errorlevel%"
call :cleanup_setup_job
if not "%INSTALL_RESULT%"=="0" exit /b %INSTALL_RESULT%
exit /b 0

:install_deno
echo Downloading Deno...
call :prepare_setup_job || exit /b 1
set "SAF_DOWNLOAD_URL=%DENO_URL%"
set "SAF_DOWNLOAD_FILE=%JOB_SETUP%\%DENO_ASSET%.part"
call :download_file
if errorlevel 1 (
    call :cleanup_setup_job
    echo Error: could not download Deno.
    exit /b 1
)

set "SAF_ARCHIVE=%SAF_DOWNLOAD_FILE%"
set "SAF_EXTRACT_DIR=%JOB_SETUP%\deno-unpack"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $env:SAF_ARCHIVE -DestinationPath $env:SAF_EXTRACT_DIR -Force; $deno=Get-ChildItem -LiteralPath $env:SAF_EXTRACT_DIR -Filter deno.exe -File -Recurse|Select-Object -First 1; if(-not $deno){throw 'deno.exe not found in archive'}; Copy-Item -LiteralPath $deno.FullName -Destination $env:DENO_NEW -Force"
if errorlevel 1 (
    del /q "%DENO_NEW%" >nul 2>&1
    call :cleanup_setup_job
    echo Error: could not extract Deno.
    exit /b 1
)
call "%DENO_NEW%" --version >nul 2>&1
if errorlevel 1 (
    del /q "%DENO_NEW%" >nul 2>&1
    call :cleanup_setup_job
    echo Error: downloaded Deno did not run.
    exit /b 1
)
move /y "%DENO_NEW%" "%DENO%" >nul
set "INSTALL_RESULT=%errorlevel%"
call :cleanup_setup_job
if not "%INSTALL_RESULT%"=="0" exit /b %INSTALL_RESULT%
exit /b 0

:install_ffmpeg
echo Downloading FFmpeg. This is a large one-time download...
call :prepare_setup_job || exit /b 1
set "SAF_DOWNLOAD_URL=%FFMPEG_URL%"
set "SAF_DOWNLOAD_FILE=%JOB_SETUP%\%FFMPEG_ASSET%.part"
call :download_file
if errorlevel 1 (
    call :cleanup_setup_job
    echo Error: could not download FFmpeg.
    exit /b 1
)

set "SAF_ARCHIVE=%SAF_DOWNLOAD_FILE%"
set "SAF_EXTRACT_DIR=%JOB_SETUP%\ffmpeg-unpack"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $env:SAF_ARCHIVE -DestinationPath $env:SAF_EXTRACT_DIR -Force; $ffmpeg=Get-ChildItem -LiteralPath $env:SAF_EXTRACT_DIR -Filter ffmpeg.exe -File -Recurse|Select-Object -First 1; $ffprobe=Get-ChildItem -LiteralPath $env:SAF_EXTRACT_DIR -Filter ffprobe.exe -File -Recurse|Select-Object -First 1; if(-not $ffmpeg -or -not $ffprobe){throw 'FFmpeg executables not found in archive'}; Copy-Item -LiteralPath $ffmpeg.FullName -Destination $env:FFMPEG_NEW -Force; Copy-Item -LiteralPath $ffprobe.FullName -Destination $env:FFPROBE_NEW -Force"
if errorlevel 1 (
    del /q "%FFMPEG_NEW%" "%FFPROBE_NEW%" >nul 2>&1
    call :cleanup_setup_job
    echo Error: could not extract FFmpeg.
    exit /b 1
)
call "%FFPROBE_NEW%" -version >nul 2>&1
if errorlevel 1 goto :install_ffmpeg_invalid
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$text=& $env:FFMPEG_NEW -hide_banner -encoders|Out-String; if($LASTEXITCODE -ne 0 -or $text -notmatch 'libx264' -or $text -notmatch 'libx265' -or $text -notmatch 'libsvtav1'){exit 1}" >nul 2>&1
if errorlevel 1 goto :install_ffmpeg_invalid
move /y "%FFMPEG_NEW%" "%FFMPEG%" >nul
if errorlevel 1 goto :install_ffmpeg_invalid
move /y "%FFPROBE_NEW%" "%FFPROBE%" >nul
if errorlevel 1 goto :install_ffmpeg_invalid
call :cleanup_setup_job
exit /b 0

:install_ffmpeg_invalid
del /q "%FFMPEG_NEW%" "%FFPROBE_NEW%" >nul 2>&1
call :cleanup_setup_job
echo Error: downloaded FFmpeg did not pass validation.
exit /b 1

:download_file
if /i "%SAF_TEST_DOWNLOAD_FAILURE%"=="YES" (
    type nul >"%SAF_DOWNLOAD_FILE%"
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri $env:SAF_DOWNLOAD_URL -OutFile $env:SAF_DOWNLOAD_FILE"
exit /b %errorlevel%

:internal_process_entry
setlocal DisableDelayedExpansion
call :select_windows_dependencies || (endlocal & exit /b 1)
call :load_config || (endlocal & exit /b 1)
set "QUEUED_INPUT=%SAF_QUEUED_INPUT%"
set "QUEUED_VIDEO_CODEC=%SAF_QUEUED_VIDEO_CODEC%"
set "QUEUED_AUDIO_CODEC=%SAF_QUEUED_AUDIO_CODEC%"
set "QUEUED_AUDIO_LANGUAGES=%SAF_QUEUED_AUDIO_LANGUAGES%"
call :process_download
set "INTERNAL_RESULT=%errorlevel%"
endlocal & exit /b %INTERNAL_RESULT%

:internal_dependency_map
call :select_windows_dependencies || exit /b 1
echo PLATFORM=%PLATFORM_ID%
echo YTDLP_URL=%YTDLP_URL%
echo DENO_URL=%DENO_URL%
echo FFMPEG_URL=%FFMPEG_URL%
exit /b 0

:fatal
call :cleanup_job >nul 2>&1
echo.
echo Setup failed.
pause >nul
exit /b 1

:success_exit
call :cleanup_job >nul 2>&1
exit /b 0

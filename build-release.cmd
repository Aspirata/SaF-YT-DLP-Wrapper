@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
    set "SOURCE_ROOT=%~dp0"
) else (
    for %%I in ("%~1") do set "SOURCE_ROOT=%%~fI"
)

if "%~2"=="" (
    set "OUTPUT_DIRECTORY=%SOURCE_ROOT%\dist"
) else (
    for %%I in ("%~2") do set "OUTPUT_DIRECTORY=%%~fI"
)

set "SYSTEM_TAR=%SystemRoot%\System32\tar.exe"
set "CERTUTIL=%SystemRoot%\System32\certutil.exe"
set "GNU_TAR=%~3"
if not defined GNU_TAR if defined SAF_GNU_TAR set "GNU_TAR=%SAF_GNU_TAR%"

if defined GNU_TAR (
    call :ValidateGnuTar "%GNU_TAR%"
) else (
    call :FindGnuTar
)

if not exist "%SYSTEM_TAR%" (
    set "ERROR_MESSAGE=The Windows system tar.exe is required to create the ZIP archive."
    goto :Failure
)
if not exist "%CERTUTIL%" (
    set "ERROR_MESSAGE=The Windows system certutil.exe is required to create the Unix release configuration."
    goto :Failure
)
if not defined GNU_TAR (
    set "ERROR_MESSAGE=GNU tar is required to preserve the executable permission in the Unix release. Install Git for Windows or set SAF_GNU_TAR."
    goto :Failure
)

for %%F in (README.md LICENSE SaF-YTDLP.cmd SaF-YTDLP.sh) do (
    if not exist "%SOURCE_ROOT%\%%F" (
        set "ERROR_MESSAGE=Required release file is missing: %%F"
        goto :Failure
    )
)

:ChooseStagingDirectory
set "STAGING=%TEMP%\saf-release-%RANDOM%-%RANDOM%-%RANDOM%"
if exist "%STAGING%" goto :ChooseStagingDirectory
set "WINDOWS_STAGE=%STAGING%\windows"
set "UNIX_STAGE=%STAGING%\unix"
set "WINDOWS_ARCHIVE=%OUTPUT_DIRECTORY%\SaF-yt-dlp-Wrapper-Windows.zip"
set "UNIX_ARCHIVE=%OUTPUT_DIRECTORY%\SaF-yt-dlp-Wrapper-Unix.tar.gz"

md "%WINDOWS_STAGE%" >nul 2>&1
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the temporary Windows staging directory."
    goto :Failure
)
md "%UNIX_STAGE%" >nul 2>&1
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the temporary Unix staging directory."
    goto :Failure
)
md "%OUTPUT_DIRECTORY%" >nul 2>&1
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the release output directory."
    goto :Failure
)

for %%F in (README.md LICENSE) do (
    copy /y "%SOURCE_ROOT%\%%F" "%WINDOWS_STAGE%\%%F" >nul
    if errorlevel 1 goto :CopyFailure
    copy /y "%SOURCE_ROOT%\%%F" "%UNIX_STAGE%\%%F" >nul
    if errorlevel 1 goto :CopyFailure
)
copy /y "%SOURCE_ROOT%\SaF-YTDLP.cmd" "%WINDOWS_STAGE%\SaF-YTDLP.cmd" >nul
if errorlevel 1 goto :CopyFailure
copy /y "%SOURCE_ROOT%\SaF-YTDLP.sh" "%UNIX_STAGE%\SaF-YTDLP.sh.exe" >nul
if errorlevel 1 goto :CopyFailure

>"%WINDOWS_STAGE%\config.ini" (
    echo PROFILE=MODERN
    echo MAX_HEIGHT=1080
    echo DEFAULT_MODE=video
    echo TRANSCODE_VP9_TO_AV1=YES
    echo ALLOW_HARDWARE_TRANSCODING=YES
    echo STORE_OPUS_IN_MP4=YES
    echo DOWNLOAD_ALL_AUDIO_TRACKS=NO
    echo COOKIE_BROWSER=
)
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the Windows release configuration."
    goto :Failure
)
>"%STAGING%\config.hex" (
    echo 50 52 4F 46 49 4C 45 3D 4D 4F 44 45 52 4E 0A 4D 41 58 5F 48 45 49 47 48
    echo 54 3D 31 30 38 30 0A 44 45 46 41 55 4C 54 5F 4D 4F 44 45 3D 76 69 64 65
    echo 6F 0A 54 52 41 4E 53 43 4F 44 45 5F 56 50 39 5F 54 4F 5F 41 56 31 3D 59
    echo 45 53 0A 41 4C 4C 4F 57 5F 48 41 52 44 57 41 52 45 5F 54 52 41 4E 53 43
    echo 4F 44 49 4E 47 3D 59 45 53 0A 53 54 4F 52 45 5F 4F 50 55 53 5F 49 4E 5F
    echo 4D 50 34 3D 59 45 53 0A 44 4F 57 4E 4C 4F 41 44 5F 41 4C 4C 5F 41 55 44
    echo 49 4F 5F 54 52 41 43 4B 53 3D 59 45 53 0A 43 4F 4F 4B 49 45 5F 42 52 4F
    echo 57 53 45 52 3D 0A
)
"%CERTUTIL%" -f -decodehex "%STAGING%\config.hex" "%UNIX_STAGE%\config.ini" 12 >nul 2>&1
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the Unix release configuration."
    goto :Failure
)

del /q "%WINDOWS_ARCHIVE%" "%UNIX_ARCHIVE%" >nul 2>&1

"%SYSTEM_TAR%" -acf "%WINDOWS_ARCHIVE%" -C "%WINDOWS_STAGE%" SaF-YTDLP.cmd config.ini README.md LICENSE
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the Windows release archive."
    goto :Failure
)

"%GNU_TAR%" -czf "%UNIX_ARCHIVE%" -C "%UNIX_STAGE%" "--transform=s/\.exe$//" "--mode=a=rX,u+w" SaF-YTDLP.sh.exe config.ini README.md LICENSE
if errorlevel 1 (
    set "ERROR_MESSAGE=Could not create the Unix release archive."
    goto :Failure
)

echo Created %WINDOWS_ARCHIVE%
echo Created %UNIX_ARCHIVE%
call :Cleanup
exit /b 0

:CopyFailure
set "ERROR_MESSAGE=Could not copy a required release file."
goto :Failure

:Failure
>&2 echo Error: %ERROR_MESSAGE%
call :Cleanup
exit /b 1

:Cleanup
if defined STAGING if exist "%STAGING%" rd /s /q "%STAGING%" >nul 2>&1
exit /b 0

:ValidateGnuTar
set "GNU_TAR_CANDIDATE=%~f1"
if not exist "%GNU_TAR_CANDIDATE%" (
    set "GNU_TAR="
    exit /b 1
)
"%GNU_TAR_CANDIDATE%" --help 2>&1 | "%SystemRoot%\System32\findstr.exe" /c:"--mode=CHANGES" >nul
if errorlevel 1 (
    set "GNU_TAR="
    exit /b 1
)
set "GNU_TAR=%GNU_TAR_CANDIDATE%"
exit /b 0

:FindGnuTar
call :ValidateGnuTar "%ProgramFiles%\Git\usr\bin\tar.exe"
if defined GNU_TAR exit /b 0
if defined ProgramFiles(x86) call :ValidateGnuTar "%ProgramFiles(x86)%\Git\usr\bin\tar.exe"
if defined GNU_TAR exit /b 0
for /f "delims=" %%G in ('where git.exe 2^>nul') do call :TryGitDirectory "%%~fG"
exit /b 0

:TryGitDirectory
if defined GNU_TAR exit /b 0
for %%R in ("%~dp1..") do call :ValidateGnuTar "%%~fR\usr\bin\tar.exe"
exit /b 0

# Simple and Flexible yt-dlp Wrapper

A small portable wrapper for downloading YouTube videos, playlists, audio, thumbnails, chapters, metadata, and multiple language tracks with yt-dlp.

## What it does

- Downloads a YouTube video or playlist as video, audio only, or thumbnails only.
- Chooses formats by resolution and frame rate first, then by the selected compatibility profile.
- Limits video to 1080p by default.
- Downloads one best audio track for every available language by default.
- Embeds YouTube chapters and metadata in video and audio downloads.
- Uses hardware video encoding when possible and automatically retries on the CPU if it fails.
- Keeps a downloaded source file when conversion fails.
- Downloads and updates its own portable yt-dlp, Deno, FFmpeg, and FFprobe copies.

Other sites are not supported or tested.

## Supported systems

- Windows x86_64 and ARM64
- Linux x86_64 and ARM64
- macOS x86_64 and Apple Silicon ARM64

An internet connection is required on first start. The launchers use only files inside their own folder and do not require administrator access.

## Quick start (Windows)

1. Extract the Windows release archive.
2. Run `SaF-YTDLP.cmd`.
3. Paste a YouTube video or playlist URL.
4. Choose video, audio, or thumbnail mode. Press Enter to use the configured default.

The first run downloads the correct dependencies for Windows x86_64 or ARM64. Finished files appear in `Downloads`.

## Quick start (Linux and macOS)

1. Extract the Unix release archive.
2. Open a terminal in the extracted folder.
3. Run `chmod +x SaF-YTDLP.sh` if the executable permission was lost while copying the file.
4. Run `./SaF-YTDLP.sh` and paste a YouTube URL.

The first run downloads the correct dependencies for the current Linux or macOS architecture. The script requires Bash 3.2 or newer and the standard `curl`, `unzip`, `tar`, and `gzip` utilities.

## Profiles

Resolution and frame rate always have priority over codec preference.

- `QUALITY` keeps the best source codecs whenever possible. At equal resolution and frame rate, native AV1 is preferred to VP9. When `TRANSCODE_VP9_TO_AV1=YES`, downloaded VP9 is converted to AV1 only when native AV1 was unavailable.
- `MODERN` produces editing-friendly MP4. At equal resolution and frame rate, it prefers H.265, H.264, AV1, then VP9. Compatible native H.265 and H.264 are copied without video re-encoding; other video is converted to H.265 when needed. Audio is stored as AAC.
- `UNIVERSAL` produces H.264 8-bit MP4 with AAC audio. Compatible native H.264 is copied without video re-encoding. Audio-only downloads are converted to high-quality MP3.

Software video encoding uses two-pass VBR. Hardware encoding uses one pass. The wrapper preserves metadata and chapters during remuxing or transcoding.

## Configuration

Edit `config.ini` in a text editor:

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

- A `MAX_HEIGHT` value of `0` removes the resolution limit.
- `DEFAULT_MODE` accepts `video`, `audio`, or `thumbnail`.
- `STORE_OPUS_IN_MP4=YES` stores Quality audio-only Opus in MP4 for applications that do not accept `.opus` or `.mka`.
- `COOKIE_BROWSER` is filled automatically after a browser cookie source works. Leave it empty to start with automatic detection.

Invalid profile, mode, number, or YES/NO values stop the program before downloading.

## Multiple audio tracks

With `DOWNLOAD_ALL_AUDIO_TRACKS=YES`, the wrapper selects one best stream for every language exposed by YouTube and stores the streams as separate tracks in one output file. It also keeps languages available only in combined video-and-audio formats.

For video, Modern and Universal use AAC; if every selected track is already AAC, it is copied. Quality keeps source audio when possible. Audio-only Quality uses Opus in MKA, or MP4 when `STORE_OPUS_IN_MP4=YES`; Modern and Universal use multitrack M4A. Language tags and readable track names are embedded.

Set `DOWNLOAD_ALL_AUDIO_TRACKS` to `NO` for the traditional single-track behavior.

## Browser cookies

The wrapper uses the browser saved in `COOKIE_BROWSER` directly, without a separate cookie probe. If that browser fails before downloading, or if no browser is saved, it checks common Chrome/Chromium, Edge, Firefox, Opera, Brave, Vivaldi, Comet, and Zen profiles and remembers the first one that works. If every check fails, yt-dlp continues without browser cookies and shows its original error.

Chromium-based browsers may lock their cookie database. Fully exit the browser, including background processes, before downloading a restricted video. Cookies remain in the browser profile and are read directly by yt-dlp; the wrapper does not export a cookie file.

## Files and folders

```text
SaF-YTDLP.cmd or SaF-YTDLP.sh  launcher
config.ini                     user settings
Downloads/                     completed downloads
internal/dependencies/         portable yt-dlp, Deno, FFmpeg, and FFprobe
internal/temp/                 temporary data for the active job
```

`internal/temp` is cleared automatically. No permanent logs, queues, or JSON state files are kept. Existing downloads are never overwritten: repeated names become `name (1).ext`, `name (2).ext`, and so on.

Do not run two copies from the same folder at the same time. They share `config.ini`, `internal`, and `Downloads`.

## Troubleshooting

- If a restricted video fails, close every supported browser completely and retry.
- If transcoding fails, the original downloaded file is kept in `Downloads`; inspect the FFmpeg message shown in the terminal.
- If moving a completed file into `Downloads` fails, it remains under `internal/temp/job.../downloads`; the next start retries the move before clearing that job.
- If setup was interrupted, start the launcher again. Partially downloaded dependencies are not installed.
- If `config.ini` is missing, restore it from the release archive. The launchers do not invent a replacement for missing user settings.
- If a copied Unix launcher is not executable, run `chmod +x SaF-YTDLP.sh`.
- Delete `internal/dependencies` to force a clean dependency download. Do not delete `Downloads` unless you intend to remove your media.

## Development

GitHub Actions performs one live end-to-end download on Windows, Ubuntu, and
macOS, using both x64 and ARM64 runners. Each job downloads the reference video
with the matching launcher, verifies the completed file and temporary cleanup,
and publishes an FFprobe media report in the job summary. Every job has a
five-minute timeout.

Build clean release archives without reading or changing the working `config.ini`:

```bat
build-release.cmd
```

The release builder requires the system `tar.exe` included with Windows 10/11 and GNU tar from Git for Windows so the Unix launcher keeps its executable permission. Set `SAF_GNU_TAR` to use another GNU tar installation.

Code by ChatGPT 5.6 Sol (High). Project management by the project author.

## License

This project is distributed under the MIT License. See `LICENSE`.

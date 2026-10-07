# Simple and Flexible yt-dlp Wrapper Release Design

## Purpose

Simple and Flexible yt-dlp Wrapper (SaF yt-dlp Wrapper) is a small,
portable, interactive YouTube downloader. It accepts YouTube video and
playlist URLs, downloads video, audio, or thumbnails, and applies a selected
compatibility profile without installing dependencies system-wide.

The product is designed and tested specifically for YouTube. Other URLs are
passed through to yt-dlp without an artificial domain restriction, but they
are unsupported and receive no compatibility guarantee.

## Product Principles

- Keep the program understandable and self-contained.
- Keep the Windows implementation in one `SaF-YTDLP.cmd` file.
- Add the Unix implementation only after the Windows version is complete and
  verified.
- Preserve source media whenever downloading, publishing, or transcoding
  fails.
- Never overwrite an existing file in `Downloads`.
- Do not require administrator privileges or system-wide dependency installs.
- Prefer explicit code over compact but difficult Batch tricks.

## Repository and Runtime Layout

```text
SaF-YTDLP.cmd
SaF-YTDLP.sh
config.ini
README.md
LICENSE
internal/
  dependencies/
  temp/
Downloads/
tests/
dist/
```

`internal/dependencies/` stores the locally downloaded yt-dlp, Deno, FFmpeg,
and FFprobe executables. `internal/temp/` stores only the active job's media,
yt-dlp metadata JSON, format selections, per-job file list, and FFprobe output.
Temporary data is removed after the job completes and stale temporary data is
cleaned on the next run.

The reusable dependency executables currently stored in `.tools` are moved
once into `internal/dependencies/` during the repository cleanup. Obsolete
generated files are removed. The released program does not contain a `.tools`
compatibility layer because this is the first public release.

`internal/`, `Downloads/`, and `dist/` are excluded from Git. Release archives
contain only the appropriate launcher, `config.ini`, `README.md`, and
`LICENSE`; dependencies are downloaded on first run. Tests and planning
documents remain in the repository but are excluded from release archives.

Running multiple copies of the wrapper simultaneously is unsupported.

## Release Configuration

The released `config.ini` uses these defaults:

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

The 1080p limit and Modern codec selection are intended to avoid unnecessary
YouTube transcoding. Hardware encoding is enabled so a required conversion
does not take excessive time. Multitrack audio is enabled so one best stream
for every language exposed by YouTube is retained.

## Download Flow

1. Resolve the wrapper root and load and validate `config.ini`.
2. Detect operating system and CPU architecture.
3. Create `internal/dependencies`, `internal/temp`, and `Downloads` as needed.
4. Download missing platform-specific dependencies locally.
5. Ask yt-dlp to update itself; continue with the installed version if the
   update fails.
6. Prompt for a YouTube video or playlist URL and the download mode.
7. Select browser cookies when needed.
8. Create an isolated temporary job, obtain metadata when exact format
   selection is required, and download into the job.
9. Post-process every completed entry independently so one failed playlist
   entry does not block later entries.
10. Publish completed files to `Downloads`, adding ` (1)`, ` (2)`, and later
    suffixes instead of replacing existing files.
11. Remove the completed job and prompt for another URL.

## Browser Cookies

Cookie selection uses one platform-independent strategy:

1. Try the browser saved in `COOKIE_BROWSER`.
2. If it fails, probe the supported browsers in a fixed platform-specific
   order using yt-dlp simulation.
3. Retain the required custom profile discovery for Comet and Zen.
4. Save the first successful browser back to `config.ini`.
5. Continue without cookies when no browser session works.

The wrapper no longer detects the operating system's default browser. That
only changed probe order and made the Windows implementation and Unix port
substantially more complex.

## Format and Profile Rules

Resolution and frame rate take priority over source codec. `MAX_HEIGHT`
filters out formats above the configured limit before codec preference is
applied.

For equal resolution and frame rate, `MODERN` uses this source preference:

```text
H.265 > H.264 > AV1 > VP9 > other
```

Native H.265 and compatible H.264 are kept without video re-encoding. AV1,
VP9, and other incompatible video are converted to H.265. On ordinary YouTube
videos H.265 is rarely exposed, so a native 1080p H.264 stream normally avoids
conversion.

`QUALITY` and `UNIVERSAL` retain their existing behavior:

- `QUALITY` prefers a ready AV1 stream over VP9 at equal resolution and frame
  rate, then keeps the best remaining source codecs. VP9 is converted to AV1
  only when no equivalent ready AV1 stream is available and conversion is
  enabled.
- `UNIVERSAL` produces H.264 8-bit MP4 video and AAC audio.

When `DOWNLOAD_ALL_AUDIO_TRACKS=YES`, every mode that downloads media retains
one best audio stream per language exposed by YouTube. The temporary yt-dlp
JSON is required to choose those language streams and is deleted with the job.

The existing codec- and resolution-aware bitrate table, 10% generation-loss
margin, additional hardware margin, two-pass software encoding, and one-pass
hardware VBR behavior remain unchanged.

## Windows Cleanup

The monolithic CMD is reorganized into clearly marked sections:

1. startup and configuration;
2. dependency management;
3. browser cookies;
4. interactive menu and download modes;
5. format and audio selection;
6. media inspection and post-processing;
7. publishing and cleanup;
8. utility functions.

The cleanup includes these targeted simplifications:

- consolidate repeated FFprobe calls into one normal media inspection, with a
  packet-size fallback only when stream bitrate is unavailable;
- normalize codec names once into `H264`, `H265`, `VP9`, `AV1`, or `OTHER`;
- share duplicated profile-specific audio download argument construction;
- remove default-browser detection from cookie selection;
- remove the persistent failed post-processing queue;
- keep failed source media and report the failure directly in the console.

The following intentionally remain explicit:

- the bitrate coefficient table;
- encoder-specific FFmpeg arguments;
- temporary JSON selection for Modern and multitrack modes;
- per-entry CMD processing used to preserve filenames containing `%`, `!`,
  Unicode, and other Batch-sensitive characters.

## Platform Support

The release supports:

- Windows 10 or 11 on x86_64 and ARM64;
- Linux on x86_64 and ARM64;
- macOS on Intel x86_64 and Apple Silicon ARM64.

Each platform downloads matching local builds of yt-dlp, Deno, FFmpeg, and
FFprobe. A download is written to a temporary name and validated before it
replaces a working dependency.

Hardware encoding is opportunistic. The wrapper probes compatible encoders
for the target codec and platform, uses the first working encoder, and retries
the file with a software encoder if hardware encoding fails.

## Unix Implementation

`SaF-YTDLP.sh` is written only after the cleaned Windows script passes its full
test suite and Windows smoke tests. It is a single Bash script that duplicates
the finished Windows behavior rather than introducing a shared runtime or a
new programming-language dependency.

The Bash version uses the same `config.ini`, directory layout, prompts,
profiles, YouTube format choices, multitrack behavior, collision-safe
publishing, and error policy. Only dependency URLs, browser profile paths,
hardware encoder candidates, and operating-system commands vary by platform.

## Error Handling

- A partial dependency download never replaces an existing executable.
- A failed yt-dlp update emits a warning and uses the installed version.
- Missing or invalid configuration stops before downloading media.
- Failure to use browser cookies falls back to the next browser and then to a
  cookie-free attempt.
- A failed hardware encode is retried once with the matching CPU encoder.
- A failed conversion keeps and publishes the downloaded source media.
- A failed playlist entry does not prevent later completed entries from being
  processed.
- Existing destination files are preserved and new files receive numbered
  suffixes.

## Testing and Verification

The current 70-test Windows suite is the behavioral baseline. Changes are made
test-first. New Windows tests cover:

- the `internal/dependencies` and `internal/temp` layout;
- x86_64 and ARM64 dependency selection;
- simplified cookie ordering and fallback;
- H.265-first Modern selection with H.264 fallback;
- consolidated media inspection;
- temporary-data cleanup and source preservation;
- released configuration defaults.

After automated Windows tests pass, real local smoke tests cover dependency
setup, Unicode paths, one video, one playlist, multitrack audio, stream copy,
software transcoding, available hardware transcoding, and CPU fallback.

Only then is the Bash implementation added. Its fake-tool integration tests
exercise the same behavioral cases, and CI runs the applicable suites on
Windows, Ubuntu, and macOS. Architecture URL selection is tested for x86_64
and ARM64 even when the CI host cannot execute both architectures.

## Release Preparation

- Replace the old product name everywhere with Simple and Flexible yt-dlp
  Wrapper while retaining `SaF-YTDLP.cmd` and `SaF-YTDLP.sh` filenames.
- Rewrite README in clear English with quick start, configuration, profiles,
  cookies, directory layout, supported systems, troubleshooting, and license.
- Credit ChatGPT 5.6 Sol (High) for the code and the project author for project
  management.
- Add a repeatable release builder that creates both archives with a generated
  default `config.ini` without modifying or packaging the user's working
  configuration.
- Remove the obsolete root release ZIP and other generated repository debris.
- Preserve all user media in `Downloads`.
- Produce separate clean Windows ZIP and Unix archive outputs in `dist/`.
- Verify each archive from a fresh extracted directory before declaring the
  release ready.

## Acceptance Criteria

- All existing behavior that is not explicitly simplified above remains
  covered and working.
- The Windows implementation remains one CMD file and passes the expanded
  Windows suite before Bash work begins.
- The Unix implementation is one Bash file and matches the completed Windows
  behavior for YouTube videos and playlists.
- First-run dependency installation works locally on every supported OS and
  architecture mapping.
- Default Modern downloads are capped at 1080p, prefer H.265 then H.264, and
  avoid re-encoding either codec.
- QUALITY selects a native AV1 stream instead of an equivalent VP9 stream and
  avoids the unnecessary VP9-to-AV1 conversion.
- Multitrack mode retains one best audio track per available language.
- Runtime files exist only under `internal/`; completed media exists only
  under `Downloads/`.
- Release archives contain no downloaded dependencies, temporary files, test
  fixtures, personal browser selection, or user downloads, and building them
  does not change the working `config.ini`.

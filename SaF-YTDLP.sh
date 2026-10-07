#!/usr/bin/env bash
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
internal_dir=$script_dir/internal
dependencies_dir=$internal_dir/dependencies
temp_dir=$internal_dir/temp
downloads_dir=$script_dir/Downloads
config_file=$script_dir/config.ini

ytdlp=$dependencies_dir/yt-dlp
deno=$dependencies_dir/deno
ffmpeg=$dependencies_dir/ffmpeg
ffprobe=$dependencies_dir/ffprobe
ytdlp_new=$dependencies_dir/yt-dlp.new
deno_new=$dependencies_dir/deno.new
ffmpeg_new=$dependencies_dir/ffmpeg.new
ffprobe_new=$dependencies_dir/ffprobe.new

PROFILE=MODERN
MAX_HEIGHT=1080
DEFAULT_MODE=video
TRANSCODE_VP9_TO_AV1=YES
ALLOW_HARDWARE_TRANSCODING=NO
STORE_OPUS_IN_MP4=NO
DOWNLOAD_ALL_AUDIO_TRACKS=YES
COOKIE_BROWSER=

platform_id=
ytdlp_asset=
deno_asset=
ffmpeg_asset=
ffprobe_asset=
ytdlp_url=
deno_url=
ffmpeg_url=
ffprobe_url=
setup_dir=

trim_value() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

uppercase() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

select_platform() {
    local os architecture
    os=${SAF_TEST_UNAME_S:-$(uname -s)}
    architecture=${SAF_TEST_UNAME_M:-$(uname -m)}

    case "$os:$architecture" in
        Linux:x86_64|Linux:amd64)
            platform_id=linux-x64
            ytdlp_asset=yt-dlp_linux
            deno_asset=deno-x86_64-unknown-linux-gnu.zip
            ffmpeg_asset=ffmpeg-master-latest-linux64-gpl.tar.xz
            ;;
        Linux:aarch64|Linux:arm64)
            platform_id=linux-arm64
            ytdlp_asset=yt-dlp_linux_aarch64
            deno_asset=deno-aarch64-unknown-linux-gnu.zip
            ffmpeg_asset=ffmpeg-master-latest-linuxarm64-gpl.tar.xz
            ;;
        Darwin:x86_64|Darwin:amd64)
            platform_id=macos-x64
            ytdlp_asset=yt-dlp_macos
            deno_asset=deno-x86_64-apple-darwin.zip
            ffmpeg_asset=ffmpeg-darwin-x64.gz
            ffprobe_asset=ffprobe-darwin-x64.gz
            ;;
        Darwin:aarch64|Darwin:arm64)
            platform_id=macos-arm64
            ytdlp_asset=yt-dlp_macos
            deno_asset=deno-aarch64-apple-darwin.zip
            ffmpeg_asset=ffmpeg-darwin-arm64.gz
            ffprobe_asset=ffprobe-darwin-arm64.gz
            ;;
        *)
            printf 'Error: this wrapper supports Linux and macOS on x86_64 and ARM64.\n' >&2
            return 1
            ;;
    esac

    ytdlp_url=https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/$ytdlp_asset
    deno_url=https://github.com/denoland/deno/releases/latest/download/$deno_asset
    if [[ $platform_id == linux-* ]]; then
        ffmpeg_url=https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/$ffmpeg_asset
        ffprobe_url=
    else
        ffmpeg_url=https://github.com/eugeneware/ffmpeg-static/releases/latest/download/$ffmpeg_asset
        ffprobe_url=https://github.com/eugeneware/ffmpeg-static/releases/latest/download/$ffprobe_asset
    fi
}

print_dependency_map() {
    printf 'PLATFORM=%s\n' "$platform_id"
    printf 'YTDLP_URL=%s\n' "$ytdlp_url"
    printf 'DENO_URL=%s\n' "$deno_url"
    printf 'FFMPEG_URL=%s\n' "$ffmpeg_url"
    if [[ -n $ffprobe_url ]]; then
        printf 'FFPROBE_URL=%s\n' "$ffprobe_url"
    fi
}

validate_yes_no() {
    local name=$1 value
    value=$(uppercase "$2")
    if [[ $value != YES && $value != NO ]]; then
        printf 'Error: Invalid %s. Use YES or NO.\n' "$name" >&2
        return 1
    fi
    printf -v "$name" '%s' "$value"
}

load_config() {
    local line key value
    if [[ ! -f $config_file ]]; then
        printf 'Error: config.ini was not found next to the script. Extract it from the release archive.\n' >&2
        return 1
    fi

    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        case $line in
            ''|'#'*|';'*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        key=$(trim_value "${line%%=*}")
        value=$(trim_value "${line#*=}")
        case $key in
            PROFILE) PROFILE=$value ;;
            MAX_HEIGHT) MAX_HEIGHT=$value ;;
            DEFAULT_MODE) DEFAULT_MODE=$value ;;
            TRANSCODE_VP9_TO_AV1) TRANSCODE_VP9_TO_AV1=$value ;;
            ALLOW_HARDWARE_TRANSCODING) ALLOW_HARDWARE_TRANSCODING=$value ;;
            STORE_OPUS_IN_MP4) STORE_OPUS_IN_MP4=$value ;;
            DOWNLOAD_ALL_AUDIO_TRACKS) DOWNLOAD_ALL_AUDIO_TRACKS=$value ;;
            COOKIE_BROWSER) COOKIE_BROWSER=$value ;;
        esac
    done < "$config_file"

    PROFILE=$(uppercase "$PROFILE")
    DEFAULT_MODE=$(printf '%s' "$DEFAULT_MODE" | tr '[:upper:]' '[:lower:]')
    case $PROFILE in QUALITY|MODERN|UNIVERSAL) ;; *) printf 'Error: Invalid PROFILE. Use QUALITY, MODERN, or UNIVERSAL.\n' >&2; return 1 ;; esac
    if [[ ! $MAX_HEIGHT =~ ^[0-9]+$ ]]; then
        printf 'Error: Invalid MAX_HEIGHT. Use 0 or a positive number.\n' >&2
        return 1
    fi
    case $DEFAULT_MODE in video|audio|thumbnail) ;; *) printf 'Error: Invalid DEFAULT_MODE. Use video, audio, or thumbnail.\n' >&2; return 1 ;; esac
    validate_yes_no TRANSCODE_VP9_TO_AV1 "$TRANSCODE_VP9_TO_AV1" || return 1
    validate_yes_no ALLOW_HARDWARE_TRANSCODING "$ALLOW_HARDWARE_TRANSCODING" || return 1
    validate_yes_no STORE_OPUS_IN_MP4 "$STORE_OPUS_IN_MP4" || return 1
    validate_yes_no DOWNLOAD_ALL_AUDIO_TRACKS "$DOWNLOAD_ALL_AUDIO_TRACKS" || return 1
    COOKIE_BROWSER=$(printf '%s' "$COOKIE_BROWSER" | tr '[:upper:]' '[:lower:]')
    case $COOKIE_BROWSER in
        ''|chrome|chromium|edge|firefox|opera|brave|vivaldi|comet|zen) ;;
        *) printf 'Error: Invalid COOKIE_BROWSER. Use chrome, chromium, edge, firefox, opera, brave, vivaldi, comet, zen, or leave it empty.\n' >&2; return 1 ;;
    esac
}

cleanup_setup() {
    if [[ -n $setup_dir && -d $setup_dir ]]; then
        rm -rf "$setup_dir"
    fi
    setup_dir=
}

prepare_setup() {
    cleanup_setup
    setup_dir=$(mktemp -d "$temp_dir/setup.XXXXXX") || return 1
}

download_file() {
    local url=$1 destination=$2
    if [[ ${SAF_TEST_DOWNLOAD_FAILURE:-} == YES ]]; then
        : > "$destination"
        return 1
    fi
    curl -fL --retry 3 --output "$destination" "$url"
}

validate_ffmpeg_pair() {
    local encoders
    "$ffprobe_new" -version >/dev/null 2>&1 || return 1
    encoders=$("$ffmpeg_new" -hide_banner -encoders 2>&1) || return 1
    case $encoders in *libx264*) ;; *) return 1 ;; esac
    case $encoders in *libx265*) ;; *) return 1 ;; esac
    case $encoders in *libsvtav1*|*libaom-av1*) ;; *) return 1 ;; esac
}

install_ytdlp() {
    local part
    printf 'Downloading yt-dlp nightly...\n'
    prepare_setup || return 1
    part=$setup_dir/$ytdlp_asset.part
    if ! download_file "$ytdlp_url" "$part"; then
        cleanup_setup
        printf 'Error: could not download yt-dlp.\n' >&2
        return 1
    fi
    cp "$part" "$ytdlp_new" && chmod +x "$ytdlp_new" && "$ytdlp_new" --version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        rm -f "$ytdlp_new"
        cleanup_setup
        printf 'Error: downloaded yt-dlp did not run.\n' >&2
        return 1
    fi
    mv -f "$ytdlp_new" "$ytdlp"
    local result=$?
    cleanup_setup
    return "$result"
}

install_deno() {
    local part unpack candidate
    printf 'Downloading Deno...\n'
    prepare_setup || return 1
    part=$setup_dir/$deno_asset.part
    unpack=$setup_dir/deno-unpack
    if ! download_file "$deno_url" "$part"; then
        cleanup_setup
        printf 'Error: could not download Deno.\n' >&2
        return 1
    fi
    mkdir -p "$unpack" && unzip -q "$part" -d "$unpack"
    candidate=$(find "$unpack" -type f -name deno -print 2>/dev/null | sed -n '1p')
    if [[ -z $candidate ]] || ! cp "$candidate" "$deno_new" || ! chmod +x "$deno_new" || ! "$deno_new" --version >/dev/null 2>&1; then
        rm -f "$deno_new"
        cleanup_setup
        printf 'Error: downloaded Deno did not run.\n' >&2
        return 1
    fi
    mv -f "$deno_new" "$deno"
    local result=$?
    cleanup_setup
    return "$result"
}

install_ffmpeg_linux() {
    local part unpack ffmpeg_candidate ffprobe_candidate
    part=$setup_dir/$ffmpeg_asset.part
    unpack=$setup_dir/ffmpeg-unpack
    if ! download_file "$ffmpeg_url" "$part"; then
        return 1
    fi
    mkdir -p "$unpack" && tar -xJf "$part" -C "$unpack" || return 1
    ffmpeg_candidate=$(find "$unpack" -type f -name ffmpeg -print 2>/dev/null | sed -n '1p')
    ffprobe_candidate=$(find "$unpack" -type f -name ffprobe -print 2>/dev/null | sed -n '1p')
    [[ -n $ffmpeg_candidate && -n $ffprobe_candidate ]] || return 1
    cp "$ffmpeg_candidate" "$ffmpeg_new" && cp "$ffprobe_candidate" "$ffprobe_new" && chmod +x "$ffmpeg_new" "$ffprobe_new"
}

install_ffmpeg_macos() {
    local ffmpeg_part ffprobe_part
    ffmpeg_part=$setup_dir/$ffmpeg_asset.part
    ffprobe_part=$setup_dir/$ffprobe_asset.part
    download_file "$ffmpeg_url" "$ffmpeg_part" || return 1
    download_file "$ffprobe_url" "$ffprobe_part" || return 1
    gzip -dc "$ffmpeg_part" > "$ffmpeg_new" || return 1
    gzip -dc "$ffprobe_part" > "$ffprobe_new" || return 1
    chmod +x "$ffmpeg_new" "$ffprobe_new"
}

install_ffmpeg() {
    printf 'Downloading FFmpeg. This is a large one-time download...\n'
    prepare_setup || return 1
    rm -f "$ffmpeg_new" "$ffprobe_new"
    if [[ $platform_id == linux-* ]]; then
        install_ffmpeg_linux
    else
        install_ffmpeg_macos
    fi
    if [[ $? -ne 0 ]] || ! validate_ffmpeg_pair; then
        rm -f "$ffmpeg_new" "$ffprobe_new"
        cleanup_setup
        printf 'Error: downloaded FFmpeg did not pass validation.\n' >&2
        return 1
    fi
    mv -f "$ffmpeg_new" "$ffmpeg" && mv -f "$ffprobe_new" "$ffprobe"
    local result=$?
    cleanup_setup
    return "$result"
}

update_ytdlp() {
    rm -f "$ytdlp_new"
    cp "$ytdlp" "$ytdlp_new" || return 1
    chmod +x "$ytdlp_new"
    if ! "$ytdlp_new" --update-to nightly || ! "$ytdlp_new" --version >/dev/null 2>&1; then
        rm -f "$ytdlp_new"
        return 1
    fi
    mv -f "$ytdlp_new" "$ytdlp"
}

# Browser cookies

file_mtime() {
    local timestamp
    timestamp=$(stat -c %Y "$1" 2>/dev/null || true)
    if [[ ! $timestamp =~ ^[0-9]+$ ]]; then
        timestamp=$(stat -f %m "$1" 2>/dev/null || true)
    fi
    [[ $timestamp =~ ^[0-9]+$ ]] || timestamp=0
    printf '%s' "$timestamp"
}

newest_cookie_profile() {
    local root=$1 kind=$2 file profile parent timestamp newest_timestamp=0 newest_profile=
    [[ -d $root ]] || return 1
    while IFS= read -r -d '' file; do
        profile=${file%/*}
        if [[ ${profile##*/} == Network ]]; then
            profile=${profile%/*}
        fi
        parent=${profile%/*}
        if [[ $kind == chromium ]]; then
            [[ $parent == "$root" ]] || continue
            case ${profile##*/} in Default|'Profile '[0-9]*) ;; *) continue ;; esac
        fi
        timestamp=$(file_mtime "$file")
        if ((timestamp >= newest_timestamp)); then
            newest_timestamp=$timestamp
            newest_profile=$profile
        fi
    done < <(find "$root" -type f \( -name Cookies -o -name cookies.sqlite \) -print0 2>/dev/null)
    [[ -n $newest_profile ]] || return 1
    printf '%s' "$newest_profile"
}

resolve_comet_source() {
    local root profile
    if [[ $platform_id == macos-* ]]; then
        root="${HOME:?}/Library/Application Support/Perplexity/Comet/User Data"
    else
        root="${XDG_CONFIG_HOME:-${HOME:?}/.config}/Perplexity/Comet/User Data"
    fi
    profile=$(newest_cookie_profile "$root" chromium) || return 1
    printf 'chrome:%s' "$profile"
}

resolve_zen_source() {
    local root profile
    if [[ $platform_id == macos-* ]]; then
        root="${HOME:?}/Library/Application Support/zen/Profiles"
    else
        root=${HOME:?}/.zen
    fi
    profile=$(newest_cookie_profile "$root" firefox) || return 1
    printf 'firefox:%s' "$profile"
}

resolve_cookie_label() {
    case $1 in
        chrome|chromium|edge|firefox|opera|brave|vivaldi) printf '%s' "$1" ;;
        comet) resolve_comet_source ;;
        zen) resolve_zen_source ;;
        *) return 1 ;;
    esac
}

save_cookie_browser() {
    local temporary=$config_file.saf-new
    awk -v value="$1" '
        BEGIN { found = 0 }
        /^[[:space:]]*COOKIE_BROWSER[[:space:]]*=/ { print "COOKIE_BROWSER=" value; found = 1; next }
        { print }
        END { if (!found) print "COOKIE_BROWSER=" value }
    ' "$config_file" > "$temporary" && mv -f "$temporary" "$config_file"
}

probe_cookie_source() {
    local source=$1
    "$ytdlp" --ignore-config --cookies-from-browser "$source" --js-runtimes "deno:$deno" \
        --ffmpeg-location "$dependencies_dir" --simulate --skip-download "$URL" >/dev/null 2>&1
}

select_cookie_source() {
    local -a labels=() sources=()
    local saved_label saved_source label source index
    cookie_source=
    cookie_source_label=
    cookie_selection_done=YES

    saved_label=$(printf '%s' "$COOKIE_BROWSER" | tr '[:upper:]' '[:lower:]')
    if [[ -n $saved_label ]]; then
        saved_source=$(resolve_cookie_label "$saved_label" 2>/dev/null || true)
        if [[ -n $saved_source ]]; then
            if [[ -z ${cookie_skip_label:-} ]]; then
                cookie_source=$saved_source
                cookie_source_label=$saved_label
                printf 'Using cookies from %s.\n' "$saved_label"
                return 0
            fi
            labels+=("$saved_label")
            sources+=("$saved_source")
        fi
    fi

    for label in chrome chromium edge firefox opera brave vivaldi; do
        [[ $label == "$saved_label" ]] && continue
        labels+=("$label")
        sources+=("$label")
    done
    if [[ $saved_label != comet ]]; then
        source=$(resolve_comet_source 2>/dev/null || true)
        if [[ -n $source ]]; then labels+=(comet); sources+=("$source"); fi
    fi
    if [[ $saved_label != zen ]]; then
        source=$(resolve_zen_source 2>/dev/null || true)
        if [[ -n $source ]]; then labels+=(zen); sources+=("$source"); fi
    fi

    printf 'Checking browser sessions for usable cookies...\n'
    index=0
    while ((index < ${#labels[@]})); do
        label=${labels[$index]}
        source=${sources[$index]}
        index=$((index + 1))
        [[ -n ${cookie_skip_label:-} && $label == "$cookie_skip_label" ]] && continue
        if probe_cookie_source "$source"; then
            cookie_source=$source
            cookie_source_label=$label
            COOKIE_BROWSER=$label
            save_cookie_browser "$label" || return 1
            printf 'Using cookies from %s.\n' "$label"
            return 0
        fi
    done

    printf 'No usable browser session was found; continuing without browser cookies.\n'
    return 0
}

build_ytdlp_base() {
    ytdlp_base=("$ytdlp" --ignore-config)
    if [[ -n ${cookie_source:-} ]]; then
        ytdlp_base+=(--cookies-from-browser "$cookie_source")
    fi
    ytdlp_base+=(--js-runtimes "deno:$deno" --ffmpeg-location "$dependencies_dir")
}

# Jobs and downloads

prepare_job() {
    job_dir=$(mktemp -d "$temp_dir/job.XXXXXX") || return 1
    job_downloads=$job_dir/downloads
    postprocess_list=$job_dir/postprocess.tsv
    metadata_file=$job_dir/metadata.json
    selections_file=$job_dir/selections.tsv
    mkdir -p "$job_downloads"
}

cleanup_job() {
    [[ -n ${job_dir:-} && -d $job_dir ]] && rm -rf "$job_dir"
    job_dir=
}

count_job_files() {
    find "$job_downloads" -type f 2>/dev/null | wc -l | tr -d ' '
}

run_ytdlp_once() {
    local -a arguments=("$@")
    build_ytdlp_base
    "${ytdlp_base[@]}" -P "$job_downloads" \
        -o '%(playlist&{}/|)s%(playlist_index&{} - |)s%(title)s.%(ext)s' \
        "${arguments[@]}" "$URL"
}

run_ytdlp() {
    local before after result
    if [[ ${cookie_selection_done:-NO} == NO ]]; then
        select_cookie_source || return 1
    fi
    before=$(count_job_files)
    run_ytdlp_once "$@"
    result=$?
    if ((result == 0)); then
        return 0
    fi
    if [[ -z ${cookie_source:-} ]]; then
        return "$result"
    fi
    after=$(count_job_files)
    if ((after > before)); then
        return "$result"
    fi
    printf 'Saved browser session failed before downloading. Checking other browsers...\n'
    cookie_skip_label=$cookie_source_label
    cookie_selection_done=NO
    select_cookie_source || return 1
    cookie_skip_label=
    run_ytdlp_once "$@"
}

dump_metadata_once() {
    build_ytdlp_base
    "${ytdlp_base[@]}" --dump-single-json --skip-download "$URL" > "$metadata_file"
}

dump_metadata() {
    local result
    if [[ ${cookie_selection_done:-NO} == NO ]]; then
        select_cookie_source || return 1
    fi
    dump_metadata_once
    result=$?
    if ((result == 0)); then
        return 0
    fi
    [[ -n ${cookie_source:-} ]] || return "$result"
    cookie_skip_label=$cookie_source_label
    cookie_selection_done=NO
    select_cookie_source || return 1
    cookie_skip_label=
    dump_metadata_once
}

select_formats() {
    local mode=$1 selector_js
    selector_js=$(cat <<'JS'
const [metadataPath, outputPath, mode, profile, maxHeightText] = Deno.args;
const root = JSON.parse(await Deno.readTextFile(metadataPath));
const isPlaylist = root._type === 'playlist';
const entries = isPlaylist ? (root.entries || []).filter(Boolean) : [root];
const maxHeight = Number(maxHeightText);
const number = (value) => Number(value) || 0;
const codecRank = (codec) => {
  codec = String(codec || '').toLowerCase();
  if (profile === 'QUALITY') return /^(av01|av1)/.test(codec) ? 4 : 0;
  if (profile === 'UNIVERSAL') {
    if (/^(avc1|h264)/.test(codec)) return 4;
    if (/^(hev1|hvc1|hevc|h265)/.test(codec)) return 3;
    if (/^(av01|av1)/.test(codec)) return 2;
    if (/^(vp09|vp9)/.test(codec)) return 1;
    return 0;
  }
  if (/^(hev1|hvc1|hevc|h265)/.test(codec)) return 4;
  if (/^(avc1|h264)/.test(codec)) return 3;
  if (/^(av01|av1)/.test(codec)) return 2;
  if (/^(vp09|vp9)/.test(codec)) return 1;
  return 0;
};
const compareVideo = (a, b) => number(b.height) - number(a.height)
  || number(b.fps) - number(a.fps)
  || codecRank(b.vcodec) - codecRank(a.vcodec)
  || number(b.quality) - number(a.quality)
  || Number((!b.acodec || b.acodec === 'none')) - Number((!a.acodec || a.acodec === 'none'))
  || number(b.language_preference) - number(a.language_preference)
  || number(b.tbr) - number(a.tbr);
const audioRank = (format) => profile === 'QUALITY'
  ? (/^opus/i.test(String(format.acodec || '')) ? 2 : 1)
  : (/^(mp4a|aac)/i.test(String(format.acodec || '')) ? 2 : 1);
const compareAudio = (a, b) => audioRank(b) - audioRank(a)
  || Number(b.vcodec === 'none') - Number(a.vcodec === 'none')
  || number(b.quality) - number(a.quality)
  || number(b.abr) - number(a.abr)
  || number(b.tbr) - number(a.tbr);
const lines = [];
let position = 0;
for (const entry of entries) {
  position += 1;
  const item = isPlaylist ? String(entry.playlist_index || position) : '0';
  const formats = (entry.formats || []).filter((format) => format && format.format_id);
  const audioGroups = new Map();
  for (const format of formats.filter((format) => format.acodec && format.acodec !== 'none')) {
    const language = String(format.language || 'und');
    if (!audioGroups.has(language)) audioGroups.set(language, []);
    audioGroups.get(language).push(format);
  }
  const chosenAudio = [];
  for (const group of audioGroups.values()) chosenAudio.push(group.sort(compareAudio)[0]);
  chosenAudio.sort((a, b) => number(b.language_preference) - number(a.language_preference)
    || String(a.language || 'und').localeCompare(String(b.language || 'und')));
  let video = null;
  if (mode === 'video') {
    const videos = formats.filter((format) => format.vcodec && format.vcodec !== 'none'
      && (maxHeight === 0 || !format.height || number(format.height) <= maxHeight));
    if (!videos.length) {
      lines.push(`ERROR\t${item}`);
      continue;
    }
    video = videos.sort(compareVideo)[0];
  }
  const videoHasAudio = Boolean(video && video.acodec && video.acodec !== 'none');
  const videoLanguage = videoHasAudio ? String(video.language || '') : '';
  const selectedAudio = chosenAudio.filter((format) => String(format.format_id) !== String(video?.format_id || '')
    && (!videoHasAudio || String(format.language || '') !== videoLanguage));
  const finalAudio = videoHasAudio ? [video, ...selectedAudio] : selectedAudio;
  const audioIds = selectedAudio.map((format) => String(format.format_id)).join('+') || 'NONE';
  const hasCombined = finalAudio.some((format) => format.vcodec && format.vcodec !== 'none') ? 'YES' : 'NO';
  const needsOpus = chosenAudio.some((format) => !/^opus/i.test(String(format.acodec || ''))) ? 'YES' : 'NO';
  const languages = finalAudio.map((format) => /^[A-Za-z0-9-]+$/.test(String(format.language || ''))
    ? String(format.language) : 'und').join('+') || 'NONE';
  lines.push([item, video ? String(video.format_id) : 'AUTO', audioIds, hasCombined, needsOpus, languages].join('\t'));
}
if (!lines.length) throw new Error('No media entries');
await Deno.writeTextFile(outputPath, `${lines.join('\n')}\n`);
JS
)
    export SAF_SELECTION_OUTPUT=$selections_file
    "$deno" eval --quiet "$selector_js" "$metadata_file" "$selections_file" "$mode" "$PROFILE" "$MAX_HEIGHT"
}

prepare_selections() {
    local mode=$1
    dump_metadata || return 1
    select_formats "$mode"
}

download_modern_video() {
    local item video audio combined needs_opus languages format result=0
    prepare_selections video || return 1
    while IFS=$'\t' read -r item video audio combined needs_opus languages; do
        if [[ $item == ERROR ]]; then
            printf 'Warning: playlist entry %s has no usable video format.\n' "$video" >&2
            result=1
            continue
        fi
        format="$video+ba[acodec^=mp4a]/$video+ba/$video"
        local -a arguments=()
        [[ $item == 0 ]] || arguments+=(--playlist-items "$item")
        arguments+=(-f "$format" --print-to-file $'after_move:%(filepath)s\t%(vcodec)s\t%(acodec)s' "$postprocess_list")
        run_ytdlp "${media_metadata_args[@]}" "${arguments[@]}" || result=1
    done < "$selections_file"
    return "$result"
}

download_all_audio_video() {
    local item video audio combined needs_opus languages format print_template result=0
    prepare_selections video || return 1
    while IFS=$'\t' read -r item video audio combined needs_opus languages; do
        if [[ $item == ERROR ]]; then
            printf 'Warning: playlist entry %s has no usable video format.\n' "$video" >&2
            result=1
            continue
        fi
        format=$video
        [[ $audio == NONE ]] || format=$format+$audio
        local -a arguments=()
        [[ $item == 0 ]] || arguments+=(--playlist-items "$item")
        if [[ $combined == YES ]]; then arguments+=(--video-multistreams --merge-output-format mkv); fi
        print_template=$'after_move:%(filepath)s\t%(vcodec)s\t%(acodec)s\t'"$languages"
        arguments+=(--audio-multistreams -f "$format" --print-to-file "$print_template" "$postprocess_list")
        run_ytdlp "${media_metadata_args[@]}" "${arguments[@]}" || result=1
    done < "$selections_file"
    return "$result"
}

download_video() {
    local format sort=
    media_metadata_args=(--embed-chapters --embed-metadata)
    if [[ $DOWNLOAD_ALL_AUDIO_TRACKS == YES ]]; then
        download_all_audio_video
        return
    fi
    if [[ $PROFILE == MODERN ]]; then
        download_modern_video
        return
    fi
    [[ $PROFILE == UNIVERSAL ]] && sort='res,fps,vcodec:h264'
    [[ $PROFILE == QUALITY ]] && sort='res,fps,vcodec:av1'
    if [[ $PROFILE == QUALITY ]]; then
        if [[ $MAX_HEIGHT == 0 ]]; then format='bv*+ba/b'; else format="bv*[height<=$MAX_HEIGHT]+ba/b[height<=$MAX_HEIGHT]"; fi
    elif [[ $MAX_HEIGHT == 0 ]]; then
        format='bv*+ba[acodec^=mp4a]/bv*+ba/b'
    elif ((MAX_HEIGHT <= 1080)); then
        format="bv*[height<=$MAX_HEIGHT][vcodec^=avc1]+ba[acodec^=mp4a]/bv*[height<=$MAX_HEIGHT][vcodec^=avc1]+ba/bv*[height<=$MAX_HEIGHT][vcodec^=h264]+ba[acodec^=mp4a]/bv*[height<=$MAX_HEIGHT][vcodec^=h264]+ba/bv*[height<=$MAX_HEIGHT]+ba[acodec^=mp4a]/bv*[height<=$MAX_HEIGHT]+ba/b[height<=$MAX_HEIGHT]"
    else
        format="bv*[height<=$MAX_HEIGHT]+ba[acodec^=mp4a]/bv*[height<=$MAX_HEIGHT]+ba/b[height<=$MAX_HEIGHT]"
    fi
    local -a arguments=()
    [[ -n $sort ]] && arguments+=(-S "$sort")
    arguments+=(-f "$format" --print-to-file $'after_move:%(filepath)s\t%(vcodec)s\t%(acodec)s' "$postprocess_list")
    run_ytdlp "${media_metadata_args[@]}" "${arguments[@]}"
}

set_audio_arguments() {
    audio_selector='ba/b'
    audio_format=best
    audio_remux=
    audio_quality=()
    [[ $PROFILE == QUALITY && $STORE_OPUS_IN_MP4 == YES ]] && audio_remux=opus-to-mp4
    if [[ $PROFILE == MODERN ]]; then
        audio_selector='ba[acodec^=mp4a]/ba/b[acodec^=mp4a]/b'
        audio_format=m4a
        audio_quality=(--audio-quality 0)
    elif [[ $PROFILE == UNIVERSAL ]]; then
        audio_format=mp3
        audio_quality=(--audio-quality 0)
    fi
}

download_all_audio_only() {
    local item video audio combined needs_opus languages metadata_text postprocessor_args container result=0
    prepare_selections audio || return 1
    while IFS=$'\t' read -r item video audio combined needs_opus languages; do
        local -a arguments=()
        [[ $item == 0 ]] || arguments+=(--playlist-items "$item")
        if [[ $audio == NONE ]]; then
            set_audio_arguments
            arguments+=(-f "$audio_selector" --extract-audio --audio-format "$audio_format" "${audio_quality[@]}")
            [[ -n $audio_remux ]] && arguments+=(--remux-video 'opus>mp4')
            arguments+=(--embed-thumbnail)
        elif [[ $PROFILE == QUALITY ]]; then
            set_audio_metadata_arguments "$languages"
            metadata_text=${AUDIO_METADATA_ARGS[*]}
            postprocessor_args='VideoRemuxer+ffmpeg_o:-vn'
            [[ $needs_opus == YES ]] && postprocessor_args=$postprocessor_args' -c:a libopus'
            [[ -n $metadata_text ]] && postprocessor_args=$postprocessor_args' '$metadata_text
            container=mka
            [[ $STORE_OPUS_IN_MP4 == YES ]] && container=mp4
            [[ $combined == YES ]] && arguments+=(--video-multistreams)
            arguments+=(--audio-multistreams -f "$audio" --merge-output-format mkv --remux-video "$container" --postprocessor-args "$postprocessor_args" --embed-thumbnail)
        else
            set_audio_metadata_arguments "$languages"
            metadata_text=${AUDIO_METADATA_ARGS[*]}
            postprocessor_args='VideoConvertor+ffmpeg_o:-vn'
            [[ -n $metadata_text ]] && postprocessor_args=$postprocessor_args' '$metadata_text
            [[ $combined == YES ]] && arguments+=(--video-multistreams)
            arguments+=(--audio-multistreams -f "$audio" --merge-output-format mkv --recode-video m4a --postprocessor-args "$postprocessor_args" --embed-thumbnail)
        fi
        run_ytdlp "${media_metadata_args[@]}" "${arguments[@]}" || result=1
    done < "$selections_file"
    return "$result"
}

download_audio() {
    media_metadata_args=(--embed-chapters --embed-metadata)
    if [[ $DOWNLOAD_ALL_AUDIO_TRACKS == YES ]]; then
        download_all_audio_only
        return
    fi
    set_audio_arguments
    local -a arguments=(-f "$audio_selector" --extract-audio --audio-format "$audio_format" "${audio_quality[@]}")
    [[ -n $audio_remux ]] && arguments+=(--remux-video 'opus>mp4')
    arguments+=(--embed-thumbnail)
    run_ytdlp "${media_metadata_args[@]}" "${arguments[@]}"
}

download_thumbnail() {
    media_metadata_args=()
    run_ytdlp --skip-download --write-thumbnail
}

# Media inspection and post-processing

normalize_codec() {
    case $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') in
        avc1*|h264*) printf 'H264' ;;
        hev1*|hvc1*|hevc*|h265*) printf 'H265' ;;
        vp09*|vp9*) printf 'VP9' ;;
        av01*|av1*) printf 'AV1' ;;
        *) printf 'OTHER' ;;
    esac
}

inspect_media() {
    local parser line
    probe_json=$job_dir/probe.json
    probe_text=$job_dir/probe.tsv
    packet_text=$job_dir/video-packets.txt
    bitrate_text=$job_dir/video-bitrate.txt
    rm -f "$probe_json" "$probe_text" "$packet_text" "$bitrate_text"
    "$ffprobe" -v error \
        -show_entries stream=index,codec_type,codec_name,pix_fmt,height,bit_rate:format=duration \
        -of json "$INPUT_FILE" > "$probe_json" 2>/dev/null || return 1
    parser=$(cat <<'JS'
const [inputPath, outputPath] = Deno.args;
const data = JSON.parse(await Deno.readTextFile(inputPath));
const video = (data.streams || []).find((stream) => stream.codec_type === 'video');
if (!video || !String(video.codec_name || '')) throw new Error('Video stream not found');
const audio = (data.streams || []).filter((stream) => stream.codec_type === 'audio')
  .map((stream) => String(stream.codec_name || '')).filter(Boolean).join(',');
const values = [video.codec_name, video.height, video.bit_rate, video.pix_fmt,
  data.format?.duration, audio].map((value) => value === undefined || value === null || value === '' ? 'NONE' : String(value));
await Deno.writeTextFile(outputPath, values.join('\t'));
JS
)
    SAF_DENO_MODE=probe SAF_DENO_OUTPUT=$probe_text \
        "$deno" eval --quiet "$parser" "$probe_json" "$probe_text" >/dev/null 2>&1 || return 1
    line=$(cat "$probe_text" 2>/dev/null) || return 1
    IFS=$'\t' read -r SOURCE_VIDEO_CODEC SOURCE_VIDEO_HEIGHT SOURCE_VIDEO_BITRATE SOURCE_PIXEL_FORMAT SOURCE_DURATION SOURCE_AUDIO_CODECS <<< "$line"
    [[ $SOURCE_VIDEO_CODEC == NONE ]] && SOURCE_VIDEO_CODEC=
    [[ $SOURCE_VIDEO_HEIGHT == NONE ]] && SOURCE_VIDEO_HEIGHT=
    [[ $SOURCE_VIDEO_BITRATE == NONE ]] && SOURCE_VIDEO_BITRATE=
    [[ $SOURCE_PIXEL_FORMAT == NONE ]] && SOURCE_PIXEL_FORMAT=
    [[ $SOURCE_DURATION == NONE ]] && SOURCE_DURATION=
    [[ $SOURCE_AUDIO_CODECS == NONE ]] && SOURCE_AUDIO_CODECS=
    [[ -n $SOURCE_VIDEO_CODEC ]]
}

estimate_video_bitrate() {
    local calculator result
    "$ffprobe" -v error -select_streams v:0 -show_entries packet=size -of csv=p=0 \
        "$INPUT_FILE" > "$packet_text" 2>/dev/null || return 1
    calculator=$(cat <<'JS'
const [packetsPath, outputPath, durationText] = Deno.args;
const duration = Number(durationText);
if (!Number.isFinite(duration) || duration <= 0) throw new Error('Invalid duration');
const sizes = (await Deno.readTextFile(packetsPath)).split(/\r?\n/).filter(Boolean).map(Number);
if (!sizes.length || sizes.some((size) => !Number.isFinite(size) || size < 0)) throw new Error('Invalid packet size');
const bytes = sizes.reduce((sum, size) => sum + size, 0);
if (bytes <= 0) throw new Error('No video packets');
await Deno.writeTextFile(outputPath, String(Math.round(bytes * 8 / duration)));
JS
)
    SAF_DENO_MODE=bitrate SAF_DENO_OUTPUT=$bitrate_text \
        "$deno" eval --quiet "$calculator" "$packet_text" "$bitrate_text" "$SOURCE_DURATION" >/dev/null 2>&1 || return 1
    result=$(cat "$bitrate_text" 2>/dev/null) || return 1
    case $result in ''|*[!0-9]*) return 1 ;; esac
    ((result > 0)) || return 1
    SOURCE_VIDEO_BITRATE=$result
}

select_bitrate_coefficient() {
    local band key
    band=LOW
    ((SOURCE_VIDEO_HEIGHT > 720)) && band=HD
    ((SOURCE_VIDEO_HEIGHT > 1080)) && band=UHD
    key=$band:$SOURCE_CODEC:$TARGET_CODEC
    case $key in
        LOW:H264:H265) BITRATE_COEFFICIENT=80 ;;
        LOW:H264:AV1) BITRATE_COEFFICIENT=70 ;;
        LOW:VP9:AV1) BITRATE_COEFFICIENT=95 ;;
        LOW:H265:AV1) BITRATE_COEFFICIENT=90 ;;
        LOW:VP9:H264|LOW:H265:H264) BITRATE_COEFFICIENT=125 ;;
        LOW:AV1:H264) BITRATE_COEFFICIENT=143 ;;
        LOW:AV1:H265) BITRATE_COEFFICIENT=111 ;;
        HD:H264:H265) BITRATE_COEFFICIENT=70 ;;
        HD:H264:AV1) BITRATE_COEFFICIENT=60 ;;
        HD:VP9:AV1) BITRATE_COEFFICIENT=90 ;;
        HD:H265:AV1) BITRATE_COEFFICIENT=85 ;;
        HD:VP9:H264|HD:H265:H264) BITRATE_COEFFICIENT=143 ;;
        HD:AV1:H264) BITRATE_COEFFICIENT=167 ;;
        HD:AV1:H265) BITRATE_COEFFICIENT=118 ;;
        UHD:H264:H265) BITRATE_COEFFICIENT=60 ;;
        UHD:H264:AV1) BITRATE_COEFFICIENT=50 ;;
        UHD:VP9:AV1) BITRATE_COEFFICIENT=80 ;;
        UHD:H265:AV1) BITRATE_COEFFICIENT=85 ;;
        UHD:VP9:H264|UHD:H265:H264) BITRATE_COEFFICIENT=167 ;;
        UHD:AV1:H264) BITRATE_COEFFICIENT=200 ;;
        UHD:AV1:H265) BITRATE_COEFFICIENT=118 ;;
        *) BITRATE_COEFFICIENT=100 ;;
    esac
}

calculate_video_bitrate() {
    case ${SOURCE_VIDEO_BITRATE:-} in
        ''|*[!0-9]*|0) estimate_video_bitrate || return 1 ;;
    esac
    case ${SOURCE_VIDEO_HEIGHT:-} in ''|*[!0-9]*) return 1 ;; esac
    select_bitrate_coefficient
    SOURCE_VIDEO_KBPS=$((SOURCE_VIDEO_BITRATE / 1000))
    TARGET_VIDEO_BITRATE=$((SOURCE_VIDEO_KBPS * BITRATE_COEFFICIENT / 100))
    TARGET_VIDEO_BITRATE=$((TARGET_VIDEO_BITRATE * 110 / 100))
    ((TARGET_VIDEO_BITRATE > 0)) || TARGET_VIDEO_BITRATE=1
}

probe_hardware_encoder() {
    local encoder=$1
    if [[ $encoder == *_vaapi ]]; then
        "$ffmpeg" -hide_banner -loglevel error -vaapi_device /dev/dri/renderD128 \
            -f lavfi -i color=c=black:s=256x144:r=30:d=0.1 -vf format=nv12,hwupload \
            -frames:v 1 -an -c:v "$encoder" -f null /dev/null >/dev/null 2>&1
    else
        "$ffmpeg" -hide_banner -loglevel error -f lavfi -i color=c=black:s=256x144:r=30:d=0.1 \
            -frames:v 1 -an -c:v "$encoder" -f null /dev/null >/dev/null 2>&1
    fi
}

choose_encoder() {
    local target=$1 encoder encoders
    local -a candidates=()
    USING_HARDWARE=NO
    case $target in
        NONE) SOFTWARE_ENCODER=copy ;;
        AV1)
            encoders=$("$ffmpeg" -hide_banner -encoders 2>&1) || return 1
            case $encoders in
                *libsvtav1*) SOFTWARE_ENCODER=libsvtav1 ;;
                *libaom-av1*) SOFTWARE_ENCODER=libaom-av1 ;;
                *) return 1 ;;
            esac
            ;;
        H265) SOFTWARE_ENCODER=libx265 ;;
        H264) SOFTWARE_ENCODER=libx264 ;;
    esac
    SELECTED_ENCODER=$SOFTWARE_ENCODER
    [[ $target != NONE && $ALLOW_HARDWARE_TRANSCODING == YES ]] || return 0
    if [[ $platform_id == linux-* ]]; then
        case $target in
            AV1) candidates=(av1_nvenc av1_qsv) ;;
            H265) candidates=(hevc_nvenc hevc_qsv) ;;
            H264) candidates=(h264_nvenc h264_qsv) ;;
        esac
        if [[ ${SAF_TEST_VAAPI_AVAILABLE:-NO} == YES || -e /dev/dri/renderD128 ]]; then
            case $target in
                AV1) candidates+=(av1_vaapi) ;;
                H265) candidates+=(hevc_vaapi) ;;
                H264) candidates+=(h264_vaapi) ;;
            esac
        fi
    elif [[ $platform_id == macos-* ]]; then
        case $target in
            H265) candidates=(hevc_videotoolbox) ;;
            H264) candidates=(h264_videotoolbox) ;;
        esac
    fi
    for encoder in "${candidates[@]}"; do
        if probe_hardware_encoder "$encoder"; then
            SELECTED_ENCODER=$encoder
            USING_HARDWARE=YES
            return 0
        fi
    done
}

set_video_arguments() {
    local encoder=$1
    ENCODE_VIDEO_BITRATE=${TARGET_VIDEO_BITRATE:-0}
    [[ $USING_HARDWARE == YES ]] && ENCODE_VIDEO_BITRATE=$((ENCODE_VIDEO_BITRATE * 110 / 100))
    ENCODE_MAX_BITRATE=$((ENCODE_VIDEO_BITRATE * 3 / 2))
    ENCODE_BUFFER_SIZE=$((ENCODE_VIDEO_BITRATE * 2))
    VIDEO_ARGS=(-c:v "$encoder")
    FFMPEG_INPUT_ARGS=()
    METADATA_ARGS=()
    [[ $encoder == copy ]] && return 0
    METADATA_ARGS=(-metadata:s:v:0 "handler_name=Transcoded from $SOURCE_CODEC by SaF yt-dlp Wrapper")
    case $encoder in
        libsvtav1) VIDEO_ARGS=(-c:v libsvtav1 -preset 6 -b:v "${ENCODE_VIDEO_BITRATE}k") ;;
        libaom-av1) VIDEO_ARGS=(-c:v libaom-av1 -cpu-used 6 -b:v "${ENCODE_VIDEO_BITRATE}k") ;;
        libx265) VIDEO_ARGS=(-c:v libx265 -preset medium -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k" -tag:v hvc1) ;;
        libx264) VIDEO_ARGS=(-c:v libx264 -preset medium -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k" -pix_fmt yuv420p) ;;
        av1_nvenc) VIDEO_ARGS=(-c:v av1_nvenc -preset p6 -tune hq -rc vbr -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k" -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32) ;;
        hevc_nvenc) VIDEO_ARGS=(-c:v hevc_nvenc -preset p6 -tune hq -rc vbr -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k" -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32 -tag:v hvc1) ;;
        h264_nvenc) VIDEO_ARGS=(-c:v h264_nvenc -preset p6 -tune hq -rc vbr -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k" -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32 -pix_fmt yuv420p) ;;
        av1_qsv|hevc_qsv|h264_qsv)
            VIDEO_ARGS=(-c:v "$encoder" -preset slow -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k")
            [[ $encoder == hevc_qsv ]] && VIDEO_ARGS+=(-tag:v hvc1)
            [[ $encoder == h264_qsv ]] && VIDEO_ARGS+=(-pix_fmt yuv420p)
            ;;
        av1_vaapi|hevc_vaapi|h264_vaapi)
            FFMPEG_INPUT_ARGS=(-vaapi_device /dev/dri/renderD128)
            VIDEO_ARGS=(-vf format=nv12,hwupload -c:v "$encoder" -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k")
            [[ $encoder == hevc_vaapi ]] && VIDEO_ARGS+=(-tag:v hvc1)
            ;;
        hevc_videotoolbox|h264_videotoolbox)
            VIDEO_ARGS=(-c:v "$encoder" -b:v "${ENCODE_VIDEO_BITRATE}k" -maxrate "${ENCODE_MAX_BITRATE}k" -bufsize "${ENCODE_BUFFER_SIZE}k")
            [[ $encoder == hevc_videotoolbox ]] && VIDEO_ARGS+=(-tag:v hvc1)
            [[ $encoder == h264_videotoolbox ]] && VIDEO_ARGS+=(-pix_fmt yuv420p)
            ;;
    esac
}

set_audio_transcode_arguments() {
    AUDIO_ARGS=(-c:a copy)
    [[ $AUDIO_ACTION == AAC ]] && AUDIO_ARGS=(-c:a aac -b:a 192k)
}

language_metadata() {
    local language=$1 primary iso name
    primary=$(printf '%s' "${language%%-*}" | tr '[:upper:]' '[:lower:]')
    case $primary in
        en) iso=eng; name=English ;; ru) iso=rus; name=Russian ;; uz) iso=uzb; name=Uzbek ;;
        uk) iso=ukr; name=Ukrainian ;; de) iso=deu; name=German ;; fr) iso=fra; name=French ;;
        es) iso=spa; name=Spanish ;; it) iso=ita; name=Italian ;; pt) iso=por; name=Portuguese ;;
        pl) iso=pol; name=Polish ;; cs) iso=ces; name=Czech ;; tr) iso=tur; name=Turkish ;;
        ar) iso=ara; name=Arabic ;; hi) iso=hin; name=Hindi ;; ja) iso=jpn; name=Japanese ;;
        ko) iso=kor; name=Korean ;; zh) iso=zho; name=Chinese ;; id) iso=ind; name=Indonesian ;;
        vi) iso=vie; name=Vietnamese ;; th) iso=tha; name=Thai ;; nl) iso=nld; name=Dutch ;;
        sv) iso=swe; name=Swedish ;; no) iso=nor; name=Norwegian ;; da) iso=dan; name=Danish ;;
        fi) iso=fin; name=Finnish ;; el) iso=ell; name=Greek ;; he) iso=heb; name=Hebrew ;;
        [a-z][a-z][a-z]) iso=$primary; name=$(printf '%s' "$primary" | tr '[:lower:]' '[:upper:]') ;;
        *) iso=und; name=Unknown ;;
    esac
    printf '%s\t%s' "$iso" "$name"
}

set_audio_metadata_arguments() {
    local remainder=$1 item metadata iso name index=0
    AUDIO_METADATA_ARGS=()
    [[ $remainder == NONE ]] && remainder=
    while [[ -n $remainder ]]; do
        item=${remainder%%+*}
        if [[ $remainder == *+* ]]; then remainder=${remainder#*+}; else remainder=; fi
        metadata=$(language_metadata "$item")
        IFS=$'\t' read -r iso name <<< "$metadata"
        AUDIO_METADATA_ARGS+=(-metadata:s:a:$index "language=$iso" -metadata:s:a:$index "handler_name=$name")
        if ((index == 0)); then
            AUDIO_METADATA_ARGS+=(-disposition:a:$index default)
        else
            AUDIO_METADATA_ARGS+=(-disposition:a:$index 0)
        fi
        index=$((index + 1))
    done
}

cleanup_transcode_artifacts() {
    rm -f "$TEMP_OUTPUT" 2>/dev/null || true
    rm -f "$PASSLOG_FILE" "$PASSLOG_FILE"-0.log "$PASSLOG_FILE"-0.log.mbtree \
        "$PASSLOG_FILE".log "$PASSLOG_FILE".log.mbtree 2>/dev/null || true
}

run_ffmpeg_transcode() {
    if [[ $SELECTED_ENCODER != copy && $USING_HARDWARE == NO ]]; then
        "$ffmpeg" -y -hide_banner "${FFMPEG_INPUT_ARGS[@]}" -i "$INPUT_FILE" \
            -map 0:v:0 -an -sn -dn "${VIDEO_ARGS[@]}" -pass 1 -passlogfile "$PASSLOG_FILE" \
            -f null /dev/null || return 1
        "$ffmpeg" -y -hide_banner "${FFMPEG_INPUT_ARGS[@]}" -i "$INPUT_FILE" \
            -map 0:v:0 -map '0:a?' -map_metadata 0 -map_chapters 0 \
            "${METADATA_ARGS[@]}" "${AUDIO_METADATA_ARGS[@]}" "${VIDEO_ARGS[@]}" \
            -pass 2 -passlogfile "$PASSLOG_FILE" "${AUDIO_ARGS[@]}" -movflags +faststart "$TEMP_OUTPUT"
        return $?
    fi
    "$ffmpeg" -y -hide_banner "${FFMPEG_INPUT_ARGS[@]}" -i "$INPUT_FILE" \
        -map 0:v:0 -map '0:a?' -map_metadata 0 -map_chapters 0 \
        "${METADATA_ARGS[@]}" "${AUDIO_METADATA_ARGS[@]}" "${VIDEO_ARGS[@]}" \
        "${AUDIO_ARGS[@]}" -movflags +faststart "$TEMP_OUTPUT"
}

transcode_media() {
    local stem
    stem=${INPUT_FILE%.*}
    OUTPUT_FILE=$stem.mp4
    TEMP_OUTPUT=$stem.saf-transcoding.mp4
    PASSLOG_FILE=$job_dir/saf-passlog
    cleanup_transcode_artifacts
    [[ $TARGET_CODEC == NONE ]] || calculate_video_bitrate || return 1
    choose_encoder "$TARGET_CODEC"
    set_video_arguments "$SELECTED_ENCODER"
    set_audio_transcode_arguments
    printf '\nTranscoding with %s...\n' "$SELECTED_ENCODER"
    if ! run_ffmpeg_transcode; then
        if [[ $USING_HARDWARE == YES ]]; then
            printf 'Hardware encoding failed. Falling back to CPU...\n'
            cleanup_transcode_artifacts
            SELECTED_ENCODER=$SOFTWARE_ENCODER
            USING_HARDWARE=NO
            set_video_arguments "$SELECTED_ENCODER"
            run_ffmpeg_transcode || { cleanup_transcode_artifacts; return 1; }
        else
            cleanup_transcode_artifacts
            return 1
        fi
    fi
    [[ -f $TEMP_OUTPUT ]] || return 1
    if [[ $INPUT_FILE != "$OUTPUT_FILE" && -e $OUTPUT_FILE ]]; then
        cleanup_transcode_artifacts
        return 1
    fi
    mv -f "$TEMP_OUTPUT" "$OUTPUT_FILE" || return 1
    [[ $INPUT_FILE == "$OUTPUT_FILE" ]] || rm -f "$INPUT_FILE"
    cleanup_transcode_artifacts
}

select_aac_action() {
    local codec
    AUDIO_ACTION=AAC
    if [[ $DOWNLOAD_ALL_AUDIO_TRACKS == YES ]]; then
        local old_ifs=$IFS
        IFS=,
        for codec in $SOURCE_AUDIO_CODECS; do
            case $(printf '%s' "$codec" | tr '[:upper:]' '[:lower:]') in aac*|mp4a*) ;; *) IFS=$old_ifs; return 0 ;; esac
        done
        IFS=$old_ifs
        AUDIO_ACTION=COPY
        return 0
    fi
    case $(printf '%s' "$AUDIO_CODEC" | tr '[:upper:]' '[:lower:]') in aac*|mp4a*|none|'') AUDIO_ACTION=COPY ;; esac
}

process_download() {
    local extension first_audio
    INPUT_FILE=$QUEUED_INPUT
    AUDIO_CODEC=$QUEUED_AUDIO_CODEC
    TARGET_CODEC=NONE
    AUDIO_ACTION=COPY
    NEEDS_REMUX=NO
    AUDIO_METADATA_ARGS=()
    inspect_media || return 1
    SOURCE_CODEC=$(normalize_codec "$SOURCE_VIDEO_CODEC")
    set_audio_metadata_arguments "$QUEUED_AUDIO_LANGUAGES"
    case $PROFILE in
        QUALITY)
            [[ $SOURCE_CODEC == VP9 && $TRANSCODE_VP9_TO_AV1 == YES ]] && TARGET_CODEC=AV1
            ;;
        MODERN)
            TARGET_CODEC=H265
            [[ $SOURCE_CODEC == H265 ]] && TARGET_CODEC=NONE
            if [[ $SOURCE_CODEC == H264 && ( $SOURCE_PIXEL_FORMAT == yuv420p || $SOURCE_PIXEL_FORMAT == yuvj420p ) ]]; then TARGET_CODEC=NONE; fi
            select_aac_action
            ;;
        UNIVERSAL)
            TARGET_CODEC=H264
            [[ $SOURCE_CODEC == H264 && ( $SOURCE_PIXEL_FORMAT == yuv420p || $SOURCE_PIXEL_FORMAT == yuvj420p ) ]] && TARGET_CODEC=NONE
            first_audio=${SOURCE_AUDIO_CODECS%%,*}
            AUDIO_CODEC=${first_audio:-none}
            select_aac_action
            ;;
    esac
    extension=${INPUT_FILE##*.}
    [[ $(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]') == mp4 ]] || NEEDS_REMUX=YES
    [[ $DOWNLOAD_ALL_AUDIO_TRACKS == YES ]] && NEEDS_REMUX=YES
    if [[ $TARGET_CODEC == NONE && $AUDIO_ACTION == COPY && $NEEDS_REMUX == NO ]]; then
        return 0
    fi
    transcode_media
}

process_postprocess_queue() {
    local line fields failed=0
    [[ -f $postprocess_list ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        IFS=$'\t' read -r QUEUED_INPUT QUEUED_VIDEO_CODEC QUEUED_AUDIO_CODEC QUEUED_AUDIO_LANGUAGES fields <<< "$line"
        if [[ -n ${fields:-} || -z ${QUEUED_INPUT:-} || -z ${QUEUED_VIDEO_CODEC:-} || -z ${QUEUED_AUDIO_CODEC:-} ]]; then
            failed=1
            continue
        fi
        case $QUEUED_INPUT in "$job_downloads"/*) ;; *) failed=1; continue ;; esac
        [[ -f $QUEUED_INPUT ]] || { failed=1; continue; }
        process_download || failed=1
    done < "$postprocess_list"
    rm -f "$postprocess_list"
    if ((failed != 0)); then
        printf 'Conversion failed; the downloaded source was kept.\n' >&2
        return 1
    fi
}

collision_target() {
    local target=$1 directory filename stem extension candidate number=1
    directory=${target%/*}
    filename=${target##*/}
    if [[ $filename == *.* ]]; then
        stem=${filename%.*}
        extension=.${filename##*.}
    else
        stem=$filename
        extension=
    fi
    candidate=$target
    while [[ -e $candidate ]]; do
        candidate=$directory/$stem\ \($number\)$extension
        number=$((number + 1))
    done
    printf '%s' "$candidate"
}

publish_job() {
    local source relative target target_directory moved=0
    while IFS= read -r -d '' source; do
        if [[ -n ${SAF_TEST_PUBLISH_FAIL_AFTER:-} && $moved -ge $SAF_TEST_PUBLISH_FAIL_AFTER ]]; then
            return 1
        fi
        relative=${source#"$job_downloads"/}
        target=$downloads_dir/$relative
        target_directory=${target%/*}
        mkdir -p "$target_directory" || return 1
        target=$(collision_target "$target")
        if [[ $platform_id == linux-* ]]; then
            mv -- "$source" "$target" || return 1
        else
            mv "$source" "$target" || return 1
        fi
        moved=$((moved + 1))
    done < <(find "$job_downloads" -type f -print0)
}

clear_temp_dir() {
    local stale saved_downloads
    for stale in "$temp_dir"/* "$temp_dir"/.[!.]* "$temp_dir"/..?*; do
        [[ -e $stale || -L $stale ]] || continue
        if [[ -d $stale/downloads && -n $(find "$stale/downloads" -type f -print 2>/dev/null | sed -n '1p') ]]; then
            saved_downloads=${job_downloads:-}
            job_downloads=$stale/downloads
            if ! publish_job; then
                job_downloads=$saved_downloads
                printf 'Error: unfinished media is still preserved in %s and could not be moved to Downloads.\n' "$stale/downloads" >&2
                return 1
            fi
            job_downloads=$saved_downloads
        fi
        rm -rf "$stale" || return 1
    done
}

interactive_loop() {
    local choice mode result process_result publish_result
    while true; do
        printf '\nPaste video or playlist URL (blank to exit): '
        IFS= read -r URL || URL=
        [[ -n $URL ]] || return 0
        prepare_job || return 1
        cookie_selection_done=NO
        cookie_source=
        cookie_source_label=
        cookie_skip_label=
        media_metadata_args=()

        printf '\nDownload:\n  1. Video\n  2. Audio only\n  3. Thumbnail only\n'
        while true; do
            printf 'Select [%s]: ' "$DEFAULT_MODE"
            IFS= read -r choice || choice=
            case $choice in
                '') mode=$DEFAULT_MODE ;;
                1) mode=video ;;
                2) mode=audio ;;
                3) mode=thumbnail ;;
                *) printf 'Invalid choice. Enter 1, 2, or 3.\n'; continue ;;
            esac
            break
        done

        result=0
        case $mode in
            video) download_video || result=$? ;;
            audio) download_audio || result=$? ;;
            thumbnail) download_thumbnail || result=$? ;;
        esac
        process_result=0
        process_postprocess_queue || process_result=$?
        ((process_result == 0)) || result=$process_result
        publish_result=0
        publish_job || publish_result=$?
        if ((publish_result == 0)); then
            cleanup_job
        else
            preserved_job=$job_dir
            job_dir=
        fi
        if ((result != 0)); then
            printf '\nDownload failed. Check the URL and the message above.\n'
        elif ((publish_result != 0)); then
            printf '\nDownload failed. Finished files could not be moved to the Downloads folder.\n'
            printf 'Unmoved files were preserved in %s/downloads.\n' "$preserved_job"
        else
            printf '\nDownload complete.\n'
        fi
    done
}

main() {
    select_platform || return 1
    if [[ ${1:-} == --internal-dependency-map ]]; then
        print_dependency_map
        return 0
    fi
    if [[ ${1:-} == --internal-select-formats ]]; then
        if (($# != 6)); then
            printf 'Error: internal format selection requires metadata, output, mode, profile, and maximum height.\n' >&2
            return 1
        fi
        metadata_file=$2
        selections_file=$3
        PROFILE=$(uppercase "$5")
        MAX_HEIGHT=$6
        deno=${SAF_TEST_DENO:-$deno}
        select_formats "$4"
        return $?
    fi
    if [[ ${1:-} == --internal-calculate-bitrate ]]; then
        if (($# != 6)); then
            printf 'Error: internal bitrate calculation requires source codec, target codec, height, bitrate, and hardware flag.\n' >&2
            return 1
        fi
        SOURCE_CODEC=$(uppercase "$2")
        TARGET_CODEC=$(uppercase "$3")
        SOURCE_VIDEO_HEIGHT=$4
        SOURCE_VIDEO_BITRATE=$5
        calculate_video_bitrate || return 1
        if [[ $(uppercase "$6") == YES ]]; then TARGET_VIDEO_BITRATE=$((TARGET_VIDEO_BITRATE * 110 / 100)); fi
        printf '%s\n' "$TARGET_VIDEO_BITRATE"
        return 0
    fi

    load_config || return 1
    mkdir -p "$dependencies_dir" "$temp_dir" "$downloads_dir" || return 1
    clear_temp_dir || return 1

    [[ -x $ytdlp ]] || install_ytdlp || return 1
    [[ -x $deno ]] || install_deno || return 1
    if [[ ! -x $ffmpeg || ! -x $ffprobe ]]; then
        install_ffmpeg || return 1
    fi

    printf 'Updating yt-dlp nightly...\n'
    if ! update_ytdlp; then
        printf 'Warning: yt-dlp update failed. Using the installed version.\n' >&2
    fi

    interactive_loop
}

trap cleanup_job EXIT
main "$@"

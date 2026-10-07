#!/usr/bin/env bash
set -uo pipefail

passed=0
failed=0
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
launcher=$repo_root/SaF-YTDLP.sh

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

assert_contains() {
    case $1 in
        *"$2"*) return 0 ;;
        *) printf 'Missing text: %s\nOutput:\n%s\n' "$2" "$1" >&2; return 1 ;;
    esac
}

assert_not_contains() {
    case $1 in
        *"$2"*) printf 'Unexpected text: %s\nOutput:\n%s\n' "$2" "$1" >&2; return 1 ;;
        *) return 0 ;;
    esac
}

count_contains() {
    printf '%s\n' "$1" | grep -F -c -- "$2" || true
}

run_scenario() {
    local config=$1 input=$2
    local cookie_success=${3:-chrome}
    local selections=${4:-$'0\tv-hevc\tNONE\tNO\tNO\tNONE\n'}
    local media_name=${5:-sample.mp4}
    local platform=${6:-Linux}
    local fixture argument_log ffmpeg_log output config_text file profile_root
    fixture=$(mktemp -d) || return 1
    mkdir -p "$fixture/internal/dependencies"
    cp "$launcher" "$fixture/SaF-YTDLP.sh"
    cp "$repo_root/tests/FakeYtdlp.sh" "$fixture/internal/dependencies/yt-dlp"
    cp "$repo_root/tests/FakeYtdlp.sh" "$fixture/internal/dependencies/deno"
    cp "$repo_root/tests/FakeFfmpeg.sh" "$fixture/internal/dependencies/ffmpeg"
    cp "$repo_root/tests/FakeFfmpeg.sh" "$fixture/internal/dependencies/ffprobe"
    chmod +x "$fixture/SaF-YTDLP.sh" "$fixture/internal/dependencies/"*
    config_text=$'PROFILE=MODERN\nMAX_HEIGHT=1080\nDEFAULT_MODE=video\nTRANSCODE_VP9_TO_AV1=YES\nALLOW_HARDWARE_TRANSCODING=YES\nSTORE_OPUS_IN_MP4=YES\nDOWNLOAD_ALL_AUDIO_TRACKS=NO\nCOOKIE_BROWSER=\n'
    printf '%s%s\n' "$config_text" "$config" > "$fixture/config.ini"
    case ${SAF_SCENARIO_PROFILE_FIXTURE:-} in
        zen-linux)
            profile_root="$fixture/home/.zen/Profile One"
            mkdir -p "$profile_root"
            : > "$profile_root/cookies.sqlite"
            ;;
        comet-linux)
            profile_root="$fixture/home/.config/Perplexity/Comet/User Data/Profile 2/Network"
            mkdir -p "$profile_root"
            : > "$profile_root/Cookies"
            ;;
        zen-macos)
            profile_root="$fixture/home/Library/Application Support/zen/Profiles/Profile One"
            mkdir -p "$profile_root"
            : > "$profile_root/cookies.sqlite"
            ;;
    esac
    argument_log=$fixture/arguments.log
    ffmpeg_log=$fixture/ffmpeg.log
    output=$(cd "$fixture" && printf '%b' "$input" | \
        HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/home/.config" \
        SAF_TEST_UNAME_S="$platform" SAF_TEST_UNAME_M=x86_64 \
        SAF_ARGUMENT_LOG="$argument_log" SAF_FAKE_COOKIE_SUCCESS="$cookie_success" \
        SAF_FAKE_SELECTIONS="$selections" SAF_FAKE_METADATA_JSON='{"id":"test","formats":[]}' \
        SAF_FAKE_MEDIA_NAME="$media_name" \
        SAF_FAKE_VIDEO_CODEC="${SAF_SCENARIO_VIDEO_CODEC:-h264}" \
        SAF_FAKE_AUDIO_CODEC="${SAF_SCENARIO_AUDIO_CODEC:-aac}" \
        SAF_FAKE_AUDIO_CODECS="${SAF_SCENARIO_AUDIO_CODECS:-aac}" \
        SAF_FAKE_AUDIO_LANGUAGES="${SAF_SCENARIO_AUDIO_LANGUAGES:-}" \
        SAF_FAKE_VIDEO_HEIGHT="${SAF_SCENARIO_VIDEO_HEIGHT:-1080}" \
        SAF_FAKE_VIDEO_BITRATE="${SAF_SCENARIO_VIDEO_BITRATE:-8000000}" \
        SAF_FAKE_PIXEL_FORMAT="${SAF_SCENARIO_PIXEL_FORMAT:-yuv420p}" \
        SAF_FAKE_DURATION="${SAF_SCENARIO_DURATION:-10}" \
        SAF_FAKE_PACKET_SIZES="${SAF_SCENARIO_PACKET_SIZES:-5000000,5000000}" \
        SAF_FAKE_PACKET_BITRATE="${SAF_SCENARIO_PACKET_BITRATE:-8000000}" \
        SAF_FAKE_DENO_PROBE_EXIT="${SAF_SCENARIO_DENO_PROBE_EXIT:-0}" \
        SAF_FAKE_ENCODERS="${SAF_SCENARIO_ENCODERS:-}" \
        SAF_FAKE_FAIL_ENCODER="${SAF_SCENARIO_FAIL_ENCODER:-}" \
        SAF_FAKE_FAIL_INPUT_CONTAINS="${SAF_SCENARIO_FAIL_INPUT_CONTAINS:-}" \
        SAF_REAL_DENO="${SAF_SCENARIO_REAL_DENO_PATH:-}" \
        SAF_TEST_VAAPI_AVAILABLE="${SAF_SCENARIO_VAAPI_AVAILABLE:-NO}" \
        SAF_TEST_PUBLISH_FAIL_AFTER="${SAF_SCENARIO_PUBLISH_FAIL_AFTER:-}" \
        SAF_FFMPEG_LOG="$ffmpeg_log" \
        SAF_FAKE_DOWNLOAD_FAIL_COOKIE="${SAF_SCENARIO_DOWNLOAD_FAIL_COOKIE:-}" \
        SAF_FAKE_DOWNLOAD_EXIT="${SAF_SCENARIO_DOWNLOAD_EXIT:-0}" \
        ./SaF-YTDLP.sh 2>&1)
    SCENARIO_EXIT=$?
    SCENARIO_OUTPUT=$output
    SCENARIO_ARGUMENTS=$(cat "$argument_log" 2>/dev/null || true)
    SCENARIO_FFMPEG=$(cat "$ffmpeg_log" 2>/dev/null || true)
    SCENARIO_CONFIG=$(cat "$fixture/config.ini")
    SCENARIO_FILES=
    if [[ -d $fixture/Downloads ]]; then
        while IFS= read -r file; do
            SCENARIO_FILES=${SCENARIO_FILES}${file##*/}$'\n'
        done < <(find "$fixture/Downloads" -type f -print)
    fi
    SCENARIO_TEMP_FILES=$(find "$fixture/internal/temp" -mindepth 1 -print 2>/dev/null || true)
    rm -rf "$fixture"
}

test_interaction_and_modes() {
    run_scenario 'DEFAULT_MODE=video' $'https://example.test/watch?v=abc&list=xyz!mark\n\n\n' chrome $'0\tv-hevc\tNONE\tNO\tNO\tNONE\n' 'video.mp4' || return 1
    [[ $SCENARIO_EXIT -eq 0 ]] || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[https://example.test/watch?v=abc&list=xyz!mark]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--embed-chapters]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[v-hevc+ba[acodec^=mp4a]/v-hevc+ba/v-hevc]' || return 1
    assert_contains "$SCENARIO_FILES" 'video.mp4' || return 1

    run_scenario 'DEFAULT_MODE=video' $'https://example.test/audio\n2\n\n' chrome '' 'audio.m4a' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--extract-audio]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--embed-thumbnail]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--embed-chapters]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--embed-metadata]' || return 1

    run_scenario 'DEFAULT_MODE=video' $'https://example.test/thumb\n9\n3\n\n' chrome '' 'cover.webp' || return 1
    assert_contains "$SCENARIO_OUTPUT" 'Invalid choice' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--skip-download]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--write-thumbnail]'
}

test_multitrack_download_selection() {
    run_scenario 'DOWNLOAD_ALL_AUDIO_TRACKS=YES' $'https://example.test/multitrack\n\n\n' chrome $'0\tv1\ta-en+a-ru\tNO\tNO\ten+ru\n' 'multi.mkv' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--audio-multistreams]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[v1+a-en+a-ru]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'en+ru'
}

test_real_deno_format_selection() {
    local deno_path=${SAF_TEST_DENO:-} fixture output
    if [[ -z $deno_path ]]; then
        deno_path=$(command -v deno 2>/dev/null || true)
    fi
    if [[ -z $deno_path || ! -x $deno_path ]]; then
        printf 'SKIP real Deno selector (Deno is not installed in the test environment).\n'
        return 0
    fi
    fixture=$(mktemp -d)
    cat > "$fixture/modern.json" <<'JSON'
{"id":"modern","formats":[
 {"format_id":"vp9-4k","vcodec":"vp9","acodec":"none","height":2160,"fps":30,"tbr":9000},
 {"format_id":"vp9","vcodec":"vp9","acodec":"none","height":1080,"fps":30,"tbr":8000},
 {"format_id":"av1","vcodec":"av01.0.08M.08","acodec":"none","height":1080,"fps":30,"tbr":7000},
 {"format_id":"h264","vcodec":"avc1.640028","acodec":"none","height":1080,"fps":30,"tbr":6000},
 {"format_id":"h265","vcodec":"hvc1.2.4.L120.B0","acodec":"none","height":1080,"fps":30,"tbr":5000},
 {"format_id":"aac-en","vcodec":"none","acodec":"mp4a.40.2","language":"en","abr":128}
]}
JSON
    SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_TEST_DENO="$deno_path" \
        "$launcher" --internal-select-formats "$fixture/modern.json" "$fixture/modern.tsv" video MODERN 1080 || { rm -rf "$fixture"; return 1; }
    output=$(cat "$fixture/modern.tsv")
    assert_contains "$output" $'0\th265\taac-en' || { rm -rf "$fixture"; return 1; }
    SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_TEST_DENO="$deno_path" \
        "$launcher" --internal-select-formats "$fixture/modern.json" "$fixture/unlimited.tsv" video MODERN 0 || { rm -rf "$fixture"; return 1; }
    output=$(cat "$fixture/unlimited.tsv")
    assert_contains "$output" $'0\tvp9-4k\taac-en' || { rm -rf "$fixture"; return 1; }

    cat > "$fixture/quality.json" <<'JSON'
{"id":"quality","formats":[
 {"format_id":"vp9","vcodec":"vp09.00.50.08","acodec":"none","height":2160,"fps":25,"tbr":19117},
 {"format_id":"av1","vcodec":"av01.0.12M.08","acodec":"none","height":2160,"fps":25,"tbr":9024},
 {"format_id":"aac-en","vcodec":"none","acodec":"mp4a.40.2","language":"en","abr":129},
 {"format_id":"opus-en","vcodec":"none","acodec":"opus","language":"en","abr":128},
 {"format_id":"combined-ru","vcodec":"avc1","acodec":"mp4a.40.2","language":"ru","height":720,"abr":127}
]}
JSON
    SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_TEST_DENO="$deno_path" \
        "$launcher" --internal-select-formats "$fixture/quality.json" "$fixture/quality.tsv" video QUALITY 0 || { rm -rf "$fixture"; return 1; }
    output=$(cat "$fixture/quality.tsv")
    assert_contains "$output" $'0\tav1\topus-en+combined-ru' || { rm -rf "$fixture"; return 1; }
    assert_contains "$output" $'\tYES\tYES\ten+ru' || { rm -rf "$fixture"; return 1; }
    rm -rf "$fixture"
}

test_cookie_order_and_fallback() {
    SAF_SCENARIO_DOWNLOAD_FAIL_COOKIE=firefox
    run_scenario 'COOKIE_BROWSER=firefox' $'https://example.test/private\n3\n\n' edge '' 'cover.webp' || return 1
    unset SAF_SCENARIO_DOWNLOAD_FAIL_COOKIE
    assert_contains "$SCENARIO_OUTPUT" 'Saved browser session failed before downloading' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[firefox]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[edge]' || return 1
    assert_contains "$SCENARIO_CONFIG" 'COOKIE_BROWSER=edge' || return 1

    run_scenario 'COOKIE_BROWSER=firefox' $'https://example.test/public\n3\n\n' firefox '' 'cover.webp' || return 1
    [[ $(count_contains "$SCENARIO_ARGUMENTS" 'ARG=[--simulate]') -eq 0 ]] || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[firefox]' || return 1

    SAF_SCENARIO_DOWNLOAD_FAIL_COOKIE=firefox
    run_scenario 'COOKIE_BROWSER=firefox' $'https://example.test/public\n3\n\n' NONE '' 'cover.webp' || return 1
    unset SAF_SCENARIO_DOWNLOAD_FAIL_COOKIE
    assert_contains "$SCENARIO_OUTPUT" 'continuing without browser cookies' || return 1

    SAF_SCENARIO_PROFILE_FIXTURE=zen-linux run_scenario 'COOKIE_BROWSER=' $'https://example.test/zen\n3\n\n' '.zen' '' 'cover.webp' || return 1
    assert_contains "$SCENARIO_CONFIG" 'COOKIE_BROWSER=zen' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'firefox:/tmp/' || return 1

    SAF_SCENARIO_PROFILE_FIXTURE=comet-linux run_scenario 'COOKIE_BROWSER=' $'https://example.test/comet\n3\n\n' 'Perplexity/Comet' '' 'cover.webp' || return 1
    assert_contains "$SCENARIO_CONFIG" 'COOKIE_BROWSER=comet' || return 1

    SAF_SCENARIO_PROFILE_FIXTURE=zen-macos run_scenario 'COOKIE_BROWSER=' $'https://example.test/zen-macos\n3\n\n' 'Application Support/zen' '' 'cover.webp' Darwin || return 1
    unset SAF_SCENARIO_PROFILE_FIXTURE
    assert_contains "$SCENARIO_CONFIG" 'COOKIE_BROWSER=zen'
}

test_repeated_download_collision() {
    run_scenario 'DEFAULT_MODE=audio' $'https://example.test/one\n\nhttps://example.test/two\n\n\n' chrome '' 'same.m4a' || return 1
    assert_contains "$SCENARIO_FILES" 'same.m4a' || return 1
    assert_contains "$SCENARIO_FILES" 'same (1).m4a'
}

test_failed_and_partial_downloads_continue() {
    SAF_SCENARIO_DOWNLOAD_EXIT=1 run_scenario 'DEFAULT_MODE=audio' $'https://example.test/broken-one\n\nhttps://example.test/broken-two\n\n\n' chrome '' 'partial.m4a' || return 1
    unset SAF_SCENARIO_DOWNLOAD_EXIT
    assert_contains "$SCENARIO_OUTPUT" 'Download failed' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[https://example.test/broken-one]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[https://example.test/broken-two]' || return 1
    assert_contains "$SCENARIO_FILES" 'partial.m4a' || return 1

    run_scenario 'DOWNLOAD_ALL_AUDIO_TRACKS=YES' $'https://example.test/playlist\n\n\n' chrome $'ERROR\t1\n2\tv2\ta2-en\tNO\tNO\ten\n' 'playlist.mkv' || return 1
    assert_contains "$SCENARIO_OUTPUT" 'playlist entry 1 has no usable video format' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--playlist-items]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[2]'
}

test_profile_postprocessing_parity() {
    SAF_SCENARIO_VIDEO_CODEC=vp9 run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/quality\n\n\n' chrome '' 'quality.webm' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libsvtav1]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[7920k]' || return 1
    [[ $(count_contains "$SCENARIO_FFMPEG" 'ARG=[-pass]') -eq 2 ]] || return 1
    assert_contains "$SCENARIO_FILES" 'quality.mp4' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 run_scenario $'PROFILE=QUALITY\nTRANSCODE_VP9_TO_AV1=NO\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/remux\n\n\n' chrome '' 'quality.webm' || return 1
    assert_not_contains "$SCENARIO_FFMPEG" 'ARG=[libsvtav1]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-c:v]\nARG=[copy]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 run_scenario $'PROFILE=MODERN\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/modern\n\n\n' chrome $'0\tv1\tNONE\tNO\tNO\tNONE\n' 'modern.webm' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libx265]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[8800k]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=h265 run_scenario $'PROFILE=MODERN\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/native-h265\n\n\n' chrome $'0\tv1\tNONE\tNO\tNO\tNONE\n' 'native.mp4' || return 1
    assert_not_contains "$SCENARIO_FFMPEG" 'ARG=[libx265]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=av1 SAF_SCENARIO_AUDIO_CODECS=opus run_scenario $'PROFILE=UNIVERSAL\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/universal\n\n\n' chrome '' 'universal.webm' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libx264]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[14696k]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-c:a]\nARG=[aac]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=h264 SAF_SCENARIO_PIXEL_FORMAT=yuv444p run_scenario $'PROFILE=UNIVERSAL\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/pixel-format\n\n\n' chrome '' 'pixel.mp4' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libx264]'
}

test_bitrate_table_and_margins() {
    local row source target height expected output
    while IFS=: read -r source target height expected; do
        output=$(SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 "$launcher" --internal-calculate-bitrate "$source" "$target" "$height" 1000000 NO) || return 1
        [[ $output == "$expected" ]] || { printf 'Unexpected bitrate for %s:%s:%s: %s\n' "$source" "$target" "$height" "$output" >&2; return 1; }
    done <<'ROWS'
H264:H265:720:880
H264:AV1:720:770
VP9:AV1:720:1045
H265:AV1:720:990
VP9:H264:720:1375
H265:H264:720:1375
AV1:H264:720:1573
AV1:H265:720:1221
H264:H265:1080:770
H264:AV1:1080:660
VP9:AV1:1080:990
H265:AV1:1080:935
VP9:H264:1080:1573
H265:H264:1080:1573
AV1:H264:1080:1837
AV1:H265:1080:1298
H264:H265:2160:660
H264:AV1:2160:550
VP9:AV1:2160:880
H265:AV1:2160:935
VP9:H264:2160:1837
H265:H264:2160:1837
AV1:H264:2160:2200
AV1:H265:2160:1298
ROWS
    output=$(SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 "$launcher" --internal-calculate-bitrate VP9 AV1 1080 8000000 YES) || return 1
    [[ $output == 8712 ]]
}

test_hardware_candidates_and_cpu_fallback() {
    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_ENCODERS=av1_nvenc,av1_qsv,av1_vaapi run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=YES' $'https://example.test/nvidia\n\n\n' chrome '' 'gpu.webm' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[av1_nvenc]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[8712k]' || return 1
    assert_not_contains "$SCENARIO_FFMPEG" 'ARG=[-pass]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_ENCODERS=av1_qsv,av1_vaapi run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=YES' $'https://example.test/intel\n\n\n' chrome '' 'gpu.webm' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[av1_qsv]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_ENCODERS=av1_vaapi SAF_SCENARIO_VAAPI_AVAILABLE=YES run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=YES' $'https://example.test/vaapi\n\n\n' chrome '' 'gpu.webm' || return 1
    unset SAF_SCENARIO_VAAPI_AVAILABLE
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[av1_vaapi]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_ENCODERS=av1_nvenc SAF_SCENARIO_FAIL_ENCODER=av1_nvenc run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=YES' $'https://example.test/fallback\n\n\n' chrome '' 'gpu.webm' || return 1
    unset SAF_SCENARIO_FAIL_ENCODER
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[av1_nvenc]' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libsvtav1]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[8712k]' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[7920k]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_ENCODERS=av1_videotoolbox run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=YES' $'https://example.test/mac-av1\n\n\n' chrome '' 'mac.webm' Darwin || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libsvtav1]' || return 1
    assert_not_contains "$SCENARIO_FFMPEG" 'ARG=[av1_videotoolbox]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_ENCODERS=hevc_videotoolbox run_scenario $'PROFILE=MODERN\nALLOW_HARDWARE_TRANSCODING=YES' $'https://example.test/mac-h265\n\n\n' chrome $'0\tv1\tNONE\tNO\tNO\tNONE\n' 'mac.webm' Darwin || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[hevc_videotoolbox]'
}

test_multitrack_processing_metadata() {
    SAF_SCENARIO_VIDEO_CODEC=h264 SAF_SCENARIO_AUDIO_CODECS=aac,aac SAF_SCENARIO_AUDIO_LANGUAGES=en+ru run_scenario $'PROFILE=MODERN\nDOWNLOAD_ALL_AUDIO_TRACKS=YES\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/multi-aac\n\n\n' chrome $'0\tv1\ta-en+a-ru\tNO\tNO\ten+ru\n' 'multi.mkv' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-c:a]\nARG=[copy]' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[language=eng]' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[handler_name=Russian]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=h264 SAF_SCENARIO_AUDIO_CODECS=aac,opus SAF_SCENARIO_AUDIO_LANGUAGES=en+uz run_scenario $'PROFILE=MODERN\nDOWNLOAD_ALL_AUDIO_TRACKS=YES\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/multi-mixed\n\n\n' chrome $'0\tv1\ta-en+a-uz\tNO\tNO\ten+uz\n' 'multi.mkv' || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-c:a]\nARG=[aac]' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[language=uzb]' || return 1
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[handler_name=Uzbek]'
}

test_probe_paths_failures_and_cleanup() {
    local special='space %! & (日本語).webm'
    SAF_SCENARIO_VIDEO_CODEC=vp9 run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/special\n\n\n' chrome '' "$special" || return 1
    assert_contains "$SCENARIO_FFMPEG" "$special" || return 1
    [[ $(count_contains "$SCENARIO_FFMPEG" 'CALL=[ffprobe]') -eq 1 ]] || return 1
    assert_contains "$SCENARIO_FILES" 'space %! & (日本語).mp4' || return 1
    [[ -z $SCENARIO_TEMP_FILES ]] || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/dash\n\n\n' chrome '' '-leading-dash.webm' || return 1
    assert_contains "$SCENARIO_FFMPEG" '-leading-dash.webm' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_VIDEO_BITRATE=NONE SAF_SCENARIO_PACKET_BITRATE=8000000 run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/packets\n\n\n' chrome '' 'packets.webm' || return 1
    [[ $(count_contains "$SCENARIO_FFMPEG" 'CALL=[ffprobe]') -eq 2 ]] || return 1
    assert_contains "$SCENARIO_FFMPEG" $'ARG=[-b:v]\nARG=[7920k]' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_DENO_PROBE_EXIT=1 run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO' $'https://example.test/malformed\n\n\n' chrome '' 'malformed.webm' || return 1
    unset SAF_SCENARIO_DENO_PROBE_EXIT
    assert_contains "$SCENARIO_FILES" 'malformed.webm' || return 1
    assert_not_contains "$SCENARIO_FILES" 'malformed.mp4' || return 1
    assert_contains "$SCENARIO_OUTPUT" 'downloaded source was kept' || return 1

    SAF_SCENARIO_VIDEO_CODEC=vp9 SAF_SCENARIO_FAIL_INPUT_CONTAINS='entry-1.webm' run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO\nDOWNLOAD_ALL_AUDIO_TRACKS=YES' $'https://example.test/playlist\n\n\n' chrome $'1\tv1\ta-en\tNO\tNO\ten\n2\tv2\ta-en\tNO\tNO\ten\n' 'entry-%ITEM%.webm' || return 1
    unset SAF_SCENARIO_FAIL_INPUT_CONTAINS
    assert_contains "$SCENARIO_FILES" 'entry-1.webm' || return 1
    assert_contains "$SCENARIO_FILES" 'entry-2.mp4' || return 1
    [[ -z $SCENARIO_TEMP_FILES ]]
}

test_real_deno_media_inspection() {
    local deno_path=${SAF_TEST_DENO:-}
    if [[ -z $deno_path || ! -x $deno_path ]]; then
        printf 'SKIP real Deno media inspection (Deno is not installed in the test environment).\n'
        return 0
    fi
    SAF_SCENARIO_REAL_DENO_PATH=$deno_path SAF_SCENARIO_VIDEO_CODEC=vp9 \
        run_scenario $'PROFILE=QUALITY\nALLOW_HARDWARE_TRANSCODING=NO' \
        $'https://example.test/real-deno\n\n\n' chrome '' 'real-deno.webm' || return 1
    unset SAF_SCENARIO_REAL_DENO_PATH
    assert_contains "$SCENARIO_FFMPEG" 'ARG=[libsvtav1]' || return 1
    assert_contains "$SCENARIO_FILES" 'real-deno.mp4'
}

test_publish_failure_preserves_unmoved_media() {
    SAF_SCENARIO_PUBLISH_FAIL_AFTER=1 run_scenario 'DOWNLOAD_ALL_AUDIO_TRACKS=YES' \
        $'https://example.test/publish-failure\n\n\n' chrome \
        $'1\tv1\ta-en\tNO\tNO\ten\n2\tv2\ta-en\tNO\tNO\ten\n' 'publish-%ITEM%.mp4' || return 1
    unset SAF_SCENARIO_PUBLISH_FAIL_AFTER
    assert_contains "$SCENARIO_OUTPUT" 'could not be moved' || return 1
    assert_contains "$SCENARIO_FILES" 'publish-1.mp4' || return 1
    assert_contains "$SCENARIO_TEMP_FILES" 'publish-2.mp4'
}

test_audio_only_multitrack_conversion_and_metadata() {
    run_scenario $'PROFILE=QUALITY\nDOWNLOAD_ALL_AUDIO_TRACKS=YES\nSTORE_OPUS_IN_MP4=YES' \
        $'https://example.test/quality-audio\n2\n\n' chrome \
        $'0\tAUTO\topus-en+aac-uz\tNO\tYES\ten+uz\n' 'quality-audio.mp4' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[VideoRemuxer+ffmpeg_o:-vn -c:a libopus' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" '-metadata:s:a:0 language=eng' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" '-metadata:s:a:1 handler_name=Uzbek' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--embed-chapters]' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[--embed-metadata]' || return 1

    run_scenario $'PROFILE=MODERN\nDOWNLOAD_ALL_AUDIO_TRACKS=YES' \
        $'https://example.test/modern-audio\n2\n\n' chrome \
        $'0\tAUTO\taac-en+aac-ru\tNO\tNO\ten+ru\n' 'modern-audio.m4a' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" 'ARG=[VideoConvertor+ffmpeg_o:-vn -metadata:s:a:0 language=eng' || return 1
    assert_contains "$SCENARIO_ARGUMENTS" '-metadata:s:a:1 handler_name=Russian'
}

test_dependency_maps() {
    local output

    output=$(SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 "$launcher" --internal-dependency-map) || return 1
    assert_contains "$output" 'PLATFORM=linux-x64' || return 1
    assert_contains "$output" 'yt-dlp_linux' || return 1
    assert_contains "$output" 'deno-x86_64-unknown-linux-gnu.zip' || return 1
    assert_contains "$output" 'ffmpeg-master-latest-linux64-gpl.tar.xz' || return 1

    output=$(SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=aarch64 "$launcher" --internal-dependency-map) || return 1
    assert_contains "$output" 'PLATFORM=linux-arm64' || return 1
    assert_contains "$output" 'yt-dlp_linux_aarch64' || return 1
    assert_contains "$output" 'deno-aarch64-unknown-linux-gnu.zip' || return 1
    assert_contains "$output" 'ffmpeg-master-latest-linuxarm64-gpl.tar.xz' || return 1

    output=$(SAF_TEST_UNAME_S=Darwin SAF_TEST_UNAME_M=x86_64 "$launcher" --internal-dependency-map) || return 1
    assert_contains "$output" 'PLATFORM=macos-x64' || return 1
    assert_contains "$output" 'yt-dlp_macos' || return 1
    assert_contains "$output" 'deno-x86_64-apple-darwin.zip' || return 1
    assert_contains "$output" 'ffmpeg-darwin-x64.gz' || return 1
    assert_contains "$output" 'ffprobe-darwin-x64.gz' || return 1

    output=$(SAF_TEST_UNAME_S=Darwin SAF_TEST_UNAME_M=arm64 "$launcher" --internal-dependency-map) || return 1
    assert_contains "$output" 'PLATFORM=macos-arm64' || return 1
    assert_contains "$output" 'yt-dlp_macos' || return 1
    assert_contains "$output" 'deno-aarch64-apple-darwin.zip' || return 1
    assert_contains "$output" 'ffmpeg-darwin-arm64.gz' || return 1
    assert_contains "$output" 'ffprobe-darwin-arm64.gz' || return 1
}

test_unsupported_platform() {
    local fixture output
    fixture=$(mktemp -d)
    cp "$launcher" "$fixture/SaF-YTDLP.sh" || return 1
    if output=$(cd "$fixture" && SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=i686 ./SaF-YTDLP.sh --internal-dependency-map 2>&1); then
        rm -rf "$fixture"
        printf 'Unsupported architecture succeeded.\n' >&2
        return 1
    fi
    if [[ -e $fixture/internal ]]; then
        rm -rf "$fixture"
        printf 'Unsupported architecture created runtime files.\n' >&2
        return 1
    fi
    rm -rf "$fixture"
    assert_contains "$output" 'supports Linux and macOS on x86_64 and ARM64'
}

test_config_validation() {
    local fixture output
    fixture=$(mktemp -d)
    cp "$launcher" "$fixture/SaF-YTDLP.sh" || return 1
    printf 'PROFILE=MODERN\nMAX_HEIGHT=invalid\nDEFAULT_MODE=video\nTRANSCODE_VP9_TO_AV1=YES\nALLOW_HARDWARE_TRANSCODING=YES\nSTORE_OPUS_IN_MP4=YES\nDOWNLOAD_ALL_AUDIO_TRACKS=YES\nCOOKIE_BROWSER=\n' > "$fixture/config.ini"
    if output=$(cd "$fixture" && SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 ./SaF-YTDLP.sh 2>&1); then
        rm -rf "$fixture"
        printf 'Invalid configuration succeeded.\n' >&2
        return 1
    fi
    if [[ -e $fixture/internal ]]; then
        rm -rf "$fixture"
        printf 'Invalid configuration created runtime files.\n' >&2
        return 1
    fi
    rm -rf "$fixture"
    assert_contains "$output" 'Invalid MAX_HEIGHT'
}

test_missing_and_invalid_cookie_config() {
    local fixture output
    fixture=$(mktemp -d)
    cp "$launcher" "$fixture/SaF-YTDLP.sh" || return 1
    if output=$(cd "$fixture" && SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_TEST_DOWNLOAD_FAILURE=YES ./SaF-YTDLP.sh </dev/null 2>&1); then
        rm -rf "$fixture"
        printf 'Missing Bash configuration succeeded.\n' >&2
        return 1
    fi
    [[ ! -e $fixture/internal && ! -e $fixture/config.ini ]] || { rm -rf "$fixture"; printf 'Missing config created runtime files.\n' >&2; return 1; }
    assert_contains "$output" 'config.ini was not found' || { rm -rf "$fixture"; return 1; }
    rm -rf "$fixture"

    fixture=$(mktemp -d)
    cp "$launcher" "$fixture/SaF-YTDLP.sh" || return 1
    printf 'PROFILE=MODERN\nMAX_HEIGHT=1080\nDEFAULT_MODE=video\nTRANSCODE_VP9_TO_AV1=YES\nALLOW_HARDWARE_TRANSCODING=YES\nSTORE_OPUS_IN_MP4=YES\nDOWNLOAD_ALL_AUDIO_TRACKS=YES\nCOOKIE_BROWSER=safari\n' > "$fixture/config.ini"
    if output=$(cd "$fixture" && SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_TEST_DOWNLOAD_FAILURE=YES ./SaF-YTDLP.sh </dev/null 2>&1); then
        rm -rf "$fixture"
        printf 'Invalid COOKIE_BROWSER succeeded.\n' >&2
        return 1
    fi
    [[ ! -e $fixture/internal ]] || { rm -rf "$fixture"; printf 'Invalid browser created runtime files.\n' >&2; return 1; }
    rm -rf "$fixture"
    assert_contains "$output" 'Invalid COOKIE_BROWSER'
}

test_existing_dependencies_and_failed_update() {
    local fixture before after output
    fixture=$(mktemp -d)
    mkdir -p "$fixture/internal/dependencies"
    cp "$launcher" "$fixture/SaF-YTDLP.sh" || return 1
    cp "$repo_root/config.ini" "$fixture/config.ini" || return 1
    cp "$repo_root/tests/FakeYtdlp.sh" "$fixture/internal/dependencies/yt-dlp"
    cp "$repo_root/tests/FakeYtdlp.sh" "$fixture/internal/dependencies/deno"
    cp "$repo_root/tests/FakeFfmpeg.sh" "$fixture/internal/dependencies/ffmpeg"
    cp "$repo_root/tests/FakeFfmpeg.sh" "$fixture/internal/dependencies/ffprobe"
    chmod +x "$fixture/SaF-YTDLP.sh" "$fixture/internal/dependencies/"*
    before=$(cksum "$fixture/internal/dependencies/yt-dlp")
    output=$(cd "$fixture" && SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_FAKE_UPDATE_EXIT=1 ./SaF-YTDLP.sh </dev/null 2>&1) || {
        rm -rf "$fixture"
        printf '%s\n' "$output" >&2
        return 1
    }
    after=$(cksum "$fixture/internal/dependencies/yt-dlp")
    [[ $before == "$after" ]] || { rm -rf "$fixture"; printf 'Failed update changed yt-dlp.\n' >&2; return 1; }
    [[ ! -e $fixture/internal/dependencies/yt-dlp.new ]] || { rm -rf "$fixture"; printf 'Failed update left yt-dlp.new.\n' >&2; return 1; }
    [[ -d $fixture/internal/temp && -d $fixture/Downloads ]] || { rm -rf "$fixture"; printf 'Runtime layout is incomplete.\n' >&2; return 1; }
    [[ -z $(find "$fixture/internal/temp" -mindepth 1 -print -quit) ]] || { rm -rf "$fixture"; printf 'Temp directory is not empty.\n' >&2; return 1; }
    rm -rf "$fixture"
    assert_contains "$output" 'update failed'
}

test_interrupted_initial_download() {
    local fixture output
    fixture=$(mktemp -d)
    cp "$launcher" "$fixture/SaF-YTDLP.sh" || return 1
    cp "$repo_root/config.ini" "$fixture/config.ini" || return 1
    if output=$(cd "$fixture" && SAF_TEST_UNAME_S=Linux SAF_TEST_UNAME_M=x86_64 SAF_TEST_DOWNLOAD_FAILURE=YES ./SaF-YTDLP.sh </dev/null 2>&1); then
        rm -rf "$fixture"
        printf 'Interrupted setup succeeded.\n' >&2
        return 1
    fi
    [[ -z $(find "$fixture/internal/dependencies" -type f -print -quit 2>/dev/null) ]] || { rm -rf "$fixture"; printf 'Interrupted setup installed a dependency.\n' >&2; return 1; }
    [[ -z $(find "$fixture/internal" -name '*.part' -print -quit 2>/dev/null) ]] || { rm -rf "$fixture"; printf 'Interrupted setup left a partial file.\n' >&2; return 1; }
    [[ -z $(find "$fixture/internal/temp" -mindepth 1 -print -quit 2>/dev/null) ]] || { rm -rf "$fixture"; printf 'Interrupted setup left temporary files.\n' >&2; return 1; }
    rm -rf "$fixture"
    assert_contains "$output" 'could not download yt-dlp'
}

run_test 'Unix dependency maps cover Linux and macOS x64 and ARM64' test_dependency_maps
run_test 'Unsupported Unix platforms stop before setup' test_unsupported_platform
run_test 'Invalid Bash configuration stops before setup' test_config_validation
run_test 'Missing or invalid Bash config stops before setup' test_missing_and_invalid_cookie_config
run_test 'Failed Bash update preserves the installed yt-dlp' test_existing_dependencies_and_failed_update
run_test 'Interrupted Bash setup leaves no partial installation' test_interrupted_initial_download
run_test 'Bash interaction covers video audio thumbnail and URL characters' test_interaction_and_modes
run_test 'Bash multitrack downloads use every selected language' test_multitrack_download_selection
run_test 'Deno selector keeps resolution first and applies codec and language rules' test_real_deno_format_selection
run_test 'Bash cookies use saved-first order and cookie-free fallback' test_cookie_order_and_fallback
run_test 'Bash repeated downloads receive collision suffixes' test_repeated_download_collision
run_test 'Bash failed and partial downloads continue safely' test_failed_and_partial_downloads_continue
run_test 'Bash profiles preserve Windows post-processing decisions' test_profile_postprocessing_parity
run_test 'Bash bitrate table keeps every coefficient and margin' test_bitrate_table_and_margins
run_test 'Bash hardware candidates use platform order and CPU fallback' test_hardware_candidates_and_cpu_fallback
run_test 'Bash multitrack processing writes language metadata' test_multitrack_processing_metadata
run_test 'Bash probing preserves paths failures and temp cleanup' test_probe_paths_failures_and_cleanup
run_test 'Real Deno parses Bash FFprobe media JSON' test_real_deno_media_inspection
run_test 'Bash publish failures preserve every unmoved media file' test_publish_failure_preserves_unmoved_media
run_test 'Bash audio-only multitrack matches conversion and metadata rules' test_audio_only_multitrack_conversion_and_metadata

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))

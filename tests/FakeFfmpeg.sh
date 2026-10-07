#!/usr/bin/env bash
set -u

program=${0##*/}

log_arguments() {
    [[ -n ${SAF_FFMPEG_LOG:-} ]] || return 0
    {
        printf 'CALL=[%s]\n' "$program"
        for argument in "$@"; do
            printf 'ARG=[%s]\n' "$argument"
        done
    } >> "$SAF_FFMPEG_LOG"
}

value_after() {
    local option=$1
    shift
    while (($# > 1)); do
        if [[ $1 == "$option" ]]; then
            printf '%s' "$2"
            return 0
        fi
        shift
    done
    return 1
}

has_argument() {
    local expected=$1 argument
    shift
    for argument in "$@"; do
        [[ $argument == "$expected" ]] && return 0
    done
    return 1
}

if [[ ${1:-} == -version || ${1:-} == --version ]]; then
    printf 'fake %s\n' "$program"
    exit 0
fi

log_arguments "$@"

if [[ $program == ffprobe ]]; then
    if has_argument packet=size "$@"; then
        printf '%s' "${SAF_FAKE_PACKET_SIZES:-}" | tr ',' '\n'
        exit "${SAF_FAKE_PACKET_EXIT:-0}"
    fi
    if [[ -n ${SAF_FAKE_PROBE_JSON:-} ]]; then
        printf '%s\n' "$SAF_FAKE_PROBE_JSON"
    else
        printf '{"streams":[{"codec_type":"video","codec_name":"%s","height":%s,"bit_rate":"%s","pix_fmt":"%s"}' \
            "${SAF_FAKE_VIDEO_CODEC:-h264}" "${SAF_FAKE_VIDEO_HEIGHT:-1080}" "${SAF_FAKE_VIDEO_BITRATE:-8000000}" "${SAF_FAKE_PIXEL_FORMAT:-yuv420p}"
        local_codecs=${SAF_FAKE_AUDIO_CODECS:-aac}
        old_ifs=$IFS
        IFS=,
        for codec in $local_codecs; do
            printf ',{"codec_type":"audio","codec_name":"%s"}' "$codec"
        done
        IFS=$old_ifs
        printf '],"format":{"duration":"%s"}}\n' "${SAF_FAKE_DURATION:-10}"
    fi
    exit "${SAF_FAKE_PROBE_EXIT:-0}"
fi

if has_argument -encoders "$@"; then
    printf 'libx264\nlibx265\nlibsvtav1\n%s\n' "${SAF_FAKE_ENCODERS:-}"
    exit 0
fi

encoder=$(value_after -c:v "$@" || true)
if has_argument lavfi "$@"; then
    case ",${SAF_FAKE_ENCODERS:-}," in
        *,"$encoder",*) exit 0 ;;
        *) exit 1 ;;
    esac
fi

if [[ -n ${SAF_FAKE_FAIL_INPUT_CONTAINS:-} ]]; then
    input=$(value_after -i "$@" || true)
    [[ $input == *"$SAF_FAKE_FAIL_INPUT_CONTAINS"* ]] && exit 1
fi
if [[ -n ${SAF_FAKE_FAIL_ENCODER:-} && $encoder == "$SAF_FAKE_FAIL_ENCODER" ]]; then
    exit "${SAF_FAKE_FAIL_ENCODER_EXIT:-1}"
fi

output=${!#}
case $output in
    /dev/null|NUL|null) exit 0 ;;
esac
mkdir -p "${output%/*}"
printf 'converted' > "$output"
exit 0

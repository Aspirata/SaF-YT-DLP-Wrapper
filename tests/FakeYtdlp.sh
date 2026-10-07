#!/usr/bin/env bash
set -u

program=${0##*/}

if [[ $program == deno && -n ${SAF_REAL_DENO:-} ]]; then
    exec "$SAF_REAL_DENO" "$@"
fi

read_exit_code() {
    local name=$1
    eval "printf '%s' \"\${$name:-0}\""
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

second_value_after() {
    local option=$1
    shift
    while (($# > 2)); do
        if [[ $1 == "$option" ]]; then
            printf '%s' "$3"
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

if [[ $program == deno ]]; then
    if [[ ${1:-} == --version ]]; then
        printf 'fake deno\n'
        exit 0
    fi
    if [[ ${1:-} == eval ]]; then
        case ${SAF_DENO_MODE:-selection} in
            probe)
                printf '%s\t%s\t%s\t%s\t%s\t%s' \
                    "${SAF_FAKE_VIDEO_CODEC:-h264}" "${SAF_FAKE_VIDEO_HEIGHT:-1080}" \
                    "${SAF_FAKE_VIDEO_BITRATE:-8000000}" "${SAF_FAKE_PIXEL_FORMAT:-yuv420p}" \
                    "${SAF_FAKE_DURATION:-10}" "${SAF_FAKE_AUDIO_CODECS:-aac}" > "${SAF_DENO_OUTPUT:?}"
                exit "$(read_exit_code SAF_FAKE_DENO_PROBE_EXIT)"
                ;;
            bitrate)
                printf '%s' "${SAF_FAKE_PACKET_BITRATE:-8000000}" > "${SAF_DENO_OUTPUT:?}"
                exit "$(read_exit_code SAF_FAKE_DENO_BITRATE_EXIT)"
                ;;
            *)
                printf '%b' "${SAF_FAKE_SELECTIONS:-}" > "${SAF_SELECTION_OUTPUT:?}"
                exit "$(read_exit_code SAF_FAKE_DENO_EXIT)"
                ;;
        esac
    fi
fi

if [[ ${1:-} == --update-to ]]; then
    exit "$(read_exit_code SAF_FAKE_UPDATE_EXIT)"
fi

if [[ ${1:-} == --version ]]; then
    printf 'fake-version\n'
    exit "$(read_exit_code SAF_FAKE_VERSION_EXIT)"
fi

if [[ -n ${SAF_ARGUMENT_LOG:-} ]]; then
    {
        printf 'CALL\n'
        for argument in "$@"; do
            printf 'ARG=[%s]\n' "$argument"
        done
    } >> "$SAF_ARGUMENT_LOG"
fi

if has_argument --simulate "$@"; then
    expected=${SAF_FAKE_COOKIE_SUCCESS:-NONE}
    actual=$(value_after --cookies-from-browser "$@" || true)
    [[ $expected != NONE && $actual == *"$expected"* ]]
    exit $?
fi

if has_argument --dump-single-json "$@"; then
    printf '%s' "${SAF_FAKE_METADATA_JSON:-{}}"
    exit 0
fi

actual_cookie=$(value_after --cookies-from-browser "$@" || true)
if [[ -n ${SAF_FAKE_DOWNLOAD_FAIL_COOKIE:-} && $actual_cookie == *"$SAF_FAKE_DOWNLOAD_FAIL_COOKIE"* ]]; then
    exit 1
fi

output_directory=$(value_after -P "$@" || true)
if [[ -n $output_directory ]]; then
    mkdir -p "$output_directory"
    if has_argument --skip-download "$@" && has_argument --write-thumbnail "$@"; then
        printf 'thumbnail' > "$output_directory/${SAF_FAKE_MEDIA_NAME:-thumbnail.webp}"
    elif [[ -n ${SAF_FAKE_MEDIA_NAME:-} ]]; then
        media_name=$SAF_FAKE_MEDIA_NAME
        playlist_item=$(value_after --playlist-items "$@" || true)
        media_name=${media_name//\%ITEM\%/${playlist_item:-0}}
        media_path=$output_directory/$media_name
        printf 'media' > "$media_path"
        print_file=$(second_value_after --print-to-file "$@" || true)
        if [[ -n $print_file ]]; then
            printf '%s\t%s\t%s\t%s\n' "$media_path" "${SAF_FAKE_VIDEO_CODEC:-h264}" "${SAF_FAKE_AUDIO_CODEC:-aac}" "${SAF_FAKE_AUDIO_LANGUAGES:-}" >> "$print_file"
        fi
    fi
fi

exit "$(read_exit_code SAF_FAKE_DOWNLOAD_EXIT)"

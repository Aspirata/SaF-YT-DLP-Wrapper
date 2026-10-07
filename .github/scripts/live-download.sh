#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd "$repository_root"

case $(uname -m) in
    x86_64|amd64) actual_architecture=x64 ;;
    aarch64|arm64) actual_architecture=arm64 ;;
    *) printf 'Unsupported runner architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac
if [[ $actual_architecture != "$SAF_EXPECTED_ARCH" ]]; then
    printf 'Expected %s runner, but the operating system reports %s.\n' "$SAF_EXPECTED_ARCH" "$actual_architecture" >&2
    exit 1
fi

printf 'Runner architecture: %s\n' "$actual_architecture"
printf '%s\n\n\n' "$SAF_SMOKE_URL" | bash ./SaF-YTDLP.sh

media_file=
media_count=0
while IFS= read -r -d '' candidate; do
    media_file=$candidate
    media_count=$((media_count + 1))
done < <(find Downloads -type f -print0)

if ((media_count != 1)); then
    printf 'Expected exactly one downloaded media file, found %d.\n' "$media_count" >&2
    exit 1
fi
if [[ ! -s $media_file ]]; then
    printf 'Downloaded file is empty: %s\n' "$media_file" >&2
    exit 1
fi
if find internal/temp ! -path internal/temp -print -quit | grep -q .; then
    printf 'Temporary data remains after the download.\n' >&2
    find internal/temp ! -path internal/temp -print >&2
    exit 1
fi

ffprobe=$repository_root/internal/dependencies/ffprobe
if [[ ! -x $ffprobe ]]; then
    printf 'The wrapper did not install an executable ffprobe.\n' >&2
    exit 1
fi

media_report=$("$ffprobe" -v error \
    -show_entries 'format=filename,format_name,format_long_name,duration,size,bit_rate:format_tags=title,artist' \
    -show_entries 'stream=index,codec_type,codec_name,codec_long_name,profile,width,height,pix_fmt,r_frame_rate,avg_frame_rate,bit_rate,sample_rate,channels,channel_layout:stream_tags=language,title,handler_name' \
    -of 'default=noprint_wrappers=0' \
    "$media_file")

size_bytes=$(wc -c < "$media_file" | tr -d '[:space:]')
size_mib=$(awk -v bytes="$size_bytes" 'BEGIN { printf "%.2f", bytes / 1048576 }')
printf 'Downloaded file: %s (%s MiB)\n' "$media_file" "$size_mib"
printf 'Media report:\n%s\n' "$media_report"

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    {
        printf '## Downloaded video — %s\n\n' "$SAF_EXPECTED_ARCH"
        printf -- '- File: `%s`\n' "${media_file##*/}"
        printf -- '- Size: %s MiB\n\n' "$size_mib"
        printf '```text\n%s\n```\n' "$media_report"
    } >> "$GITHUB_STEP_SUMMARY"
fi

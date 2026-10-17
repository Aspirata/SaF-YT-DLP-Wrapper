#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
launcher=$repository_root/SaF-YTDLP.sh

dependency_map() {
    SAF_TEST_UNAME_S=$1 SAF_TEST_UNAME_M=$2 bash "$launcher" --internal-dependency-map
}

assert_contains() {
    local text=$1 expected=$2 message=$3
    if [[ $text != *"$expected"* ]]; then
        printf '%s\nExpected: %s\nActual:\n%s\n' "$message" "$expected" "$text" >&2
        return 1
    fi
}

linux_x64=$(dependency_map Linux x86_64)
linux_arm64=$(dependency_map Linux aarch64)
macos_x64=$(dependency_map Darwin x86_64)
macos_arm64=$(dependency_map Darwin arm64)

assert_contains "$linux_x64" \
    'FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl-shared.tar.xz' \
    'Linux x64 does not select the BtbN GPL Shared FFmpeg package.'
assert_contains "$linux_arm64" \
    'FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl-shared.tar.xz' \
    'Linux ARM64 does not select the BtbN GPL Shared FFmpeg package.'
assert_contains "$linux_x64" '/ffmpeg-shared/bin/ffmpeg' 'Linux x64 does not run FFmpeg from the Shared runtime directory.'
assert_contains "$linux_arm64" '/ffmpeg-shared/bin/ffmpeg' 'Linux ARM64 does not run FFmpeg from the Shared runtime directory.'

assert_contains "$macos_x64" 'FFMPEG_URL=https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-x64.gz' 'macOS x64 FFmpeg source changed unexpectedly.'
assert_contains "$macos_arm64" 'FFMPEG_URL=https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-arm64.gz' 'macOS ARM64 FFmpeg source changed unexpectedly.'
assert_contains "$macos_x64" '/dependencies/ffmpeg' 'macOS x64 does not use the standalone FFmpeg binary.'
assert_contains "$macos_arm64" '/dependencies/ffmpeg' 'macOS ARM64 does not use the standalone FFmpeg binary.'

printf 'PASS: Linux selects GPL Shared FFmpeg and macOS keeps its standalone binaries.\n'

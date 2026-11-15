#!/bin/bash
# Reproducible build of the XRUN-fixed audio.primary.x86.so for the systems
# flashed by ../xiaomi-latte-flash_tools.
#
# Upstream android-generic/platform_hardware_libaudio opens the PCM with
# PCM_NORESTART and never recovers from -EPIPE; its SHORT-mode write pacing
# also leaves only ~22ms of headroom, less than the observed AudioFlinger
# write jitter (avg 29ms / max 45ms), so playback underruns structurally.
# patches/0001 adds recovery, 0002 raises the buffer headroom (verified on
# hardware: 20 min of playback, zero XRUNs).
#
# Usage: ./build.sh <profile>
#   Profiles: v14 v15 v16 v17 (BlissOS) | sk5 (ProjectSakura) | los21 (LineageOS)
#   v18 is reserved (A15; ABI not recon'd yet).
#
# Requires: Android NDK (NDK env or /opt/android-ndk), git.
# Link libs come from the target system images; if deps/<abi>/ is missing,
# they are extracted automatically from a local system.img (SYSTEM_IMG_32 /
# SYSTEM_IMG_64) -- see README.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"

NDK=${NDK:-/opt/android-ndk}
REPO=https://github.com/android-generic/platform_hardware_libaudio

# profile: branch  pinned-commit  abi  api  (pinned 2026-11-15)
PROFILE_ATTRS() {
    case "$1" in
        v14|sk5) echo "11-x86 a5a0778c88dfeb6a928cf01a46ea881fda20c6e8 i686 30" ;;
        v15)     echo "12l-x86 a886ef675fbc07c7e96c913ccf1fb23fac3357d7 i686 32" ;;
        v16)     echo "13-x86 3f1620d0d25804dd2cede1bb4e83af356fa38f6a i686 33" ;;
        v17)     echo "14-x86 889952b9fb3330d54739f9a974b14dfec0f0893b i686 33" ;;
        los21)   echo "14-x86 889952b9fb3330d54739f9a974b14dfec0f0893b x86_64 33" ;;
        *) return 1 ;;
    esac
}

PROFILE=${1:-}
[ -n "$PROFILE" ] || { echo "usage: $0 <profile: v14 v15 v16 v17 sk5 los21>" >&2; exit 1; }
ATTRS=$(PROFILE_ATTRS "$PROFILE") || { echo "unknown profile: $PROFILE" >&2; exit 1; }
read -r BRANCH SHA ABI API <<< "$ATTRS"

TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
CC=$TC/bin/${ABI}-linux-android${API}-clang
STRIP=$TC/bin/llvm-strip
[ -x "$CC" ] || { echo "NDK compiler not found: $CC" >&2; exit 1; }

echo "==> 1. Source: $BRANCH @ $SHA"
SRC=$HERE/source/$BRANCH
if [ ! -d "$SRC/.git" ] || [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$SHA" ]; then
    rm -rf "$SRC"; mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$REPO"
    # HTTP/1.1: HTTP/2 to github occasionally stalls mid-transfer here.
    git -C "$SRC" -c http.version=HTTP/1.1 fetch -q --depth=1 origin "refs/heads/$BRANCH"
    TIP=$(git -C "$SRC" rev-parse FETCH_HEAD)
    if [ "$TIP" != "$SHA" ]; then
        echo "branch $BRANCH moved: pinned $SHA, tip $TIP" >&2
        echo "verify the delta, then update the pin in build.sh" >&2
        exit 1
    fi
    git -C "$SRC" checkout -q FETCH_HEAD
fi
if ! grep -q 'out_write underrun: %d, recovering' "$SRC/hal/audio_hw.c"; then
    for p in "$HERE"/patches/*.patch; do
        echo "    applying $(basename "$p")"
        git -C "$SRC" apply "$p"
    done
fi

echo "==> 2. Link deps ($ABI)"
DEPS=$HERE/deps/$ABI
mkdir -p "$DEPS"
for f in libtinyalsa libcutils libaudioutils libexpat; do
    [ -f "$DEPS/$f.so" ] || {
        case "$ABI" in
            i686)   IMG=${SYSTEM_IMG_32:-}; P=/lib ;;           # Bliss/Sakura layout
            x86_64) IMG=${SYSTEM_IMG_64:-}; P=/vendor/lib64 ;;  # LineageOS layout
        esac
        [ -n "$IMG" ] && [ -f "$IMG" ] || {
            echo "deps missing: set SYSTEM_IMG_32 (Bliss/Sakura system.img) or SYSTEM_IMG_64 (LineageOS system.img)" >&2
            exit 1
        }
        debugfs -R "dump $P/$f.so $DEPS/$f.so" "$IMG" 2>/dev/null \
            || { echo "dump $P/$f.so from $IMG failed" >&2; exit 1; }
    }
done

echo "==> 3. Build (API $API)"
mkdir -p "$HERE/out/$PROFILE"
$CC -shared -fPIC -O2 -std=gnu11 \
    -I"$HERE/include" -I"$HERE/include/expat" \
    -Wl,-soname,audio.primary.x86.so \
    -L"$DEPS" -ltinyalsa -lcutils -laudioutils -lexpat -llog \
    "$SRC/hal/audio_hw.c" "$SRC/hal/audio_route.c" \
    -o "$HERE/out/$PROFILE/audio.primary.x86.so"
$STRIP "$HERE/out/$PROFILE/audio.primary.x86.so"

echo "==> 4. Verify"
SO=$HERE/out/$PROFILE/audio.primary.x86.so
grep -q ' HMI' <(readelf -Ws "$SO") || { echo "HMI export missing" >&2; exit 1; }
grep -q 'recovering' <(strings "$SO") || { echo "patched code missing" >&2; exit 1; }
echo "OK[$PROFILE $BRANCH@${SHA:0:9} $ABI API$API]: $(stat -c %s "$SO") bytes -> $SO"

#!/bin/bash
# Deploy a fixed HAL to an Android-x86 device over adb without touching the
# read-only system image: bind-mount the pushed .so over /system/lib{,64}/hw.
# Rebooting the device reverts it (the flash_tools build installs it for real).
#
# Usage: ADB_DEV=host:port ./deploy.sh <profile>   (e.g. v14)
#
# Pitfalls baked into the flow below:
# - Only android.hardware.audio.service is killed. Killing audioserver too
#   makes AudioPolicyManager race back up and the primary output can land on
#   audio.primary.default.so (r_submix virtual device) -- silent playback.
# - The service keeps the old bind mount mmapped, so kill it *before*
#   umount; and push to a fresh file name so the old and new mounts do not
#   alias the same inode.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PROFILE=${1:?usage: ADB_DEV=host:port ./deploy.sh <profile>}
SO=$HERE/out/$PROFILE/audio.primary.x86.so
ADB_DEV=${ADB_DEV:?set ADB_DEV to the adb device (e.g. 192.168.0.123:5555)}
[ -f "$SO" ] || { echo "build first: ./build.sh $PROFILE" >&2; exit 1; }

adb_() { adb -s "$ADB_DEV" "$@"; }

case "$PROFILE" in
    los21) HAL_PATH=/system/vendor/lib64/hw/audio.primary.x86.so ;;
    *)     HAL_PATH=/system/lib/hw/audio.primary.x86.so ;;
esac

echo "==> 1. Push"
DEV_SO=/data/local/tmp/audio-hal/$PROFILE.so
adb_ shell "mkdir -p /data/local/tmp/audio-hal" >/dev/null
adb_ push "$SO" "$DEV_SO" >/dev/null
adb_ shell "su -c 'chown root:root $DEV_SO; chmod 644 $DEV_SO'"

echo "==> 2. Swap bind mount (service stopped first)"
cat > "$HERE/.deploy-device.sh" <<DEVICE
set -e
killall android.hardware.audio.service 2>/dev/null || true
sleep 1
umount "$HAL_PATH" 2>/dev/null || true
mount -o bind "$DEV_SO" "$HAL_PATH"
md5sum "$HAL_PATH"
DEVICE
adb_ push "$HERE/.deploy-device.sh" /data/local/tmp/audio-hal/device.sh >/dev/null
adb_ shell "su -c 'sh /data/local/tmp/audio-hal/device.sh'"
rm -f "$HERE/.deploy-device.sh"

echo "==> 3. Wait for the service and verify"
sleep 5
PID=\$(adb_ shell pidof android.hardware.audio.service | tr -d '\r')
[ -n "\$PID" ] || { echo "service did not restart" >&2; exit 1; }
adb_ shell "su -c 'grep -c audio.primary.x86.so /proc/\$PID/maps'" | tr -d '\r' \
    | grep -qv '^0$' && echo "HAL loaded by pid \$PID"
adb_ shell "md5sum $DEV_SO" | tr -d '\r'
echo
echo "Now play audio and watch: adb -s $ADB_DEV logcat -s audio_hw_primary"
echo "(silence = no XRUNs; recovery lines should be rare or absent)"

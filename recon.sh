#!/bin/bash
# 从每个 ISO 提取 audio HAL 并输出：路径/位数/是否 android-generic libaudio 同源
# 用法: recon.sh <tag> <iso-path>
set -u
TAG=$1; ISO=$2
D=/home/qs315490/mipad2/tmp/hal-recon/$TAG
mkdir -p "$D"

echo "===== $TAG ====="
# 1. 从 ISO 提取 system.sfs / system.efs
xorriso -osirrox on -indev "$ISO" -extract /system.sfs "$D/system.sfs" >/dev/null 2>&1
xorriso -osirrox on -indev "$ISO" -extract /system.efs "$D/system.efs" >/dev/null 2>&1

# 2. 解出 system.img
if [ -s "$D/system.sfs" ]; then
    unsquashfs -d "$D/sfs-root" "$D/system.sfs" >/dev/null 2>&1
elif [ -s "$D/system.efs" ]; then
    fsck.erofs --extract="$D/sfs-root/" "$D/system.efs" >/dev/null 2>&1
fi
IMG=$(find "$D/sfs-root" -maxdepth 1 -name 'system.img' 2>/dev/null | head -1)
[ -z "$IMG" ] && { echo "no system.img found"; ls "$D/sfs-root" 2>/dev/null | head; exit 1; }

# 3. 找 HAL（lib/hw + lib64/hw）
for lib in lib lib64; do
    echo "--- /$lib/hw ---"
    debugfs -R "ls -l /$lib/hw" "$IMG" 2>/dev/null | grep -iE 'audio.primary|r_submix|usb' || echo "(none)"
done

# 4. dump 所有 audio.primary 并鉴定
i=0
for lib in lib lib64; do
    for f in $(debugfs -R "ls /$lib/hw" "$IMG" 2>/dev/null | tr ' ' '\n' | grep -E '^audio\.primary'); do
        out="$D/hal-$lib-$f"
        debugfs -R "dump /$lib/hw/$f $out" "$IMG" 2>/dev/null
        echo "=== $lib/hw/$f ==="
        file "$out" | cut -d, -f1-2
        strings "$out" | grep -q 'chose pcmC%dD%d%c' && echo "SAME-SOURCE: android-generic libaudio (select_card log present)" || echo "different HAL or stripped differently"
        strings "$out" | grep -oE 'pcm_[a-z_]+' | sort -u | tr '\n' ' '; echo
        i=$((i+1))
    done
done
[ $i -eq 0 ] && echo "!! no audio.primary.* found"
echo

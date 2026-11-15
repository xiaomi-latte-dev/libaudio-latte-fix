# audio.primary.x86 XRUN fix (reproducible build)

Fixed builds of the Android-x86 primary audio HAL for the systems flashed by
`../xiaomi-latte-flash_tools`.

## The bug (verified on hardware, 2026-11-15)

Upstream `android-generic/platform_hardware_libaudio`:

1. opens the PCM with `PCM_NORESTART` and, on underrun (`-EPIPE`), only logs
   and returns the error -- no recovery. tinyalsa in the image does retry on
   the *next* write, but the stream then carries a single ~21ms batch, drains,
   and underruns again: a self-sustaining 50ms -EPIPE storm until standby.
2. paces writes to a SHORT-mode threshold of ~22ms of buffered audio, less
   than the measured AudioFlinger write jitter (avg 29ms, max 45ms), so the
   first underrun is structurally guaranteed on this hardware (CHT).

Symptom: after ~20 minutes of Jellyfin playback audio dies with
`StreamHAL: Error from HAL stream in function write: Broken pipe`
(`-61`) until playback is stopped for a while.

## Patches

- `patches/0001` -- recover in `out_write`: `pcm_prepare` + rewrite, fall
  back to a full PCM reopen; drop the current chunk (~11ms) if the buffer
  was reallocated.
- `patches/0002` -- raise headroom: `start_threshold` at 7 periods (~75ms)
  and force the LONG write threshold (~88ms) so jitter spikes are absorbed.
  With this the HAL stops sleep-pacing and blocks in `pcm_write` instead,
  which anchors the AF write cadence to the hardware drain rate (measured
  jitter dropped from ave 28.6ms to 0.00007ms).

## Layout

```
patches/    0001 + 0002 against hal/audio_hw.c of each branch
include/    AOSP android-11.0.0_r48 headers + cutils/log.h shim +
            stub system/graphics*.h (audio HAL 2.0 C ABI is version-stable,
            headers work for all branches)
source/     fetched by build.sh at the pinned commit (gitignored)
deps/       link libs extracted from target system images (gitignored)
out/        build output per profile (gitignored)
build.sh    ./build.sh <profile>
deploy.sh   ADB_DEV=host:port ./deploy.sh <profile>
recon.sh    fingerprint the stock HAL inside an ISO (path/ABI/symbols)
```

## Profiles

| profile | system | branch | ABI | API | pinned commit |
|---|---|---|---|---|---|
| v14 | BlissOS 14 (A11) | 11-x86 | i686 | 30 | a5a0778c |
| sk5 | ProjectSakura (A11) | 11-x86 | i686 | 30 | a5a0778c |
| v15 | BlissOS 15 (A12L) | 12l-x86 | i686 | 32 | a886ef67 |
| v16 | BlissOS 16 (A13) | 13-x86 | i686 | 33 | 3f1620d0 |
| v17 | BlissOS 17.2 (A14) | 14-x86 | i686 | 33 | 889952b9 |
| los21 | LineageOS 21 (A14) | 14-x86 | x86_64 | 33 | 889952b9 |
| v18 | reserved (A15, ABI not recon'd) | | | | |

sk5 note: the stock Sakura binary is the 2021 shape of the HAL (no runtime
card selection); the rebuild is based on 11-x86 HEAD and is slightly newer
than stock -- watch for surprises when testing on that image.

## Build

```
./build.sh v14
# first run on a new clone, provide the link libs:
SYSTEM_IMG_32=../xiaomi-latte-flash_tools/build/system_uncomp_v14/system.img ./build.sh v14
SYSTEM_IMG_64=<los21 system.img> ./build.sh los21
```

`deps/i686/` is extracted from `/lib` of a Bliss/Sakura image, `deps/x86_64/`
from `/vendor/lib64` of the LineageOS image (debugfs, read-only).

## Deploy (test on device, reverts on reboot)

```
ADB_DEV=192.168.0.123:5555 ./deploy.sh v14
```

Bind-mounts the .so over the system copy and restarts only
`android.hardware.audio.service` (killing audioserver too can park the
primary output on r_submix -- silent; see deploy.sh comments).

## Ship

```
cp out/<profile>/audio.primary.x86.so \
   ../xiaomi-latte-flash_tools/device_files/audio-hal/<profile>.so
```

flash_tools installs it into the system image per-VER (`make VER=<profile>`).

## Hardware verification log (v14)

- v1 (0001 only): storm persisted, one `recovering` line per 50ms cycle;
  capture showed XRUN<->RUNNING oscillation with hw_ptr frozen at 1056.
- v2 (0001+0002): 20 min playback, 0 XRUNs, 56932 writes, jitter ave
  0.00007ms, a 29ms scheduling spike absorbed by the 77ms headroom,
  `avail_max` 3712 (vs ~1024 on v1).

/* Minimal shim of AOSP cutils/log.h for NDK standalone build.
 * Provides the ALOGx macros audio_hw.c / audio_route.c use.
 * Also pulls POSIX headers that platform bionic headers normally drag in. */
#pragma once
#include <unistd.h>
#include <sys/ioctl.h>
#include <android/log.h>

#ifndef LOG_TAG
#define LOG_TAG "audio_hw_primary"
#endif

#ifndef LOG_NDEBUG
#define LOG_NDEBUG 0
#endif

#ifndef ALOGV
#if LOG_NDEBUG
#define ALOGV(...) ((void)0)
#else
#define ALOGV(...) ((void)__android_log_print(ANDROID_LOG_VERBOSE, LOG_TAG, __VA_ARGS__))
#endif
#endif
#ifndef ALOGD
#define ALOGD(...) ((void)__android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__))
#endif
#ifndef ALOGI
#define ALOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__))
#endif
#ifndef ALOGW
#define ALOGW(...) ((void)__android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__))
#endif
#ifndef ALOGE
#define ALOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__))
#endif
#ifndef ALOGI_IF
#define ALOGI_IF(cond, ...) \
    ((cond) ? ((void)__android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)) : (void)0)
#endif

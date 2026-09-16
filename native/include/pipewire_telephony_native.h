#pragma once

#include <stdint.h>

#if _WIN32
#define PIPEWIRE_TELEPHONY_EXPORT __declspec(dllexport)
#else
#define PIPEWIRE_TELEPHONY_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

PIPEWIRE_TELEPHONY_EXPORT int sum(int a, int b);

PIPEWIRE_TELEPHONY_EXPORT int sum_long_running(int a, int b);

#ifdef __cplusplus
}
#endif

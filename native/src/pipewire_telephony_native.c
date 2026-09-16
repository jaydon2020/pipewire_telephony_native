#include "pipewire_telephony_native.h"

#if _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

int sum(int a, int b) { return a + b; }

int sum_long_running(int a, int b) {
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}

/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdint.h>
#include <stdio.h>

int pwt_loader_fixture(void) { return 0; }

#ifdef PWT_LOADER_MARKER
__attribute__((constructor)) static void marker(void) {
  puts("AUDIT_UNTRUSTED_LIBRARY_LOADED");
  fflush(stdout);
}

uint32_t pwt_abi_version(void) { return 1; }
#endif

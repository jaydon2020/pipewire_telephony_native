/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define PWT_EXPORT __declspec(dllexport)
#else
#define PWT_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t pwt_status;

#define PWT_STATUS_OK 0
#define PWT_STATUS_INVALID_ARGUMENT 1
#define PWT_STATUS_INVALID_HANDLE 2
#define PWT_STATUS_INVALID_STATE 3
#define PWT_STATUS_QUEUE_FULL 4
#define PWT_STATUS_PROTOCOL_ERROR 5
#define PWT_STATUS_INTERNAL_ERROR 6

#define PWT_BUS_SYSTEM 0
#define PWT_BUS_SESSION 1
#define PWT_BUS_AUTO 2

PWT_EXPORT uint32_t pwt_abi_version(void);
/* Absolute loader path borrowed for the native asset's lifetime. */
PWT_EXPORT const char *pwt_library_path(void);
PWT_EXPORT pwt_status pwt_initialize_dart_api_dl(void *data);

PWT_EXPORT void *pwt_client_create(int32_t bus, const uint8_t *test_bus_address,
                                   uint64_t test_bus_address_length,
                                   int64_t event_port);
PWT_EXPORT pwt_status pwt_client_start(void *handle);
PWT_EXPORT pwt_status pwt_client_submit(void *handle, const uint8_t *bytes,
                                        uint64_t length, int64_t result_port);
PWT_EXPORT pwt_status pwt_client_stop(void *handle);
PWT_EXPORT void pwt_client_destroy(void *handle);

PWT_EXPORT void pwt_free(void *buffer);

#ifdef __cplusplus
}
#endif

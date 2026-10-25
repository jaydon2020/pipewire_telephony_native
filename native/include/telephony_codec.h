/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "telephony_types.h"

namespace pwt {

std::optional<Request> decode_request(std::string_view json,
                                      std::string &error);
std::string encode_reply(const Reply &reply);
std::string encode_event(const Event &event);

} // namespace pwt

/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include "telephony_codec.h"

#include <algorithm>
#include <array>

#include <glaze/json/read.hpp>
#include <glaze/json/write.hpp>

namespace pwt {
namespace {

constexpr std::array<std::string_view, 17> kOperations{
    "refreshGateway",   "refreshCall",
    "refreshTransport", "dial",
    "sendTones",        "answer",
    "hangup",           "hangupAll",
    "setSpeakerVolume", "setMicrophoneVolume",
    "activate",         "setRejectSco",
    "swapCalls",        "releaseAndAnswer",
    "releaseAndSwap",   "holdAndAnswer",
    "createMultiparty",
};

constexpr auto kReadOptions = glz::opts{
    .error_on_unknown_keys = false,
    .error_on_missing_keys = true,
};

bool valid_operation(std::string_view operation) {
  return std::ranges::find(kOperations, operation) != kOperations.end();
}

bool valid_text(std::string_view value, std::string_view allowed) {
  return std::ranges::all_of(value,
                             [allowed](char c) { return allowed.contains(c); });
}

template <typename T> std::string encode(const T &value) {
  auto json = glz::write_json(value).value_or("");
  if (json.size() > kMaxMessageBytes) {
    return {};
  }
  return json;
}

} // namespace

std::optional<Request> decode_request(std::string_view json,
                                      std::string &error) {
  error.clear();
  if (json.size() > kMaxMessageBytes) {
    error = "message exceeds 1 MiB";
    return std::nullopt;
  }

  Request request;
  // A mutable Glaze buffer is padded during parsing, which keeps malformed
  // non-null-terminated FFI input inside its allocation.
  std::string padded{json};
  if (const auto result = glz::read<kReadOptions>(request, padded); result) {
    error = glz::format_error(result, padded);
    return std::nullopt;
  }
  if (request.version != kProtocolVersion) {
    error = "unsupported protocol version";
  } else if (request.requestId == 0 || request.target.clientGeneration == 0 ||
             request.target.objectIncarnation == 0) {
    error = "request identity values must be non-zero";
  } else if (request.target.path.empty() ||
             request.target.path.front() != '/' ||
             request.target.interface.empty()) {
    error = "invalid target";
  } else if (!valid_operation(request.operation)) {
    error = "unknown operation";
  } else if (request.operation == "dial" &&
             (!request.arguments.text || request.arguments.text->empty() ||
              request.arguments.text->size() > 80 ||
              !valid_text(*request.arguments.text, "0123456789+*#,ABCD"))) {
    error = "invalid dial string";
  } else if (request.operation == "sendTones" &&
             (!request.arguments.text ||
              !valid_text(*request.arguments.text, "0123456789*#ABCD"))) {
    error = "invalid DTMF string";
  } else if ((request.operation == "setSpeakerVolume" ||
              request.operation == "setMicrophoneVolume") &&
             (!request.arguments.volume || *request.arguments.volume > 15)) {
    error = "volume must be between 0 and 15";
  } else {
    return request;
  }
  return std::nullopt;
}

std::string encode_reply(const Reply &reply) { return encode(reply); }

std::string encode_event(const Event &event) { return encode(event); }

} // namespace pwt

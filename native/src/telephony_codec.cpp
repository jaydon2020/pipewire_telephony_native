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

bool valid_operation(std::string_view operation) {
  return std::ranges::find(kOperations, operation) != kOperations.end();
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
  if (const auto result = glz::read_json(request, json); result) {
    error = glz::format_error(result, json);
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
  } else {
    return request;
  }
  return std::nullopt;
}

std::string encode_reply(const Reply &reply) { return encode(reply); }

std::string encode_event(const Event &event) { return encode(event); }

} // namespace pwt

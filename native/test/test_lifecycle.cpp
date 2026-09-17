#include "command_queue.h"
#include "pipewire_telephony_native.h"

#include <chrono>
#include <cstdint>
#include <future>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition) {
  if (!condition) {
    throw std::runtime_error("lifecycle assertion failed");
  }
}

constexpr auto kRequest =
    R"({"version":1,"requestId":42,"operation":"dial","target":{"clientGeneration":7,"objectIncarnation":3,"path":"/org/pipewire/Telephony/ag1","interface":"org.pipewire.Telephony.AudioGateway1"},"arguments":{"text":"+123#","volume":null,"value":null}})";

} // namespace

int main() {
  require(pwt_abi_version() == 1);
  require(pwt_initialize_dart_api_dl(nullptr) == PWT_STATUS_INVALID_ARGUMENT);

  auto *const null_handle = static_cast<void *>(nullptr);
  auto *const bogus_handle = reinterpret_cast<void *>(0xdeadbeef);
  require(pwt_client_start(null_handle) == PWT_STATUS_INVALID_HANDLE);
  require(pwt_client_stop(bogus_handle) == PWT_STATUS_INVALID_HANDLE);
  pwt_client_destroy(null_handle);
  pwt_client_destroy(bogus_handle);
  pwt_free(nullptr);

  pwt::CommandQueue queue;
  std::vector<uint8_t> source{1, 2, 3};
  require(queue.push({.bytes = source, .resultPort = 9}));
  source[0] = 99;
  const auto copied = queue.try_pop();
  require(copied.has_value());
  require(copied->bytes == std::vector<uint8_t>({1, 2, 3}));

  for (size_t index = 0; index < pwt::kMaxOutstandingRequests; ++index) {
    require(queue.push({.bytes = {static_cast<uint8_t>(index)},
                        .resultPort = static_cast<int64_t>(index)}));
  }
  require(!queue.push({.bytes = {65}, .resultPort = 65}));

  pwt::CommandQueue stop_queue;
  auto stopped = std::async(std::launch::async,
                            [&stop_queue] { stop_queue.wait_for_stop(); });
  require(stopped.wait_for(std::chrono::milliseconds(10)) ==
          std::future_status::timeout);
  stop_queue.request_stop();
  require(stopped.wait_for(std::chrono::seconds(1)) ==
          std::future_status::ready);
  require(!stop_queue.push({.bytes = {1}, .resultPort = 1}));

  require(pwt_client_create(99, nullptr, 0, 0) == nullptr);
  void *automatic = pwt_client_create(PWT_BUS_AUTO, nullptr, 0, 0);
  require(automatic != nullptr);
  pwt_client_destroy(automatic);
  void *handle = pwt_client_create(PWT_BUS_SESSION, nullptr, 0, 0);
  require(handle != nullptr);
  require(pwt_client_submit(handle, nullptr, 0, 0) ==
          PWT_STATUS_INVALID_ARGUMENT);

  const auto *bytes = reinterpret_cast<const uint8_t *>(kRequest);
  require(pwt_client_submit(handle, bytes, 1, 0) == PWT_STATUS_PROTOCOL_ERROR);
  require(pwt_client_start(handle) == PWT_STATUS_OK);
  require(pwt_client_start(handle) == PWT_STATUS_INVALID_STATE);
  require(pwt_client_stop(handle) == PWT_STATUS_OK);
  require(pwt_client_submit(handle, bytes,
                            std::char_traits<char>::length(kRequest),
                            66) == PWT_STATUS_INVALID_STATE);

  pwt_client_destroy(handle);
  require(pwt_client_start(handle) == PWT_STATUS_INVALID_HANDLE);
  pwt_client_destroy(handle);
}

#include "pipewire_telephony_native.h"

#include <cstdlib>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <dart_api_dl.h>

#include "client_context.h"
#include "telephony_codec.h"

namespace {

constexpr uint32_t kAbiVersion = 1;

struct ClientRegistry {
  std::mutex mutex;
  std::unordered_map<uintptr_t, std::shared_ptr<pwt::ClientContext>> clients;
  uintptr_t next_id{1};
};

ClientRegistry &registry() {
  static ClientRegistry value;
  return value;
}

std::mutex &dart_api_mutex() {
  static std::mutex value;
  return value;
}

bool &dart_api_initialized() {
  static bool value = false;
  return value;
}

// The ABI transports a monotonically allocated token in an opaque pointer.
// It is never dereferenced.
uintptr_t token_of(void *handle) { return reinterpret_cast<uintptr_t>(handle); }

void *handle_of(uintptr_t token) { return reinterpret_cast<void *>(token); }

std::shared_ptr<pwt::ClientContext> client_for(void *handle) {
  if (handle == nullptr)
    return {};
  auto &clients = registry();
  const std::lock_guard lock(clients.mutex);
  const auto found = clients.clients.find(token_of(handle));
  return found == clients.clients.end() ? nullptr : found->second;
}

} // namespace

extern "C" {

uint32_t pwt_abi_version() { return kAbiVersion; }

pwt_status pwt_initialize_dart_api_dl(void *data) {
  try {
    if (data == nullptr)
      return PWT_STATUS_INVALID_ARGUMENT;
    const std::lock_guard lock(dart_api_mutex());
    if (dart_api_initialized())
      return PWT_STATUS_OK;
    if (Dart_InitializeApiDL(data) != 0)
      return PWT_STATUS_INTERNAL_ERROR;
    dart_api_initialized() = true;
    return PWT_STATUS_OK;
  } catch (...) {
    return PWT_STATUS_INTERNAL_ERROR;
  }
}

void *pwt_client_create(int32_t bus, const uint8_t *test_bus_address,
                        uint64_t test_bus_address_length, int64_t event_port) {
  try {
    if (bus != PWT_BUS_SYSTEM && bus != PWT_BUS_SESSION)
      return nullptr;
    if ((test_bus_address == nullptr && test_bus_address_length != 0) ||
        test_bus_address_length > 4096) {
      return nullptr;
    }
    std::string address;
    if (test_bus_address_length != 0) {
      address.assign(reinterpret_cast<const char *>(test_bus_address),
                     test_bus_address_length);
      if (address.find('\0') != std::string::npos)
        return nullptr;
    }

    auto &clients = registry();
    const std::lock_guard lock(clients.mutex);
    if (clients.next_id == std::numeric_limits<uintptr_t>::max())
      return nullptr;
    const auto token = clients.next_id++;
    auto client = std::make_shared<pwt::ClientContext>(
        event_port, token, static_cast<pwt::BusType>(bus), std::move(address));
    clients.clients.emplace(token, std::move(client));
    return handle_of(token);
  } catch (...) {
    return nullptr;
  }
}

pwt_status pwt_client_start(void *handle) {
  try {
    const auto client = client_for(handle);
    return client ? client->start() : PWT_STATUS_INVALID_HANDLE;
  } catch (...) {
    return PWT_STATUS_INTERNAL_ERROR;
  }
}

pwt_status pwt_client_submit(void *handle, const uint8_t *bytes,
                             uint64_t length, int64_t result_port) {
  try {
    const auto client = client_for(handle);
    if (!client)
      return PWT_STATUS_INVALID_HANDLE;
    if (bytes == nullptr || length == 0 || length > pwt::kMaxMessageBytes) {
      return PWT_STATUS_INVALID_ARGUMENT;
    }

    std::vector<uint8_t> copy(bytes, bytes + length);
    std::string error;
    const std::string_view json{reinterpret_cast<const char *>(copy.data()),
                                copy.size()};
    if (!pwt::decode_request(json, error)) {
      return PWT_STATUS_PROTOCOL_ERROR;
    }
    return client->submit(std::move(copy), result_port);
  } catch (...) {
    return PWT_STATUS_INTERNAL_ERROR;
  }
}

pwt_status pwt_client_stop(void *handle) {
  try {
    const auto client = client_for(handle);
    return client ? client->stop() : PWT_STATUS_INVALID_HANDLE;
  } catch (...) {
    return PWT_STATUS_INTERNAL_ERROR;
  }
}

void pwt_client_destroy(void *handle) {
  try {
    std::shared_ptr<pwt::ClientContext> client;
    {
      auto &clients = registry();
      const std::lock_guard lock(clients.mutex);
      const auto found = clients.clients.find(token_of(handle));
      if (found == clients.clients.end())
        return;
      client = std::move(found->second);
      clients.clients.erase(found);
    }
    client->stop();
    client->join();
  } catch (...) {
  }
}

void pwt_free(void *buffer) {
  try {
    std::free(buffer);
  } catch (...) {
  }
}

} // extern "C"

/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

#include "command_queue.h"
#include "pipewire_telephony_native.h"
#include "telephony_types.h"

namespace pwt {

class GatewayRegistry;
struct DiscoverySnapshot;

enum class BusType : int32_t { system = 0, session = 1, automatic = 2 };

struct StartupResult {
  bool ready{};
  std::string errorName;
  std::string errorMessage;
};

class ClientContext {
public:
  ClientContext(int64_t event_port, uint64_t generation, BusType bus,
                std::string test_bus_address = {});
  ~ClientContext();

  ClientContext(const ClientContext &) = delete;
  ClientContext &operator=(const ClientContext &) = delete;

  pwt_status start();
  pwt_status submit(std::vector<uint8_t> bytes, int64_t result_port);
  pwt_status stop();
  void join();

  StartupResult wait_for_startup(std::chrono::milliseconds timeout);
  bool wait_for_shutdown(std::chrono::milliseconds timeout);

private:
  enum class State { created, running, stopping, stopped };

  struct PendingRequest {
    uint64_t requestId{};
    int64_t resultPort{};
    std::string operation;
    std::string path;
    uint64_t incarnation{};
    std::string gatewayPath;
    std::chrono::steady_clock::time_point deadline;
  };

  void run();
  void run_event_loop();
  void dispatch_commands();
  void dispatch_request(const Request &request, int64_t result_port);
  void complete_request(uint64_t request_id,
                        std::optional<Error> error = std::nullopt);
  void complete_refresh(uint64_t request_id,
                        const std::map<std::string, sdbus::Variant> &properties,
                        std::optional<sdbus::Error> error);
  void expire_requests();
  void fail_pending(const std::string &name, const std::string &message);
  void post_reply(uint64_t request_id, int64_t result_port,
                  std::optional<Error> error);
  void finish_startup(StartupResult result);
  void post_ready(DiscoverySnapshot snapshot);
  void post_gateway(const std::string &kind, const GatewayProperties &gateway);
  void post_call(const std::string &kind, const CallProperties &call);
  void post_transport(const std::string &kind,
                      const TransportProperties &transport);
  void post_unavailable(const std::string &name, const std::string &message);
  bool post_json(int64_t port, const std::string &json) const;
  std::string get_service_owner();

  const int64_t event_port_;
  const uint64_t generation_;
  const BusType bus_;
  const std::string test_bus_address_;
  std::mutex state_mutex_;
  std::condition_variable state_changed_;
  State state_{State::created};
  CommandQueue commands_;
  std::thread owner_thread_;
  std::unique_ptr<sdbus::IConnection> connection_;
  sdbus::Slot owner_subscription_;
  std::unique_ptr<GatewayRegistry> gateways_;
  std::string service_owner_;
  uint64_t sequence_{};
  std::unordered_map<uint64_t, PendingRequest> pending_;
  std::unordered_set<std::string> busy_gateways_;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>>
      operation_proxies_;
  std::mutex startup_mutex_;
  std::condition_variable startup_changed_;
  bool startup_finished_{};
  StartupResult startup_result_;
};

} // namespace pwt

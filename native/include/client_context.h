#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

#include "command_queue.h"
#include "pipewire_telephony_native.h"

namespace pwt {

enum class BusType : int32_t { system = 0, session = 1 };

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

  void run();
  void run_event_loop();
  void dispatch_commands();
  void finish_startup(StartupResult result);
  void post_ready();
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
  std::string service_owner_;
  uint64_t sequence_{};
  std::mutex startup_mutex_;
  std::condition_variable startup_changed_;
  bool startup_finished_{};
  StartupResult startup_result_;
};

} // namespace pwt

#pragma once

#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

#include "command_queue.h"
#include "pipewire_telephony_native.h"

namespace pwt {

class ClientContext {
public:
  explicit ClientContext(int64_t event_port) : event_port_(event_port) {}
  ~ClientContext();

  ClientContext(const ClientContext &) = delete;
  ClientContext &operator=(const ClientContext &) = delete;

  pwt_status start();
  pwt_status submit(std::vector<uint8_t> bytes, int64_t result_port);
  pwt_status stop();
  void join();

private:
  enum class State { created, running, stopping, stopped };

  const int64_t event_port_;
  std::mutex state_mutex_;
  State state_{State::created};
  CommandQueue commands_;
  std::thread owner_thread_;
};

} // namespace pwt

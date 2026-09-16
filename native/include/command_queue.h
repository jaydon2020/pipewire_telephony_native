#pragma once

#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <vector>

namespace pwt {

inline constexpr size_t kMaxOutstandingRequests = 64;

struct Command {
  std::vector<uint8_t> bytes;
  int64_t resultPort{};
};

class CommandQueue {
public:
  bool push(Command command);
  std::optional<Command> try_pop();
  void request_stop();
  void wait_for_stop();
  bool stopping() const;
  size_t size() const;

private:
  mutable std::mutex mutex_;
  std::condition_variable wakeup_;
  std::deque<Command> commands_;
  bool stopping_{};
};

} // namespace pwt

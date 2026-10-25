/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#pragma once

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
  CommandQueue();
  ~CommandQueue();

  CommandQueue(const CommandQueue &) = delete;
  CommandQueue &operator=(const CommandQueue &) = delete;

  bool push(Command command);
  std::optional<Command> try_pop();
  void request_stop();
  void wait_for_stop();
  void consume_wakeup();
  int fd() const { return wakeup_fd_; }
  bool stopping() const;
  size_t size() const;

private:
  mutable std::mutex mutex_;
  std::deque<Command> commands_;
  bool stopping_{};
  int wakeup_fd_{-1};
};

} // namespace pwt

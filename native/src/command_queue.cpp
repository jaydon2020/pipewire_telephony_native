/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include "command_queue.h"

#include <cerrno>
#include <cstdint>
#include <stdexcept>
#include <utility>

#include <poll.h>
#include <sys/eventfd.h>
#include <unistd.h>

namespace pwt {
namespace {

void signal(int fd) {
  const uint64_t value = 1;
  ssize_t result;
  do {
    result = write(fd, &value, sizeof(value));
  } while (result < 0 && errno == EINTR);
  if (result < 0 && errno != EAGAIN) {
    throw std::runtime_error("failed to signal command queue");
  }
}

} // namespace

CommandQueue::CommandQueue()
    : wakeup_fd_(eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK)) {
  if (wakeup_fd_ < 0) {
    throw std::runtime_error("failed to create command queue eventfd");
  }
}

CommandQueue::~CommandQueue() {
  if (wakeup_fd_ >= 0) {
    close(wakeup_fd_);
  }
}

bool CommandQueue::push(Command command) {
  {
    const std::lock_guard lock(mutex_);
    if (stopping_ || commands_.size() >= kMaxOutstandingRequests) {
      return false;
    }
    commands_.push_back(std::move(command));
  }
  signal(wakeup_fd_);
  return true;
}

std::optional<Command> CommandQueue::try_pop() {
  const std::lock_guard lock(mutex_);
  if (commands_.empty()) {
    return std::nullopt;
  }
  auto command = std::move(commands_.front());
  commands_.pop_front();
  return command;
}

void CommandQueue::request_stop() {
  {
    const std::lock_guard lock(mutex_);
    stopping_ = true;
  }
  signal(wakeup_fd_);
}

void CommandQueue::wait_for_stop() {
  while (!stopping()) {
    pollfd descriptor{.fd = wakeup_fd_, .events = POLLIN, .revents = 0};
    if (poll(&descriptor, 1, -1) < 0 && errno != EINTR) {
      throw std::runtime_error("failed to poll command queue");
    }
    consume_wakeup();
  }
}

void CommandQueue::consume_wakeup() {
  uint64_t value;
  while (true) {
    const auto result = read(wakeup_fd_, &value, sizeof(value));
    if (result > 0)
      continue;
    if (result < 0 && errno == EINTR)
      continue;
    if (result < 0 && errno == EAGAIN)
      return;
    throw std::runtime_error("failed to consume command queue wakeup");
  }
}

bool CommandQueue::stopping() const {
  const std::lock_guard lock(mutex_);
  return stopping_;
}

size_t CommandQueue::size() const {
  const std::lock_guard lock(mutex_);
  return commands_.size();
}

} // namespace pwt

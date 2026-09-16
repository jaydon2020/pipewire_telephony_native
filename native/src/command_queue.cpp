#include "command_queue.h"

#include <utility>

namespace pwt {

bool CommandQueue::push(Command command) {
  const std::lock_guard lock(mutex_);
  if (stopping_ || commands_.size() >= kMaxOutstandingRequests) {
    return false;
  }
  commands_.push_back(std::move(command));
  return true;
}

std::optional<Command> CommandQueue::try_pop() {
  const std::lock_guard lock(mutex_);
  if (commands_.empty())
    return std::nullopt;
  auto command = std::move(commands_.front());
  commands_.pop_front();
  return command;
}

void CommandQueue::request_stop() {
  {
    const std::lock_guard lock(mutex_);
    stopping_ = true;
  }
  wakeup_.notify_all();
}

void CommandQueue::wait_for_stop() {
  std::unique_lock lock(mutex_);
  wakeup_.wait(lock, [this] { return stopping_; });
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

#include "client_context.h"

#include <utility>

namespace pwt {

ClientContext::~ClientContext() {
  stop();
  join();
}

pwt_status ClientContext::start() {
  const std::lock_guard lock(state_mutex_);
  if (state_ != State::created) {
    return PWT_STATUS_INVALID_STATE;
  }

  try {
    owner_thread_ = std::thread([this] {
      commands_.wait_for_stop();
      const std::lock_guard state_lock(state_mutex_);
      state_ = State::stopped;
    });
    state_ = State::running;
    return PWT_STATUS_OK;
  } catch (...) {
    state_ = State::stopped;
    return PWT_STATUS_INTERNAL_ERROR;
  }
}

pwt_status ClientContext::submit(std::vector<uint8_t> bytes,
                                 int64_t result_port) {
  {
    const std::lock_guard lock(state_mutex_);
    if (state_ != State::running) {
      return PWT_STATUS_INVALID_STATE;
    }
  }
  if (!commands_.push({.bytes = std::move(bytes), .resultPort = result_port})) {
    return commands_.stopping() ? PWT_STATUS_INVALID_STATE
                                : PWT_STATUS_QUEUE_FULL;
  }
  return PWT_STATUS_OK;
}

pwt_status ClientContext::stop() {
  {
    const std::lock_guard lock(state_mutex_);
    if (state_ == State::stopped || state_ == State::stopping) {
      return PWT_STATUS_OK;
    }
    state_ = State::stopping;
  }
  commands_.request_stop();
  return PWT_STATUS_OK;
}

void ClientContext::join() {
  if (owner_thread_.joinable()) {
    owner_thread_.join();
  }
}

} // namespace pwt

#include "support/mock_telephony_service.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string>
#include <thread>

namespace {

std::atomic_bool running{true};

void stop(int) { running = false; }

} // namespace

int main() {
  const char *address = std::getenv("DBUS_SESSION_BUS_ADDRESS");
  if (address == nullptr) {
    return 2;
  }
  std::signal(SIGINT, stop);
  std::signal(SIGTERM, stop);
  pwt::test::MockTelephonyService service(std::string{address}, false);
  service.start();
  std::cout << "READY" << std::endl;
  while (running) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
}

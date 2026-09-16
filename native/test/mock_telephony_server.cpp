#include "support/mock_telephony_service.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string>
#include <thread>

#include <poll.h>
#include <unistd.h>

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
  pwt::test::MockTelephonyService service(std::string{address});
  service.start();
  std::cout << "READY" << std::endl;
  while (running) {
    pollfd input{.fd = STDIN_FILENO, .events = POLLIN, .revents = 0};
    if (poll(&input, 1, 10) <= 0 || (input.revents & POLLIN) == 0) {
      continue;
    }
    std::string command;
    if (!std::getline(std::cin, command)) {
      break;
    }
    if (command == "add") {
      service.add_gateway();
    } else if (command == "remove") {
      service.remove_gateway();
    } else if (command == "add-second") {
      service.add_second_gateway();
    } else if (command == "remove-second") {
      service.remove_second_gateway();
    } else if (command == "quit") {
      break;
    }
  }
}

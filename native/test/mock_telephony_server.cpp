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
    } else if (command == "add-call") {
      service.add_call();
    } else if (command == "remove-call") {
      service.remove_call();
    } else if (command == "add-transport") {
      service.add_transport();
    } else if (command == "remove-transport") {
      service.remove_transport();
    } else if (command == "change-properties") {
      service.change_gateway_state({.address = "AA:BB:CC:DD:EE:FF",
                                    .speakerVolume = 0,
                                    .microphoneVolume = 10},
                                   {"SpeakerVolume"});
      service.change_call_state({.lineIdentification = "+123",
                                 .incomingLine = "",
                                 .name = "Ada",
                                 .multiparty = false,
                                 .state = "future-ringing"},
                                {"IncomingLine", "Multiparty", "State"});
    } else if (command == "invalidate-properties") {
      service.change_gateway_state({.address = "AA:BB:CC:DD:EE:FF",
                                    .speakerVolume = 0,
                                    .microphoneVolume = 0},
                                   {}, {"MicrophoneVolume"});
      service.change_call_state({.lineIdentification = "+123",
                                 .incomingLine = "",
                                 .name = "Grace",
                                 .multiparty = false,
                                 .state = "future-ringing"},
                                {}, {"Name"});
    } else if (command == "disconnect-call") {
      service.change_call_state({.lineIdentification = "+123",
                                 .incomingLine = "",
                                 .name = "Ada",
                                 .multiparty = false,
                                 .state = "disconnected"},
                                {"State"});
    } else if (command == "prepare-refresh") {
      service.change_gateway_state(
          {.address = "", .speakerVolume = 0, .microphoneVolume = 0}, {});
      service.change_call_state({.lineIdentification = "",
                                 .incomingLine = "",
                                 .name = "",
                                 .multiparty = false,
                                 .state = "future-state"},
                                {});
      service.set_transport_state(
          {.state = "future-state", .codec = 255, .rejectSco = false});
    } else if (command == "delay-operations") {
      service.set_operation_delay(std::chrono::milliseconds{500});
    } else if (command == "clear-operation-delay") {
      service.set_operation_delay(std::chrono::milliseconds{0});
    } else if (command.starts_with("fail-refresh ")) {
      const auto name = command.substr(std::string{"fail-refresh "}.size());
      service.fail_next("GetGatewayProperties", name, "mock refresh failure");
    } else if (command == "fail-answer") {
      service.fail_next("Answer", "org.pipewire.Telephony.Error.InvalidState",
                        "call cannot be answered");
    } else if (command == "fail-speaker-volume") {
      service.fail_next("SetSpeakerVolume",
                        "org.pipewire.Telephony.Error.NotSupported",
                        "speaker volume is unavailable");
    } else if (command == "fail-activate") {
      service.fail_next("Activate", "org.pipewire.Telephony.Error.NotSupported",
                        "SCO activation is unavailable");
    } else if (command == "quit") {
      break;
    }
  }
}

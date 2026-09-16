#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

namespace pwt::test {

inline constexpr auto kServiceName = "org.pipewire.Telephony";
inline constexpr auto kRootPath = "/org/pipewire/Telephony";
inline constexpr auto kGatewayPath = "/org/pipewire/Telephony/ag1";
inline constexpr auto kSecondGatewayPath = "/org/pipewire/Telephony/phone42";
inline constexpr auto kCallPath = "/org/pipewire/Telephony/ag1/call1";
inline constexpr auto kGatewayInterface =
    "org.pipewire.Telephony.AudioGateway1";
inline constexpr auto kTransportInterface =
    "org.pipewire.Telephony.AudioGatewayTransport1";
inline constexpr auto kCallInterface = "org.pipewire.Telephony.Call1";

struct GatewayState {
  std::string address{"AA:BB:CC:DD:EE:FF"};
  uint8_t speakerVolume{12};
  uint8_t microphoneVolume{10};
};

struct TransportState {
  std::string state{"active"};
  uint8_t codec{2};
  bool rejectSco{};
};

struct CallState {
  std::string lineIdentification{"+123"};
  std::string incomingLine;
  std::string name{"Ada"};
  bool multiparty{};
  std::string state{"incoming"};
};

class MockTelephonyService {
public:
  explicit MockTelephonyService(std::string bus_address,
                                bool populate_initially = true);
  ~MockTelephonyService();

  MockTelephonyService(const MockTelephonyService &) = delete;
  MockTelephonyService &operator=(const MockTelephonyService &) = delete;

  void start();
  void stop();
  void restart();
  void add_gateway();
  void remove_gateway();
  void add_second_gateway();
  void remove_second_gateway();
  void add_call();
  void remove_call();

  std::string unique_owner() const;
  void fail_next(std::string operation, std::string name, std::string message);
  std::vector<std::pair<std::string, std::string>> invocations() const;
  void set_gateway_state(GatewayState state);
  void set_transport_state(TransportState state);
  void set_call_state(CallState state);

private:
  struct Failure {
    std::string name;
    std::string message;
  };

  void register_gateway(const char *path, GatewayState &state,
                        std::unique_ptr<sdbus::IObject> &object);
  void register_call();
  void invoke(std::string operation, std::string argument = {});

  const std::string bus_address_;
  const bool populate_initially_;
  mutable std::mutex mutex_;
  GatewayState gateway_state_;
  GatewayState second_gateway_state_{.address = "11:22:33:44:55:66",
                                     .speakerVolume = 7,
                                     .microphoneVolume = 8};
  TransportState transport_state_;
  CallState call_state_;
  std::map<std::string, Failure> failures_;
  std::vector<std::pair<std::string, std::string>> invocations_;
  std::unique_ptr<sdbus::IConnection> connection_;
  std::unique_ptr<sdbus::IObject> root_;
  std::unique_ptr<sdbus::IObject> gateway_;
  std::unique_ptr<sdbus::IObject> second_gateway_;
  std::unique_ptr<sdbus::IObject> call_;
};

} // namespace pwt::test

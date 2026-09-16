#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace pwt {

inline constexpr uint32_t kProtocolVersion = 1;
inline constexpr size_t kMaxMessageBytes = 1024 * 1024;

struct TargetIdentity {
  uint64_t clientGeneration{};
  uint64_t objectIncarnation{};
  std::string path;
  std::string interface;
};

struct RequestArguments {
  std::optional<std::string> text;
  std::optional<uint8_t> volume;
  std::optional<bool> value;
};

struct Request {
  uint32_t version{};
  uint64_t requestId{};
  std::string operation;
  TargetIdentity target;
  RequestArguments arguments;
};

struct Error {
  std::string category;
  std::string name;
  std::string message;
  std::string operation;
  std::string path;
};

struct Reply {
  uint32_t version{};
  uint64_t clientGeneration{};
  uint64_t sequence{};
  std::string kind;
  uint64_t requestId{};
  bool ok{};
  std::optional<Error> error;
};

struct GatewayProperties {
  std::string path;
  uint64_t incarnation{};
  std::optional<std::string> address;
  std::optional<uint8_t> speakerVolume;
  std::optional<uint8_t> microphoneVolume;
  std::vector<std::string> changed;
};

struct CallProperties {
  std::string path;
  std::string gatewayPath;
  uint64_t incarnation{};
  std::optional<std::string> lineIdentification;
  std::optional<std::string> incomingLine;
  std::optional<std::string> name;
  std::optional<bool> multiparty;
  std::optional<std::string> state;
  std::vector<std::string> changed;
};

struct TransportProperties {
  std::string path;
  uint64_t incarnation{};
  std::optional<std::string> state;
  std::optional<uint8_t> codec;
  std::optional<bool> rejectSco;
  std::vector<std::string> changed;
};

struct StartupSnapshot {
  std::vector<GatewayProperties> gateways;
  std::vector<CallProperties> calls;
  std::vector<TransportProperties> transports;
};

struct Lifecycle {
  std::string state;
};

struct EventPayload {
  std::optional<StartupSnapshot> startup;
  std::optional<Lifecycle> lifecycle;
  std::optional<GatewayProperties> gateway;
  std::optional<CallProperties> call;
  std::optional<TransportProperties> transport;
  std::optional<Error> error;
};

struct Event {
  uint32_t version{};
  uint64_t clientGeneration{};
  uint64_t sequence{};
  std::string kind;
  EventPayload payload;
};

} // namespace pwt

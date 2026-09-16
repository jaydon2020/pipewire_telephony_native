#include "gateway_registry.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "object_manager_proxy.h"

namespace pwt {
namespace {

constexpr auto kService = "org.pipewire.Telephony";
constexpr auto kRootPath = "/org/pipewire/Telephony";
constexpr auto kGatewayInterface = "org.pipewire.Telephony.AudioGateway1";

template <typename T>
std::optional<T>
property(const std::map<std::string, sdbus::Variant> &properties,
         const std::string &name) {
  const auto value = properties.find(name);
  if (value == properties.end()) {
    return std::nullopt;
  }
  try {
    return value->second.get<T>();
  } catch (const sdbus::Error &) {
    return std::nullopt;
  }
}

bool is_gateway_path(const std::string &path) {
  constexpr std::string_view prefix = "/org/pipewire/Telephony/";
  return path.starts_with(prefix) && path.size() > prefix.size();
}

} // namespace

class GatewayRegistry::ObjectManager final
    : public org::freedesktop::DBus::ObjectManager_proxy {
public:
  ObjectManager(sdbus::IProxy &proxy, GatewayRegistry &registry)
      : org::freedesktop::DBus::ObjectManager_proxy(proxy),
        registry_(registry) {
    registerProxy();
  }

private:
  void onInterfacesAdded(const sdbus::ObjectPath &path,
                         const Interfaces &interfaces) override {
    registry_.interfaces_added(path, interfaces);
  }

  void
  onInterfacesRemoved(const sdbus::ObjectPath &path,
                      const std::vector<std::string> &interfaces) override {
    registry_.interfaces_removed(path, interfaces);
  }

  GatewayRegistry &registry_;
};

GatewayRegistry::GatewayRegistry(sdbus::IConnection &connection,
                                 EventCallback callback)
    : callback_(std::move(callback)),
      proxy_(sdbus::createProxy(connection, sdbus::ServiceName{kService},
                                sdbus::ObjectPath{kRootPath})),
      manager_(std::make_unique<ObjectManager>(*proxy_, *this)) {}

GatewayRegistry::~GatewayRegistry() = default;

std::vector<GatewayProperties> GatewayRegistry::synchronize() {
  const auto objects = manager_->GetManagedObjects();
  for (const auto &[path, interfaces] : objects) {
    interfaces_added(path, interfaces);
  }
  synchronizing_ = false;

  std::vector<GatewayProperties> snapshot;
  snapshot.reserve(gateways_.size());
  for (const auto &[path, gateway] : gateways_) {
    snapshot.push_back(gateway);
  }
  return snapshot;
}

void GatewayRegistry::invalidate_all() {
  while (!gateways_.empty()) {
    const auto gateway = gateways_.begin()->second;
    gateways_.erase(gateways_.begin());
    callback_("gatewayRemoved", gateway);
  }
}

bool GatewayRegistry::contains(const std::string &path,
                               uint64_t incarnation) const {
  const auto gateway = gateways_.find(path);
  return gateway != gateways_.end() &&
         gateway->second.incarnation == incarnation;
}

void GatewayRegistry::interfaces_added(const sdbus::ObjectPath &object_path,
                                       const Interfaces &interfaces) {
  const std::string path = object_path;
  if (!is_gateway_path(path)) {
    return;
  }
  const auto interface = interfaces.find(kGatewayInterface);
  if (interface == interfaces.end()) {
    return;
  }

  const auto existing = gateways_.find(path);
  const bool added = existing == gateways_.end();
  GatewayProperties gateway{
      .path = path,
      .incarnation = added ? ++next_incarnation_ : existing->second.incarnation,
      .address = property<std::string>(interface->second, "Address"),
      .speakerVolume = property<uint8_t>(interface->second, "SpeakerVolume"),
      .microphoneVolume =
          property<uint8_t>(interface->second, "MicrophoneVolume"),
      .changed = {},
  };
  gateways_.insert_or_assign(path, gateway);
  if (!synchronizing_) {
    callback_(added ? "gatewayAdded" : "gatewayChanged", gateway);
  }
}

void GatewayRegistry::interfaces_removed(
    const sdbus::ObjectPath &object_path,
    const std::vector<std::string> &interfaces) {
  if (std::ranges::find(interfaces, kGatewayInterface) == interfaces.end()) {
    return;
  }
  const auto gateway = gateways_.find(std::string{object_path});
  if (gateway == gateways_.end()) {
    return;
  }
  const auto removed = gateway->second;
  gateways_.erase(gateway);
  if (!synchronizing_) {
    callback_("gatewayRemoved", removed);
  }
}

} // namespace pwt

#include "call_registry.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "object_manager_proxy.h"

namespace pwt {
namespace {

constexpr auto kService = "org.pipewire.Telephony";
constexpr auto kCallInterface = "org.pipewire.Telephony.Call1";

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

} // namespace

class CallRegistry::ObjectManager final
    : public org::freedesktop::DBus::ObjectManager_proxy {
public:
  ObjectManager(sdbus::IProxy &proxy, CallRegistry &registry)
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

  CallRegistry &registry_;
};

CallRegistry::CallRegistry(sdbus::IConnection &connection,
                           std::string gateway_path, uint64_t &next_incarnation,
                           EventCallback callback)
    : gateway_path_(std::move(gateway_path)),
      next_incarnation_(next_incarnation), callback_(std::move(callback)),
      proxy_(sdbus::createProxy(connection, sdbus::ServiceName{kService},
                                sdbus::ObjectPath{gateway_path_})),
      manager_(std::make_unique<ObjectManager>(*proxy_, *this)) {}

CallRegistry::~CallRegistry() = default;

void CallRegistry::synchronize() {
  const auto objects = manager_->GetManagedObjects();
  for (const auto &[path, interfaces] : objects) {
    interfaces_added(path, interfaces);
  }
}

std::vector<CallProperties> CallRegistry::activate() {
  synchronizing_ = false;

  std::vector<CallProperties> snapshot;
  snapshot.reserve(calls_.size());
  for (const auto &[path, call] : calls_) {
    snapshot.push_back(call);
  }
  return snapshot;
}

void CallRegistry::invalidate_all() {
  while (!calls_.empty()) {
    const auto call = calls_.begin()->second;
    calls_.erase(calls_.begin());
    if (!synchronizing_) {
      callback_("callRemoved", call);
    }
  }
}

bool CallRegistry::contains(const std::string &path,
                            uint64_t incarnation) const {
  const auto call = calls_.find(path);
  return call != calls_.end() && call->second.incarnation == incarnation;
}

void CallRegistry::interfaces_added(const sdbus::ObjectPath &object_path,
                                    const Interfaces &interfaces) {
  const std::string path = object_path;
  const std::string prefix = gateway_path_ + "/";
  if (!path.starts_with(prefix)) {
    return;
  }
  const auto interface = interfaces.find(kCallInterface);
  if (interface == interfaces.end()) {
    return;
  }

  const auto existing = calls_.find(path);
  const bool added = existing == calls_.end();
  CallProperties call{
      .path = path,
      .gatewayPath = gateway_path_,
      .incarnation = added ? ++next_incarnation_ : existing->second.incarnation,
      .lineIdentification =
          property<std::string>(interface->second, "LineIdentification"),
      .incomingLine = property<std::string>(interface->second, "IncomingLine"),
      .name = property<std::string>(interface->second, "Name"),
      .multiparty = property<bool>(interface->second, "Multiparty"),
      .state = property<std::string>(interface->second, "State"),
      .changed = {},
  };
  calls_.insert_or_assign(path, call);
  if (!synchronizing_) {
    callback_(added ? "callAdded" : "callChanged", call);
  }
}

void CallRegistry::interfaces_removed(
    const sdbus::ObjectPath &object_path,
    const std::vector<std::string> &interfaces) {
  if (std::ranges::find(interfaces, kCallInterface) == interfaces.end()) {
    return;
  }
  const auto call = calls_.find(std::string{object_path});
  if (call == calls_.end()) {
    return;
  }
  const auto removed = call->second;
  calls_.erase(call);
  if (!synchronizing_) {
    callback_("callRemoved", removed);
  }
}

} // namespace pwt

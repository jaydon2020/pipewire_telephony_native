#include "call_registry.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "object_manager_proxy.h"

namespace pwt {
namespace {

constexpr auto kService = "org.pipewire.Telephony";
constexpr auto kCallInterface = "org.pipewire.Telephony.Call1";
constexpr auto kPropertiesInterface = "org.freedesktop.DBus.Properties";

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
    : gateway_path_(std::move(gateway_path)), connection_(connection),
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
  refresh_revisions_.clear();
  property_proxies_.clear();
  revisions_.clear();
}

bool CallRegistry::contains(const std::string &path,
                            uint64_t incarnation) const {
  const auto call = calls_.find(path);
  return call != calls_.end() && call->second.incarnation == incarnation;
}

bool CallRegistry::properties_changed(
    const std::string &path, const std::string &interface,
    const Properties &changed, const std::vector<std::string> &invalidated) {
  const auto found = calls_.find(path);
  if (interface != kCallInterface || found == calls_.end()) {
    return false;
  }

  auto &call = found->second;
  std::vector<std::string> names;
  const auto apply = [&]<typename T>(const char *name,
                                     std::optional<T> &target) {
    if (changed.contains(name)) {
      target = property<T>(changed, name);
      names.emplace_back(name);
    }
    if (std::ranges::find(invalidated, name) != invalidated.end()) {
      target.reset();
      if (std::ranges::find(names, name) == names.end()) {
        names.emplace_back(name);
      }
    }
  };
  apply("LineIdentification", call.lineIdentification);
  apply("IncomingLine", call.incomingLine);
  apply("Name", call.name);
  apply("Multiparty", call.multiparty);
  apply("State", call.state);
  if (names.empty()) {
    return true;
  }

  call.changed = names;
  const auto revision = revisions_[path] = ++next_revision_;
  if (call.state == "disconnected") {
    const auto removed = call;
    calls_.erase(found);
    refresh_revisions_.erase(path);
    property_proxies_.erase(path);
    revisions_.erase(path);
    if (!synchronizing_) {
      callback_("callRemoved", removed);
    }
    return true;
  }
  if (!synchronizing_) {
    callback_("callChanged", call);
  }
  if (!invalidated.empty()) {
    refresh(path, call.incarnation, revision);
  }
  return true;
}

void CallRegistry::refresh(const std::string &path, uint64_t incarnation,
                           uint64_t revision) {
  refresh_revisions_.insert_or_assign(path, revision);
  auto &proxy = property_proxies_[path];
  if (!proxy) {
    proxy = sdbus::createProxy(connection_, sdbus::ServiceName{kService},
                               sdbus::ObjectPath{path});
  }
  const std::weak_ptr<int> lifetime = lifetime_;
  proxy->callMethodAsync("GetAll")
      .onInterface(kPropertiesInterface)
      .withArguments(std::string{kCallInterface})
      .uponReplyInvoke([lifetime, this, path, incarnation,
                        revision](std::optional<sdbus::Error> error,
                                  const Properties &properties) {
        if (lifetime.expired()) {
          return;
        }
        const auto requested = refresh_revisions_.find(path);
        if (requested == refresh_revisions_.end() ||
            requested->second != revision) {
          return;
        }
        refresh_revisions_.erase(requested);
        const auto call = calls_.find(path);
        if (error || call == calls_.end() ||
            call->second.incarnation != incarnation) {
          return;
        }
        if (revisions_[path] != revision) {
          refresh(path, incarnation, revisions_[path]);
          return;
        }
        replace_properties(path, properties);
      });
}

void CallRegistry::replace_properties(const std::string &path,
                                      const Properties &properties) {
  const auto found = calls_.find(path);
  if (found == calls_.end()) {
    return;
  }
  auto next = found->second;
  next.changed.clear();
  next.lineIdentification =
      property<std::string>(properties, "LineIdentification");
  next.incomingLine = property<std::string>(properties, "IncomingLine");
  next.name = property<std::string>(properties, "Name");
  next.multiparty = property<bool>(properties, "Multiparty");
  next.state = property<std::string>(properties, "State");
  if (next.lineIdentification != found->second.lineIdentification)
    next.changed.emplace_back("LineIdentification");
  if (next.incomingLine != found->second.incomingLine)
    next.changed.emplace_back("IncomingLine");
  if (next.name != found->second.name)
    next.changed.emplace_back("Name");
  if (next.multiparty != found->second.multiparty)
    next.changed.emplace_back("Multiparty");
  if (next.state != found->second.state)
    next.changed.emplace_back("State");
  revisions_[path] = ++next_revision_;
  found->second = next;
  if (!synchronizing_ && !next.changed.empty()) {
    callback_("callChanged", next);
  }
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
  revisions_[path] = ++next_revision_;
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
  refresh_revisions_.erase(removed.path);
  property_proxies_.erase(removed.path);
  revisions_.erase(removed.path);
  calls_.erase(call);
  if (!synchronizing_) {
    callback_("callRemoved", removed);
  }
}

} // namespace pwt

#pragma once

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

#include "telephony_types.h"

namespace pwt {

class CallRegistry;

struct DiscoverySnapshot {
  std::vector<GatewayProperties> gateways;
  std::vector<CallProperties> calls;
};

class GatewayRegistry {
public:
  using GatewayEventCallback =
      std::function<void(const std::string &, const GatewayProperties &)>;
  using CallEventCallback =
      std::function<void(const std::string &, const CallProperties &)>;

  GatewayRegistry(sdbus::IConnection &connection,
                  GatewayEventCallback gateway_callback,
                  CallEventCallback call_callback);
  ~GatewayRegistry();

  GatewayRegistry(const GatewayRegistry &) = delete;
  GatewayRegistry &operator=(const GatewayRegistry &) = delete;

  void synchronize();
  DiscoverySnapshot activate();
  void invalidate_all();
  bool contains(const std::string &path, uint64_t incarnation) const;
  bool contains_call(const std::string &path, uint64_t incarnation) const;

private:
  class ObjectManager;
  using Properties = std::map<std::string, sdbus::Variant>;
  using Interfaces = std::map<std::string, Properties>;

  void interfaces_added(const sdbus::ObjectPath &path,
                        const Interfaces &interfaces);
  void interfaces_removed(const sdbus::ObjectPath &path,
                          const std::vector<std::string> &interfaces);

  sdbus::IConnection &connection_;
  GatewayEventCallback gateway_callback_;
  CallEventCallback call_callback_;
  std::unique_ptr<sdbus::IProxy> proxy_;
  std::unique_ptr<ObjectManager> manager_;
  std::map<std::string, GatewayProperties> gateways_;
  std::map<std::string, std::unique_ptr<CallRegistry>> call_registries_;
  uint64_t next_incarnation_{};
  bool synchronizing_{true};
};

} // namespace pwt

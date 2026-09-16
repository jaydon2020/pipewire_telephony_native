#pragma once

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

#include "telephony_types.h"

namespace pwt {

class GatewayRegistry {
public:
  using EventCallback =
      std::function<void(const std::string &, const GatewayProperties &)>;

  GatewayRegistry(sdbus::IConnection &connection, EventCallback callback);
  ~GatewayRegistry();

  GatewayRegistry(const GatewayRegistry &) = delete;
  GatewayRegistry &operator=(const GatewayRegistry &) = delete;

  std::vector<GatewayProperties> synchronize();
  void invalidate_all();
  bool contains(const std::string &path, uint64_t incarnation) const;

private:
  class ObjectManager;
  using Properties = std::map<std::string, sdbus::Variant>;
  using Interfaces = std::map<std::string, Properties>;

  void interfaces_added(const sdbus::ObjectPath &path,
                        const Interfaces &interfaces);
  void interfaces_removed(const sdbus::ObjectPath &path,
                          const std::vector<std::string> &interfaces);

  EventCallback callback_;
  std::unique_ptr<sdbus::IProxy> proxy_;
  std::unique_ptr<ObjectManager> manager_;
  std::map<std::string, GatewayProperties> gateways_;
  uint64_t next_incarnation_{};
  bool synchronizing_{true};
};

} // namespace pwt

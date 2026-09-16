#pragma once

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

#include "telephony_types.h"

namespace pwt {

class CallRegistry {
public:
  using EventCallback =
      std::function<void(const std::string &, const CallProperties &)>;

  CallRegistry(sdbus::IConnection &connection, std::string gateway_path,
               uint64_t &next_incarnation, EventCallback callback);
  ~CallRegistry();

  CallRegistry(const CallRegistry &) = delete;
  CallRegistry &operator=(const CallRegistry &) = delete;

  void synchronize();
  std::vector<CallProperties> activate();
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

  const std::string gateway_path_;
  uint64_t &next_incarnation_;
  EventCallback callback_;
  std::unique_ptr<sdbus::IProxy> proxy_;
  std::unique_ptr<ObjectManager> manager_;
  std::map<std::string, CallProperties> calls_;
  bool synchronizing_{true};
};

} // namespace pwt

/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

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
  std::vector<TransportProperties> transports;
};

class GatewayRegistry {
public:
  using GatewayEventCallback =
      std::function<void(const std::string &, const GatewayProperties &)>;
  using CallEventCallback =
      std::function<void(const std::string &, const CallProperties &)>;
  using TransportEventCallback =
      std::function<void(const std::string &, const TransportProperties &)>;

  GatewayRegistry(sdbus::IConnection &connection,
                  GatewayEventCallback gateway_callback,
                  CallEventCallback call_callback,
                  TransportEventCallback transport_callback);
  ~GatewayRegistry();

  GatewayRegistry(const GatewayRegistry &) = delete;
  GatewayRegistry &operator=(const GatewayRegistry &) = delete;

  void synchronize();
  DiscoverySnapshot activate();
  void invalidate_all();
  bool contains(const std::string &path, uint64_t incarnation) const;
  bool contains_call(const std::string &path, uint64_t incarnation) const;
  bool contains_transport(const std::string &path, uint64_t incarnation) const;
  std::optional<std::string> gateway_path_for_call(const std::string &path,
                                                   uint64_t incarnation) const;
  bool apply_gateway_refresh(
      const std::string &path, uint64_t incarnation,
      const std::map<std::string, sdbus::Variant> &properties);
  bool
  apply_call_refresh(const std::string &path, uint64_t incarnation,
                     const std::map<std::string, sdbus::Variant> &properties);
  bool apply_transport_refresh(
      const std::string &path, uint64_t incarnation,
      const std::map<std::string, sdbus::Variant> &properties);
  void reconcile(const std::string &gateway_path);

private:
  class ObjectManager;
  using Properties = std::map<std::string, sdbus::Variant>;
  using Interfaces = std::map<std::string, Properties>;

  void interfaces_added(const sdbus::ObjectPath &path,
                        const Interfaces &interfaces);
  void interfaces_removed(const sdbus::ObjectPath &path,
                          const std::vector<std::string> &interfaces);
  void properties_changed(const std::string &path, const std::string &interface,
                          const Properties &changed,
                          const std::vector<std::string> &invalidated);
  void refresh_gateway(const std::string &path, uint64_t incarnation,
                       uint64_t revision);
  void replace_gateway_properties(const std::string &path,
                                  const Properties &properties);
  void refresh_transport(const std::string &path, uint64_t incarnation,
                         uint64_t revision);
  void replace_transport_properties(const std::string &path,
                                    const Properties &properties);

  sdbus::IConnection &connection_;
  GatewayEventCallback gateway_callback_;
  CallEventCallback call_callback_;
  TransportEventCallback transport_callback_;
  std::unique_ptr<sdbus::IProxy> proxy_;
  std::unique_ptr<ObjectManager> manager_;
  sdbus::Slot properties_subscription_;
  std::map<std::string, GatewayProperties> gateways_;
  std::map<std::string, TransportProperties> transports_;
  std::map<std::string, std::unique_ptr<CallRegistry>> call_registries_;
  uint64_t next_incarnation_{};
  std::map<std::string, uint64_t> revisions_;
  std::map<std::string, std::unique_ptr<sdbus::IProxy>> property_proxies_;
  std::map<std::string, uint64_t> refresh_revisions_;
  std::map<std::string, uint64_t> transport_revisions_;
  std::map<std::string, uint64_t> transport_refresh_revisions_;
  uint64_t next_revision_{};
  bool synchronizing_{true};
  std::shared_ptr<int> lifetime_{std::make_shared<int>(0)};
};

} // namespace pwt

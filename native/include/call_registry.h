/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
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
  bool properties_changed(const std::string &path, const std::string &interface,
                          const std::map<std::string, sdbus::Variant> &changed,
                          const std::vector<std::string> &invalidated);
  bool apply_refresh(const std::string &path, uint64_t incarnation,
                     const std::map<std::string, sdbus::Variant> &properties);
  void reconcile();

private:
  class ObjectManager;
  using Properties = std::map<std::string, sdbus::Variant>;
  using Interfaces = std::map<std::string, Properties>;

  void interfaces_added(const sdbus::ObjectPath &path,
                        const Interfaces &interfaces);
  void interfaces_removed(const sdbus::ObjectPath &path,
                          const std::vector<std::string> &interfaces);
  void refresh(const std::string &path, uint64_t incarnation,
               uint64_t revision);
  void replace_properties(const std::string &path,
                          const Properties &properties);

  const std::string gateway_path_;
  sdbus::IConnection &connection_;
  uint64_t &next_incarnation_;
  EventCallback callback_;
  std::unique_ptr<sdbus::IProxy> proxy_;
  std::unique_ptr<ObjectManager> manager_;
  std::map<std::string, CallProperties> calls_;
  std::map<std::string, uint64_t> revisions_;
  std::map<std::string, std::unique_ptr<sdbus::IProxy>> property_proxies_;
  std::map<std::string, uint64_t> refresh_revisions_;
  uint64_t next_revision_{};
  bool synchronizing_{true};
  std::shared_ptr<int> lifetime_{std::make_shared<int>(0)};
};

} // namespace pwt
